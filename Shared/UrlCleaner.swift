import Foundation

/// Strips tracking query parameters from a URL according to the filter rules.
/// Port of `UrlCleaner.kt`. Only touches http/https URLs; anything else is returned untouched.
enum UrlCleaner {

    static func clean(_ rawUrl: String, rules: [FilterRule]) -> String {
        guard var components = URLComponents(string: rawUrl),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
        else { return rawUrl }

        var paramsToRemove = Set<String>()
        for rule in rules {
            if rule.domain == nil || host == rule.domain || host.hasSuffix(".\(rule.domain!)") {
                paramsToRemove.insert(rule.param.lowercased())
            }
        }
        if paramsToRemove.isEmpty { return rawUrl }

        guard let items = components.queryItems, !items.isEmpty else { return rawUrl }
        let kept = items.filter { !paramsToRemove.contains($0.name.lowercased()) }
        if kept.count == items.count { return rawUrl }

        components.queryItems = kept.isEmpty ? nil : kept
        return components.string ?? rawUrl
    }
}
