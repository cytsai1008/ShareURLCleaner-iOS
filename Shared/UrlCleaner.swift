import Foundation

/// Strips tracking query parameters from a URL according to the filter rules.
/// Port of `UrlCleaner.kt`. Only touches http/https URLs; anything else is returned untouched.
nonisolated enum UrlCleaner {

    static func clean(_ rawUrl: String, rules: [FilterRule]) -> String {
        guard var components = URLComponents(string: rawUrl),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
        else { return rawUrl }

        var paramsToRemove = Set<String>()
        var patternsToRemove = [NSRegularExpression]()
        for rule in rules where rule.domains?.contains(where: { hostMatches(host, $0) }) ?? true {
            if let regex = rule.regex { patternsToRemove.append(regex) } else {
                paramsToRemove.insert(rule.param.lowercased())
            }
        }
        if paramsToRemove.isEmpty && patternsToRemove.isEmpty { return rawUrl }

        guard let items = components.queryItems, !items.isEmpty else { return rawUrl }
        let kept = items.filter { item in
            if paramsToRemove.contains(item.name.lowercased()) { return false }
            let pair = "\(item.name)=\(item.value ?? "")"
            let range = NSRange(pair.startIndex..., in: pair)
            return !patternsToRemove.contains { $0.firstMatch(in: pair, range: range) != nil }
        }
        if kept.count == items.count { return rawUrl }

        components.queryItems = kept.isEmpty ? nil : kept
        return components.string ?? rawUrl
    }

    /// Whether `host` falls under a rule's `domain=` entry, including AdGuard's TLD wildcard
    /// (`shopee.*` — the same brand on every country domain). Over 100 rules in the shipped
    /// lists are written that way, and all of them used to match nothing.
    private static func hostMatches(_ host: String, _ domain: String) -> Bool {
        if domain.hasSuffix(".*") {
            // "shopee." — matches shopee.tw and s.shopee.tw, not myshopee.tw.
            let base = String(domain.dropLast())
            return host.hasPrefix(base) || host.contains(".\(base)")
        }
        return host == domain || host.hasSuffix(".\(domain)")
    }
}
