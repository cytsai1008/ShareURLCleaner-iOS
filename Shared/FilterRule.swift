import Foundation

/// A single tracking-parameter removal rule. `domain == nil` means it applies to every host.
/// Port of `FilterRule` from the Android app.
struct FilterRule: Equatable {
    let domain: String?
    let param: String
}
