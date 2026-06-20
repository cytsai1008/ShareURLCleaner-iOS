// Standalone self-check for the pure cleaning logic (no app/UIKit deps).
// Run (this file holds the top-level code, so swiftc needs it named main.swift):
//   d=$(mktemp -d); cp Shared/{FilterRule,UrlCleaner,ShareTextCleaner,FilterParser}.swift "$d"
//   cp Tests/SelfCheck.swift "$d/main.swift"; (cd "$d" && swiftc *.swift -o check && ./check)
import Foundation

func check(_ cond: Bool, _ msg: String) {
    if !cond { print("FAIL: \(msg)"); exit(1) }
}

// UrlCleaner: drops matching param, keeps the rest.
check(
    UrlCleaner.clean("https://example.com/page?utm_source=n&id=123",
                     rules: [FilterRule(domain: nil, param: "utm_source")])
        == "https://example.com/page?id=123",
    "global param removed")

// Unmatched rule leaves URL untouched.
check(
    UrlCleaner.clean("https://example.com/page?utm_source=n&id=123",
                     rules: [FilterRule(domain: "other.example", param: "utm_source")])
        == "https://example.com/page?utm_source=n&id=123",
    "non-matching domain rule no-ops")

// Domain rule matches host and subdomain only.
let fbRule = [FilterRule(domain: "facebook.com", param: "fbclid")]
check(UrlCleaner.clean("https://m.facebook.com/p?fbclid=x&a=1", rules: fbRule)
        == "https://m.facebook.com/p?a=1", "subdomain match")
check(UrlCleaner.clean("https://twitter.com/p?fbclid=x&a=1", rules: fbRule)
        == "https://twitter.com/p?fbclid=x&a=1", "other host untouched")

// Case-insensitive param match.
check(
    UrlCleaner.clean("https://e.com/p?UTM_Source=n&id=1",
                     rules: [FilterRule(domain: nil, param: "utm_source")])
        == "https://e.com/p?id=1", "case-insensitive param")

// Non-http URL returned as-is.
check(UrlCleaner.clean("ftp://e.com/p?utm_source=n", rules: [FilterRule(domain: nil, param: "utm_source")])
        == "ftp://e.com/p?utm_source=n", "non-http untouched")

// ShareTextCleaner: cleans first URL inside surrounding text.
let r1 = ShareTextCleaner.cleanFirstUrl("Look https://e.com/p?gclid=x&id=1 here",
                                        rules: [FilterRule(domain: nil, param: "gclid")])
check(r1.text == "Look https://e.com/p?id=1 here" && r1.foundUrl && r1.cleaned, "text url cleaned in place")

let r2 = ShareTextCleaner.cleanFirstUrl("no link here", rules: [FilterRule(domain: nil, param: "gclid")])
check(!r2.foundUrl && !r2.cleaned, "no url reported")

let r3 = ShareTextCleaner.cleanFirstUrl("https://e.com/p?utm_source=n", rules: [])
check(r3.foundUrl && !r3.cleaned, "empty rules -> found but not cleaned")

// FilterParser: AdGuard $removeparam syntax.
let parsed = FilterParser.parse("""
! comment
@@||x.com^$removeparam=keep
$removeparam=utm_source
||facebook.com^$removeparam=fbclid
||bestbuy.com^$removeparam=id,domain=foo
not a rule
""")
check(parsed == [
    FilterRule(domain: nil, param: "utm_source"),
    FilterRule(domain: "facebook.com", param: "fbclid"),
    FilterRule(domain: "bestbuy.com", param: "id"),
], "adguard parse: skip comment/exception, global + domain rules, param before comma")

print("OK: all self-checks passed")
