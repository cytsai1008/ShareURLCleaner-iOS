// Standalone self-check for the pure cleaning logic (no app/UIKit deps).
// Run (this file holds the top-level code, so swiftc needs it named main.swift):
//   d=$(mktemp -d)
//   cp Shared/{FilterRule,UrlCleaner,ShareTextCleaner,FilterParser,RedirectResolver}.swift "$d"
//   cp Tests/SelfCheck.swift "$d/main.swift"; (cd "$d" && swiftc *.swift -o check && ./check)
import Foundation

func check(_ cond: Bool, _ msg: String) {
    if !cond { print("FAIL: \(msg)"); exit(1) }
}

func global(_ param: String) -> FilterRule { FilterRule(domains: nil, param: param) }

// MARK: - UrlCleaner

// Drops matching param, keeps the rest.
check(
    UrlCleaner.clean("https://example.com/page?utm_source=n&id=123", rules: [global("utm_source")])
        == "https://example.com/page?id=123",
    "global param removed")

// Unmatched rule leaves URL untouched.
check(
    UrlCleaner.clean("https://example.com/page?utm_source=n&id=123",
                     rules: [FilterRule(domains: ["other.example"], param: "utm_source")])
        == "https://example.com/page?utm_source=n&id=123",
    "non-matching domain rule no-ops")

// Domain rule matches host and subdomain only.
let fbRule = [FilterRule(domains: ["facebook.com"], param: "fbclid")]
check(UrlCleaner.clean("https://m.facebook.com/p?fbclid=x&a=1", rules: fbRule)
        == "https://m.facebook.com/p?a=1", "subdomain match")
check(UrlCleaner.clean("https://twitter.com/p?fbclid=x&a=1", rules: fbRule)
        == "https://twitter.com/p?fbclid=x&a=1", "other host untouched")

// A rule listing several domains applies to each of them.
let multi = [FilterRule(domains: ["skimlinks.com", "hanes.com"], param: "id")]
check(UrlCleaner.clean("https://hanes.com/p?id=x&a=1", rules: multi)
        == "https://hanes.com/p?a=1", "second domain of a multi-domain rule matches")

// AdGuard TLD wildcard: shopee.* covers every country domain, and their subdomains.
let shopee = [FilterRule(domains: ["shopee.*"], param: "af_siteid")]
check(UrlCleaner.clean("https://shopee.tw/p?af_siteid=x&a=1", rules: shopee)
        == "https://shopee.tw/p?a=1", "tld wildcard matches base host")
check(UrlCleaner.clean("https://s.shopee.tw/p?af_siteid=x&a=1", rules: shopee)
        == "https://s.shopee.tw/p?a=1", "tld wildcard matches subdomain")
check(UrlCleaner.clean("https://myshopee.tw/p?af_siteid=x", rules: shopee)
        == "https://myshopee.tw/p?af_siteid=x", "tld wildcard does not match a longer brand")

// Case-insensitive param match.
check(UrlCleaner.clean("https://e.com/p?UTM_Source=n&id=1", rules: [global("utm_source")])
        == "https://e.com/p?id=1", "case-insensitive param")

// Non-http URL returned as-is.
check(UrlCleaner.clean("ftp://e.com/p?utm_source=n", rules: [global("utm_source")])
        == "ftp://e.com/p?utm_source=n", "non-http untouched")

// MARK: - ShareTextCleaner

func cleanSync(_ text: String, _ rules: [FilterRule],
               _ resolve: (@Sendable (String) async -> String?)? = nil) -> ShareTextCleaner.Result {
    let box = UnsafeMutablePointer<ShareTextCleaner.Result?>.allocate(capacity: 1)
    box.initialize(to: nil)
    let done = DispatchSemaphore(value: 0)
    Task {
        box.pointee = await ShareTextCleaner.cleanUrls(text, rules: rules, resolve: resolve)
        done.signal()
    }
    done.wait()
    let result = box.pointee!
    box.deallocate()
    return result
}

let r1 = cleanSync("Look https://e.com/p?gclid=x&id=1 here", [global("gclid")])
check(r1.text == "Look https://e.com/p?id=1 here" && r1.foundUrl && r1.cleaned,
      "text url cleaned in place")

let r2 = cleanSync("no link here", [global("gclid")])
check(!r2.foundUrl && !r2.cleaned, "no url reported")

let r3 = cleanSync("https://e.com/p?utm_source=n", [])
check(r3.foundUrl && !r3.cleaned, "empty rules -> found but not cleaned")

// Every URL in the caption, not just the first.
let r4 = cleanSync("a https://e.com/1?gclid=x b https://f.com/2?gclid=y c", [global("gclid")])
check(r4.text == "a https://e.com/1 b https://f.com/2 c", "all urls cleaned")

