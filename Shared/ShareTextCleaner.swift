import Foundation

/// Cleans every http(s) URL inside shared text, leaving surrounding text intact.
/// Port of `ShareTextCleaner.kt`.
enum ShareTextCleaner {

    struct Result {
        let text: String
        let foundUrl: Bool
        let cleaned: Bool
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://\S+"#)

    /// Whether there is anything here worth cleaning, without doing the work.
    static func hasUrl(_ text: String) -> Bool {
        urlRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Cleans every URL in `text` — a shared caption often carries several, and the one the user
    /// cares about is not always the first.
    ///
    /// Every distinct URL is resolved concurrently, so a caption with three shorteners waits for
    /// the slowest one rather than the sum of all three.
    ///
    /// - Parameter resolve: optional aggressive-mode redirect resolver. When supplied, each
    ///   cleaned URL is followed to its destination and the destination is cleaned in turn.
    ///   Return nil to skip (not applicable / failed).
    static func cleanUrls(
        _ text: String,
        rules: [FilterRule],
        resolve: (@Sendable (String) async -> String?)? = nil
    ) async -> Result {
        let ranges = urlRegex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        if ranges.isEmpty { return Result(text: text, foundUrl: false, cleaned: false) }

        var cleanedUrls: [String: String] = [:]
        for range in ranges {
            let raw = String(text[range])
            if cleanedUrls[raw] == nil { cleanedUrls[raw] = UrlCleaner.clean(raw, rules: rules) }
        }

        // Keyed by the cleaned URL, so the same link twice in one caption costs one fetch.
        var resolved: [String: String] = [:]
        if let resolve {
            await withTaskGroup(of: (String, String?).self) { group in
                for url in Set(cleanedUrls.values) {
                    group.addTask { (url, await resolve(url)) }
                }
                for await (url, destination) in group {
                    if let destination { resolved[url] = destination }
                }
            }
        }

        var out = ""
        var cursor = text.startIndex
        for range in ranges {
            let cleaned = cleanedUrls[String(text[range])] ?? String(text[range])
            let destination = resolved[cleaned]
            out += text[cursor..<range.lowerBound]
            out += (destination != nil && destination != cleaned)
                ? UrlCleaner.clean(destination!, rules: rules)
                : cleaned
            cursor = range.upperBound
        }
        out += text[cursor...]

        return Result(text: out, foundUrl: true, cleaned: out != text)
    }
}
