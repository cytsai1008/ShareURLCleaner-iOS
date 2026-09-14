import Foundation

/// Follows HTTP redirects (302 and friends) to the destination URL.
///
/// `URLSession` follows redirect chains itself, so the final URL is simply `response.url` —
/// no need to walk `Location` headers.
///
/// Interstitials that answer 200 and hand off in JavaScript instead
/// (`document.location.replace("…")`) are followed too, as one more hop.
///
/// The chain is followed to its end rather than to a fixed depth: shorteners routinely point at
/// other shorteners, so the dive continues while each new URL is still one the caller wants
/// followed, and stops once a destination neither redirects nor hands off.
///
/// Port of `RedirectResolver.kt`.
enum RedirectResolver {

    /// Whether to follow redirects to the real destination before cleaning.
    enum Mode: String, CaseIterable, Sendable {
        case off = "OFF"
        case selected = "SELECTED"
        case all = "ALL"
    }

    /// Pinned deliberately — redirect behaviour is highly User-Agent sensitive.
    ///
    /// Measured against threads.com, facebook.com and b23.tv:
    ///  - Browser UAs (mobile and desktop Chrome) get a JS handoff and never redirect at all;
    ///    Facebook answers 400 outright.
    ///  - The HTTP client's own default UA is singled out by Meta and lands on a login wall,
    ///    `m.facebook.com/login/?next=…`, which is worse than the link we started with.
    ///  - Any other non-browser UA gets the plain 302 to the real content. This one does.
    private static let userAgent = "curl/8.7.1"

    // ponytail: aggressive timeouts on purpose — this runs in the share path, so a slow host
    // must degrade to "share the URL as-is", never stall the share sheet.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    /// Safety backstop, not a policy. The chain runs until the URL stops moving; this only bounds
    /// a loop that slips past the visited set — a redirector minting a fresh URL on every hop.
    private static let maxHops = 10

    /// Enough for a handoff stub; a real page's redirect script sits in the first bytes too.
    private static let maxBodyBytes = 64 * 1024

    /// A JS handoff: `location.replace("…")`, `location.href = "…"`, `location = "…"`, with or
    /// without a `window.`/`document.` prefix. Only absolute http(s) targets — a relative one
    /// would land on the same interstitial we are trying to leave.
    private static let jsRedirect = try! NSRegularExpression(
        pattern: #"location(?:\.href)?\s*=\s*["'](https?:[^"']+)["']"#
            + #"|location\.(?:replace|assign)\(\s*["'](https?:[^"']+)["']"#,
        options: .caseInsensitive
    )

    /// Follows the chain to the end.
    ///
    /// Keeps diving for as long as the URL it lands on is still one worth following: a shortener
    /// pointing at a shortener pointing at the real page is one share, not three. It stops when
    /// the destination answers without a redirect and without a JS handoff, when `shouldFollow`
    /// turns the new host down, or when the chain doubles back on somewhere it has already been.
    ///
    /// Returns nil only when nothing was learned: a hop that fails after the chain already moved
    /// keeps the progress, because a half-followed shortener is still better than the shortener.
    ///
    /// - Parameters:
    ///   - shouldFollow: gates each URL in turn, not just the first — the domain list applies to
    ///     the whole chain, so a hop that leaves it ends the dive.
    ///   - clean: applied to every hop, so tracking params picked up along the way never reach the
    ///     next request or the shared result.
    ///   - hop: one step of the chain. Defaults to the real network call; overridden in tests,
    ///     which is the only way to exercise the loop without a live server.
    static func resolve(
        _ url: String,
        shouldFollow: (String) -> Bool = { _ in true },
        clean: (String) -> String = { $0 },
        hop: (String) async throws -> String? = hop
    ) async -> String? {
        let start = clean(url)
        var current = start
        var visited: Set<String> = [current]
        var failed = false

        for _ in 0..<maxHops {
            if !shouldFollow(current) { break }
            var next: String?
            do {
                next = try await hop(current)
            } catch {
                failed = true
                next = nil
            }
            guard let next else { break }
            let cleaned = clean(next)
            // A URL seen before means a cycle; anything further would just go round again.
            if !visited.insert(cleaned).inserted { break }
            current = cleaned
        }
        return (failed && current == start) ? nil : current
    }