// The resolver's destination is cleaned in turn.
let r5 = cleanSync("go https://s.hort/abc", [global("utm_source")],
                   { _ in "https://real.com/p?utm_source=n&id=1" })
check(r5.text == "go https://real.com/p?id=1", "resolved destination is cleaned")

check(ShareTextCleaner.hasUrl("x https://e.com y") && !ShareTextCleaner.hasUrl("no link"),
      "hasUrl")

// MARK: - FilterParser

let parsed = FilterParser.parse("""
! comment
@@||x.com^$removeparam=keep
$removeparam=utm_source
||facebook.com^$removeparam=fbclid
||bestbuy.com^$removeparam=id
$removeparam=id,domain=skimlinks.com|hanes.com
$removeparam=ref,domain=~excluded.com
://www.bilibili.com/video/$removeparam=mid
||shopee.*^$removeparam=af_siteid
$doc,removeparam=trk
$removeparam
$removeparam=/^utm_/
ref=shadcn.com^$removeparam=ref
not a rule
""")
check(parsed == [
    global("utm_source"),
    FilterRule(domains: ["facebook.com"], param: "fbclid"),
    FilterRule(domains: ["bestbuy.com"], param: "id"),
    FilterRule(domains: ["skimlinks.com", "hanes.com"], param: "id"),
    global("ref"),
    FilterRule(domains: ["www.bilibili.com"], param: "mid"),
    FilterRule(domains: ["shopee.*"], param: "af_siteid"),
    global("trk"),
], "adguard parse: domain= lists, ~exclusions, scheme patterns, tld wildcard, late removeparam")

// MARK: - RedirectResolver

check(RedirectResolver.jsRedirectIn(#"<script>document.location.replace("https:\/\/e.com\/a")</script>"#)
        == "https://e.com/a", "js handoff via location.replace, escaped slashes")
check(RedirectResolver.jsRedirectIn(#"window.location.href = 'https://e.com/b?x=1'"#)
        == "https://e.com/b?x=1", "js handoff via location.href")
check(RedirectResolver.jsRedirectIn(#"location = "https://e.com/c%"#+#"32""#)
        == "https://e.com/c%32", "js handoff unescapes \\uXXXX")
check(RedirectResolver.jsRedirectIn("nothing here") == nil, "no js handoff")

func resolveSync(_ url: String,
                 shouldFollow: @escaping (String) -> Bool = { _ in true },
                 hop: @escaping (String) async throws -> String?) -> String? {
    let box = UnsafeMutablePointer<String??>.allocate(capacity: 1)
    box.initialize(to: nil)
    let done = DispatchSemaphore(value: 0)
    Task {
        box.pointee = await RedirectResolver.resolve(url, shouldFollow: shouldFollow, hop: hop)
        done.signal()
    }
    done.wait()
    let result = box.pointee!
    box.deallocate()
    return result
}

// Follows the chain to its end, not to a fixed depth.
let chain = ["https://a/1": "https://b/2", "https://b/2": "https://c/3"]
check(resolveSync("https://a/1", hop: { chain[$0] }) == "https://c/3", "chain followed to the end")

// A cycle stops instead of spinning.
let cycle = ["https://a/1": "https://b/2", "https://b/2": "https://a/1"]
check(resolveSync("https://a/1", hop: { cycle[$0] }) == "https://b/2", "cycle broken")

// shouldFollow gates every hop, not just the first.
check(resolveSync("https://a/1", shouldFollow: { $0 != "https://b/2" }, hop: { chain[$0] })
        == "https://b/2", "dive stops when a hop leaves the allowed set")

// A failure on the first hop means nothing was learned; later ones keep the progress.
struct HopError: Error {}
check(resolveSync("https://a/1", hop: { _ in throw HopError() }) == nil, "first-hop failure -> nil")
check(resolveSync("https://a/1", hop: { url in
    if url == "https://b/2" { throw HopError() }
    return chain[url]
}) == "https://b/2", "later failure keeps the progress")

// appliesTo gates before any network call.
check(!RedirectResolver.appliesTo(.off, domains: ["e.com"], url: "https://e.com/a"), "off never applies")
check(RedirectResolver.appliesTo(.all, domains: [], url: "https://e.com/a"), "all applies to http")
check(!RedirectResolver.appliesTo(.all, domains: [], url: "mailto:a@e.com"), "all skips non-http")
check(RedirectResolver.appliesTo(.selected, domains: ["e.com"], url: "https://m.e.com/a"),
      "selected matches subdomain")
check(!RedirectResolver.appliesTo(.selected, domains: ["e.com"], url: "https://f.com/a"),
      "selected skips unlisted host")
check(RedirectResolver.forMode(.off, domains: ["e.com"]) == nil, "off yields no resolver")
check(RedirectResolver.forMode(.selected, domains: []) == nil, "selected with no domains yields none")

print("OK: all self-checks passed")
