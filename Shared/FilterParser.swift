import Foundation

/// Parses AdGuard `$removeparam` filter syntax into `FilterRule`s.
/// Port of `FilterRepository.parseLine`.
enum FilterParser {

    static func parse(_ contents: String) -> [FilterRule] {
        contents.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> FilterRule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("@@") { return nil }

        let marker = "$removeparam="
        guard let markerRange = trimmed.range(of: marker) else { return nil }

        let afterMarker = trimmed[markerRange.upperBound...]
        let param = afterMarker.split(separator: ",", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if param.isEmpty { return nil }

        // Domain-scoped: ||example.com^$removeparam=...
        if trimmed.hasPrefix("||") {
            let afterPipes = trimmed.dropFirst(2)
            let domainPart = afterPipes.split(separator: "^", maxSplits: 1).first ?? ""
            let domain = domainPart.split(separator: "/", maxSplits: 1).first
                .map { $0.lowercased() } ?? ""
            return FilterRule(domain: domain, param: param)
        }
        return FilterRule(domain: nil, param: param)
    }
}
