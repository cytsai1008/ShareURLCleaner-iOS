import Foundation

/// A single tracking-parameter removal rule. `domains == nil` means it applies to every host.
/// Port of `FilterRule` from the Android app.
struct FilterRule: Equatable, Hashable, Sendable {
    /// Hosts (and their subdomains) the rule is scoped to, or nil for a global rule.
    /// An entry ending in `.*` is AdGuard's TLD wildcard (`shopee.*`).
    let domains: [String]?
    let param: String
}
