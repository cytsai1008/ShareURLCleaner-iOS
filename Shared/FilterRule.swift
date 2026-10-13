import Foundation

/// A single tracking-parameter removal rule. `domains == nil` means it applies to every host.
/// Port of `FilterRule` from the Android app.
nonisolated struct FilterRule: Equatable, Hashable, Sendable {
    /// Hosts (and their subdomains) the rule is scoped to, or nil for a global rule.
    /// An entry ending in `.*` is AdGuard's TLD wildcard (`shopee.*`).
    let domains: [String]?
    let param: String

    /// Set when `param` is an AdGuard `/regex/flags` value, matched against `name=value` the way
    /// AdGuard does — needed for params whose name is random on every share. Recompiled per
    /// call; only regex rules pay for it, and few exist.
    var regex: NSRegularExpression? {
        guard let end = param.lastIndex(of: "/"), param.hasPrefix("/"),
              param.distance(from: param.startIndex, to: end) >= 2 else { return nil }
        let flags = param[param.index(after: end)...]
        if flags.contains(where: { $0 != "i" }) { return nil }
        // JS-only syntax ICU can't compile: no regex, and the parser drops the rule.
        return try? NSRegularExpression(
            pattern: String(param[param.index(after: param.startIndex)..<end]),
            options: flags.isEmpty ? [] : .caseInsensitive
        )
    }
}
