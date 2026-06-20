import Foundation

/// Cleans the first http(s) URL found inside shared text, leaving surrounding text intact.
/// Port of `ShareTextCleaner.kt`.
enum ShareTextCleaner {

    struct Result {
        let text: String
        let foundUrl: Bool
        let cleaned: Bool
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://\S+"#)

    static func cleanFirstUrl(_ text: String, rules: [FilterRule]) -> Result {
        let full = NSRange(text.startIndex..., in: text)
        guard let match = urlRegex.firstMatch(in: text, range: full),
              let range = Range(match.range, in: text)
        else { return Result(text: text, foundUrl: false, cleaned: false) }

        if rules.isEmpty {
            return Result(text: text, foundUrl: true, cleaned: false)
        }

        let cleanedUrl = UrlCleaner.clean(String(text[range]), rules: rules)
        let cleanedText = text.replacingCharacters(in: range, with: cleanedUrl)
        return Result(text: cleanedText, foundUrl: true, cleaned: cleanedText != text)
    }
}
