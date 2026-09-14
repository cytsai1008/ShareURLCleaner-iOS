import Foundation

/// Persists filter rules in the shared App Group container so the app and the share extension
/// read the same `filter_rules.txt`. On-disk format matches the Android app: one rule per line,
/// `a.com|b.com<TAB>param` for domain rules, bare `param` for global ones. A file written by an
/// older build has one domain and no '|', so it still reads back correctly.
enum FilterStore {

    static let appGroupID = "group.com.cytsai.urlclean"
    private static let fileName = "filter_rules.txt"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Loads the downloaded rules. Empty until the first successful update (matches the Android app).
    static func loadRules() -> [FilterRule] {
        guard let url = fileURL,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }

        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            switch parts.count {
            case 1:
                return parts[0].isEmpty ? nil : FilterRule(domains: nil, param: String(parts[0]))
            case 2:
                return FilterRule(domains: parts[0].split(separator: "|").map(String.init),
                                  param: String(parts[1]))
            default:
                return nil
            }
        }
    }

    /// Atomically writes rules to the container. Returns false if the App Group is unavailable.
    @discardableResult
    static func save(_ rules: [FilterRule]) -> Bool {
        guard let url = fileURL else { return false }
        let body = rules.map { rule in
            rule.domains.map { "\($0.joined(separator: "|"))\t\(rule.param)" } ?? rule.param
        }.joined(separator: "\n")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
