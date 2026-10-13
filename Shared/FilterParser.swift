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

        guard let optionsStart = optionsStart(in: trimmed) else { return nil }
        let pattern = String(trimmed[..<optionsStart])
        let options = splitUnescapedCommas(trimmed[trimmed.index(after: optionsStart)...])

        guard let paramOption = options.first(where: {
            $0 == "removeparam" || $0.hasPrefix("removeparam=")
        }) else { return nil }
        let param = paramOption.drop(while: { $0 != "=" }).dropFirst()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\$", with: "$")
        // Bare `$removeparam` (strip everything) and inverted params are out of scope — better
        // to skip than to guess. So is a regex ICU can't compile.
        if param.isEmpty || param.hasPrefix("~") { return nil }
        if param.hasPrefix("/") && FilterRule(domains: nil, param: param).regex == nil { return nil }

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

    /// The options `$` is the last unescaped one followed by an option name — a regex's own end
    /// anchor (`.*$/`) is followed by `/` or `)` instead. Regex values escape `$` as `\$`.
    private static func optionsStart(in line: String) -> String.Index? {
        line.indices.last { i in
            line[i] == "$" && (i == line.startIndex || line[line.index(before: i)] != "\\")
                && isOptionStart(line, i)
        }
    }

    private static func isOptionStart(_ line: String, _ i: String.Index) -> Bool {
        let next = line.index(after: i)
        return next < line.endIndex && (line[next] == "~" || ("a"..."z").contains(line[next]))
    }

    /// Regex values escape `,` as `\,` so it doesn't end the option.
    private static func splitUnescapedCommas(_ s: Substring) -> [String] {
        var parts = [""]
        var prev: Character?
        for c in s {
            if c == ",", prev != "\\" { parts.append("") } else { parts[parts.count - 1].append(c) }
            prev = c
        }
        return parts
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