    /// One step of the chain, or nil once `url` stops pointing anywhere else.
    private static func hop(_ url: String) async throws -> String? {
        guard let target = URL(string: url) else { return nil }

        // HEAD avoids downloading the body; some hosts only redirect on GET, and a JS handoff
        // is invisible without one, so fall back when HEAD lands us nowhere new.
        var head = URLRequest(url: target)
        head.httpMethod = "HEAD"
        if let viaHead = try await finalUrl(head), viaHead != url { return viaHead }

        // ponytail: URLSession has no `peekBody`, so the whole body is read and then truncated.
        // `timeoutIntervalForResource` caps the cost; switch to a delegate-based byte cap if a
        // multi-megabyte interstitial ever shows up.
        let (data, response) = try await session.data(for: URLRequest(url: target))
        let viaGet = response.url?.absoluteString ?? url
        if viaGet != url { return viaGet }
        return jsRedirectIn(String(decoding: data.prefix(maxBodyBytes), as: UTF8.self))
    }

    /// The URL the redirect chain ended at, whatever the final status code.
    ///
    /// Deliberately not gated on a 2xx status: b23.tv answers 412 on the destination while still
    /// having redirected correctly, and an error page's address is still the address we were
    /// sent to.
    private static func finalUrl(_ request: URLRequest) async throws -> String? {
        let (_, response) = try await session.data(for: request)
        return response.url?.absoluteString
    }

    /// The target of a JavaScript handoff in `body`, or nil if there isn't one.
    static func jsRedirectIn(_ body: String) -> String? {
        guard let match = jsRedirect.firstMatch(
            in: body, range: NSRange(body.startIndex..., in: body)
        ) else { return nil }

        let captured = (1..<match.numberOfRanges)
            .compactMap { Range(match.range(at: $0), in: body).map { String(body[$0]) } }
            .first { !$0.isEmpty }
        guard let captured else { return nil }

        // Inline scripts escape the slashes: "https:\/\/example.com", and `%` and friends —
        // Meta escapes the percent signs of a nested URL that way.
        let unescaped = unescapeUnicode(captured.replacingOccurrences(of: #"\/"#, with: "/"))
        return URL(string: unescaped) != nil ? unescaped : nil
    }

    private static let unicodeEscape = try! NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#)

    private static func unescapeUnicode(_ text: String) -> String {
        var out = text
        for match in unicodeEscape.matches(
            in: text, range: NSRange(text.startIndex..., in: text)
        ).reversed() {
            guard let whole = Range(match.range, in: out),
                  let digits = Range(match.range(at: 1), in: text),
                  let code = UInt32(text[digits], radix: 16),
                  let scalar = Unicode.Scalar(code)
            else { continue }
            out.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return out
    }

    /// Whether `url` would actually be fetched under `mode` — checked before any network call.
    static func appliesTo(_ mode: Mode, domains: Set<String>, url: String) -> Bool {
        switch mode {
        case .off:
            return false
        case .all:
            return isHttp(url)
        case .selected:
            guard isHttp(url), let host = URLComponents(string: url)?.host?.lowercased() else {
                return false
            }
            return domains.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
    }

    private static func isHttp(_ url: String) -> Bool {
        guard let scheme = URLComponents(string: url)?.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https")
            && URLComponents(string: url)?.host?.isEmpty == false
    }

    /// Returns a resolver for `mode`, or nil when redirect following is off entirely.
    ///
    /// `onFailure` fires only when a fetch was actually attempted and came back empty, which is
    /// what distinguishes "the network let us down" from the far more common "this host isn't one
    /// we follow" — both of which return nil to the caller.
    ///
    /// - Parameters:
    ///   - onFetch: fires just before a network call, so callers can show progress.
    ///   - clean: applied to every URL in the chain — pass the filter rules in here.
    static func forMode(
        _ mode: Mode,
        domains: Set<String>,
        onFailure: @escaping @Sendable () -> Void = {},
        onFetch: @escaping @Sendable () -> Void = {},
        clean: @escaping @Sendable (String) -> String = { $0 }
    ) -> (@Sendable (String) async -> String?)? {
        if mode == .off { return nil }
        if mode == .selected && domains.isEmpty { return nil }
        return { url in
            guard appliesTo(mode, domains: domains, url: url) else { return nil }
            onFetch()
            // The same gate guards every hop: under .selected the dive ends the moment it lands
            // off the list, under .all it runs to the real destination.
            let result = await resolve(
                url,
                shouldFollow: { appliesTo(mode, domains: domains, url: $0) },
                clean: clean
            )
            if result == nil { onFailure() }
            return result
        }
    }
}
