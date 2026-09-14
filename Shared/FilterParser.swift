import Foundation

/// Parses AdGuard `$removeparam` filter syntax into `FilterRule`s.
/// Port of `FilterRepository.parseLine` / `hostFromPattern`.
enum FilterParser {

    static func parse(_ contents: String) -> [FilterRule] {
        contents.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    /// One rule is `pattern$option,option,option`. Scope arrives three different ways and all
    /// three must be honoured — anything treated as global gets stripped from every site:
    ///
    ///     ||facebook.com^$removeparam=rdid                -> facebook.com
    ///     $removeparam=id,domain=skimlinks.com|hanes.com  -> those two hosts
    ///     ://www.bilibili.com/video/$removeparam=mid      -> www.bilibili.com
    ///
    /// `removeparam` is not always the first option (`$doc,removeparam=ref`), so the option list
    /// is split before looking for it rather than string-matching `"$removeparam="`.
    static func parseLine(_ line: String) -> FilterRule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("@@") { return nil }

        guard let optionsStart = trimmed.lastIndex(of: "$") else { return nil }
        let pattern = String(trimmed[..<optionsStart])
        let options = trimmed[trimmed.index(after: optionsStart)...]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)

        guard let paramOption = options.first(where: {
            $0 == "removeparam" || $0.hasPrefix("removeparam=")
        }) else { return nil }
        let param = paramOption.drop(while: { $0 != "=" }).dropFirst()
            .trimmingCharacters(in: .whitespaces)
        // Bare `$removeparam` (strip everything), regex params and inverted params are all out
        // of scope — better to skip than to guess.
        if param.isEmpty || param.hasPrefix("/") || param.hasPrefix("~") { return nil }

        if let domainOption = options.first(where: { $0.hasPrefix("domain=") }) {
            let domains = domainOption.dropFirst("domain=".count)
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                // `~host` excludes a host. A list of nothing but exclusions means "everywhere but
                // these", which is a global rule as far as this app is concerned.
                .filter { !$0.isEmpty && !$0.hasPrefix("~") }
            return FilterRule(domains: domains.isEmpty ? nil : domains, param: param)
        }

        if let host = hostFromPattern(pattern) {
            return FilterRule(domains: [host], param: param)
        }

        // No host anywhere. An empty pattern (`$removeparam=fbclid`) really is global, but a
        // non-empty one scopes by URL substring (`ref=shadcn.com^$removeparam=ref`) — a match
        // mode this app doesn't implement. Skipping is the conservative read.
        if !pattern.isEmpty { return nil }

        return FilterRule(domains: nil, param: param)
    }

    /// The host a rule pattern is anchored to, or nil when it matches any host.
    private static func hostFromPattern(_ pattern: String) -> String? {
        let afterAnchor: Substring
        if pattern.hasPrefix("||") {
            afterAnchor = pattern.dropFirst(2)
        } else if let scheme = pattern.range(of: "://") {
            afterAnchor = pattern[scheme.upperBound...]
        } else {
            return nil
        }
        let host = afterAnchor
            .prefix { $0 != "^" && $0 != "/" && $0 != "*" && $0 != "?" }
            .lowercased()
        if host.isEmpty { return nil }
        // `||shopee.*^` truncates to "shopee." — keep it as the TLD wildcard the rule meant,
        // which the host matcher understands, instead of a host ending in a dot.
        return host.hasSuffix(".") ? host + "*" : host
    }
}
