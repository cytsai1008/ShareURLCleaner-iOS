import Foundation

/// Downloads the enabled filter lists, parses them, and persists the merged rule set.
/// Shared by the Update-Now button and the background refresh task.
/// Port of `FilterRepository.downloadAndUpdate`.
enum FilterDownloader {

    enum DownloadError: LocalizedError {
        case noneEnabled
        case badURL(String)
        case http(Int, String)
        case rateLimited(String)
        case storeFailed

        var errorDescription: String? {
            switch self {
            case .noneEnabled: return "No filter lists enabled"
            case .badURL(let url): return "Invalid filter URL: \(url)"
            case .http(let code, let url): return "Download failed (HTTP \(code)) for \(url)"
            case .rateLimited(let url): return "Rate limited: \(url)"
            case .storeFailed: return "Could not save rules (App Group unavailable)"
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private static let gitHubHosts: Set<String> = [
        "github.com",
        "raw.githubusercontent.com",
        "gist.githubusercontent.com",
        "objects.githubusercontent.com",
    ]

    /// Above this many GitHub-hosted lists in one run, space the requests out.
    ///
    /// All four built-ins are on raw.githubusercontent.com, which serves static files far more
    /// generously than the API — so the default set no longer pays the delay. Real rate limiting
    /// is handled where it actually shows up, in `rateLimitedBackoff`.
    private static let gitHubCooldownThreshold = 6
    private static let gitHubCooldown: UInt64 = 750_000_000

    /// Backoff after GitHub actually says no (429, or 403 with a rate-limit body).
    private static let rateLimitedBackoff: UInt64 = 5_000_000_000

    private static func isGitHub(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return gitHubHosts.contains(host) || host.hasSuffix(".githubusercontent.com")
    }

    /// Downloads every `urls` entry and writes the merged, de-duplicated rule set.
    ///
    /// All-or-nothing on purpose: a single failed list aborts the run and leaves the previous
    /// `filter_rules.txt` in place, rather than silently shrinking the user's protection.
    @discardableResult
    static func update(from urls: [String]) async throws -> Int {
        if urls.isEmpty { throw DownloadError.noneEnabled }

        let spaceOutGitHub = urls.filter(isGitHub).count > gitHubCooldownThreshold
        var gitHubFetched = 0

        var rules: [FilterRule] = []
        var seen = Set<FilterRule>()
        for url in urls {
            if isGitHub(url) {
                if spaceOutGitHub && gitHubFetched > 0 {
                    try? await Task.sleep(nanoseconds: gitHubCooldown)
                }
                gitHubFetched += 1
            }
            for rule in FilterParser.parse(try await fetch(url)) where seen.insert(rule).inserted {
                rules.append(rule)
            }
        }

        guard FilterStore.save(rules) else { throw DownloadError.storeFailed }
        Settings.ruleCount = rules.count
        Settings.lastUpdated = Date()
        return rules.count
    }

    /// Retries once after a pause when GitHub reports rate limiting.
    private static func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw DownloadError.badURL(urlString) }

        for attempt in 0..<2 {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            if (200..<300).contains(code) { return String(decoding: data, as: UTF8.self) }

            let rateLimited = code == 429 || (code == 403 && isGitHub(urlString))
            if !rateLimited || attempt == 1 { throw DownloadError.http(code, urlString) }
            try? await Task.sleep(nanoseconds: rateLimitedBackoff)
        }
        throw DownloadError.rateLimited(urlString)
    }
}
