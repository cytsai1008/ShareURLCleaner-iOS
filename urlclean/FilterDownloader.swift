import Foundation

/// Downloads the AdGuard filter list, parses it, and persists the rules.
/// Shared by the Update-Now button and the background refresh task.
enum FilterDownloader {

    enum DownloadError: LocalizedError {
        case badURL
        case http(Int)
        case storeFailed

        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid filter URL"
            case .http(let code): return "Download failed (HTTP \(code))"
            case .storeFailed: return "Could not save rules (App Group unavailable)"
            }
        }
    }

    /// Downloads from `urlString`, saves the rules, updates `Settings`, returns the rule count.
    @discardableResult
    static func update(from urlString: String) async throws -> Int {
        guard let url = URL(string: urlString) else { throw DownloadError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode)
        }

        let contents = String(decoding: data, as: UTF8.self)
        let rules = FilterParser.parse(contents)
        guard FilterStore.save(rules) else { throw DownloadError.storeFailed }

        Settings.ruleCount = rules.count
        Settings.lastUpdated = Date()
        return rules.count
    }
}
