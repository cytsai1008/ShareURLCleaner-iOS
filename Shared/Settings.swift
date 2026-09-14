import Foundation

/// One filter list the user can tick on or off. `name` is blank for user-added lists.
struct FilterSource: Equatable, Identifiable, Sendable {
    let url: String
    var enabled: Bool
    var name: String = ""

    var id: String { url }
    var isBuiltIn: Bool { Settings.isBuiltIn(url) }
}

/// App-Group-backed settings, shared between the app and the share extension.
/// Port of `SettingsDataStore.kt`.
enum Settings {

    static let defaultFilterURL =
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt"

    /// Lists shipped with the app, all on by default. Names are product names, deliberately not
    /// translated.
    ///
    /// Together they clean the three share links this was tested against down to zero tracking
    /// params — AdGuard alone leaves 3 on Bilibili, and Facebook needs uBO. Each list covers
    /// params the others miss, and overlap is de-duplicated on download.
    static let builtInFilters: [FilterSource] = [
        FilterSource(url: defaultFilterURL, enabled: true, name: "AdGuard URL Tracking"),
        FilterSource(
            url: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt",
            enabled: true,
            name: "Legitimate URL Shortener"
        ),
        FilterSource(
            url: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt",
            enabled: true,
            name: "uBlock Origin Privacy"
        ),
        FilterSource(
            url: "https://raw.githubusercontent.com/cytsai1008/ShareURLCleaner/main/Filters/filter.txt",
            enabled: true,
            name: "Kenichi's URL Cleaner List"
        ),
    ]

    /// Hosts where following a redirect actually pays off: link shorteners, plus the
    /// social/shopping apps that wrap shares in a tracking hop. Sorted alphabetically.
    ///
    /// Note the entries for whole domains (facebook.com, instagram.com, threads.com): their share
    /// links live on the main domain (`/share/…`), so scoping to a subdomain would miss them. The
    /// cost is a HEAD request on every link to those sites — trim them if that bothers you.
    static let defaultAggressiveDomains = [
        "3.cn", "a.co", "amzn.asia", "amzn.eu",
        "amzn.to", "b23.tv", "bit.ly", "buff.ly",
        "cutt.ly", "dlvr.it", "facebook.com", "fb.me",
        "fb.watch", "goo.gl", "ift.tt", "ig.me",
        "instagram.com", "is.gd", "l.facebook.com", "l.instagram.com",
        "l.threads.net", "lihi.cc", "lihi1.cc", "lihi2.cc",
        "lihi3.cc", "lm.facebook.com", "lnkd.in", "m.me",
        "m.tb.cn", "momo.dm", "ow.ly", "pin.it",
        "pse.is", "rb.gy", "rebrand.ly", "redd.it",
        "reurl.cc", "s.id", "s.shopee.tw", "shope.ee",
        "shorturl.at", "spoti.fi", "t.cn", "t.co",
        "t.ly", "t.snapchat.com", "tb.cn", "threads.com",
        "threads.net", "tiny.cc", "tinyurl.com", "trib.al",
        "tw.shp.ee", "u.jd.com", "url.cn", "v.douyin.com",
        "v.gd", "v.kuaishou.com", "vm.tiktok.com", "vt.tiktok.com",
        "xhslink.com", "z.kuaishou.com",
    ].joined(separator: "\n")

    private static let defaults = UserDefaults(suiteName: FilterStore.appGroupID) ?? .standard

    private enum Key {
        static let filterURL = "filter_url"
        static let filterSources = "filter_sources"
        static let autoUpdate = "auto_update"
        static let lastUpdated = "last_updated"
        static let ruleCount = "rule_count"
        static let aggressiveMode = "aggressive_mode"
        static let aggressiveDomains = "aggressive_domains"
    }

    static func isBuiltIn(_ url: String) -> Bool { builtInFilters.contains { $0.url == url } }

    private static func builtInName(_ url: String) -> String {
        builtInFilters.first { $0.url == url }?.name ?? ""
    }

    /// Never empty. Falls back to the built-ins, carrying over a custom `filter_url` from the
    /// single-list version of the app so an upgrade doesn't silently drop it.
    static var filterSources: [FilterSource] {
        get {
            if let raw = defaults.string(forKey: Key.filterSources) {
                let stored = parseSources(raw)
                if !stored.isEmpty { return withMissingBuiltIns(stored) }
            }
            let legacy = defaults.string(forKey: Key.filterURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let legacy, !legacy.isEmpty, !isBuiltIn(legacy) {
                return builtInFilters + [FilterSource(url: legacy, enabled: true)]
            }
            return builtInFilters
        }
        set { defaults.set(serializeSources(newValue), forKey: Key.filterSources) }
    }

    /// URLs to actually download, in order.
    static var enabledFilterURLs: [String] {
        filterSources.filter(\.enabled).map(\.url)
    }

    /// Appends built-ins the stored list has never seen. The UI offers no way to delete a
    /// built-in — only to untick it — so one missing from storage is a list shipped in a later
    /// release, not one the user got rid of.
    static func withMissingBuiltIns(_ stored: [FilterSource]) -> [FilterSource] {
        stored + builtInFilters.filter { builtIn in !stored.contains { $0.url == builtIn.url } }
    }

    private static func serializeSources(_ sources: [FilterSource]) -> String {
        sources.map { "\($0.enabled ? 1 : 0)\t\($0.url)" }.joined(separator: "\n")
    }

    private static func parseSources(_ raw: String) -> [FilterSource] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let url = parts[1].trimmingCharacters(in: .whitespaces)
            if url.isEmpty { return nil }
            return FilterSource(url: url, enabled: parts[0] == "1", name: builtInName(url))
        }
    }

    static var autoUpdate: Bool {
        get { defaults.object(forKey: Key.autoUpdate) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoUpdate) }
    }

    static var lastUpdated: Date? {
        get {
            let t = defaults.double(forKey: Key.lastUpdated)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastUpdated) }
    }

    static var ruleCount: Int {
        get { defaults.integer(forKey: Key.ruleCount) }
        set { defaults.set(newValue, forKey: Key.ruleCount) }
    }

    static var aggressiveMode: RedirectResolver.Mode {
        get {
            defaults.string(forKey: Key.aggressiveMode)
                .flatMap(RedirectResolver.Mode.init(rawValue:)) ?? .off
        }
        set { defaults.set(newValue.rawValue, forKey: Key.aggressiveMode) }
    }

    /// Raw, user-editable text. Use `parseDomains` to turn it into matchable hosts.
    ///
    /// Absent means "whatever the app ships with", so an untouched list picks up domains added in
    /// a later release. The setter keeps it absent until there is a real edit: a list matching
    /// the shipped default is stored as "not set" rather than as a copy of it, so it keeps
    /// tracking the default instead of freezing at today's version.
    static var aggressiveDomains: String {
        get { defaults.string(forKey: Key.aggressiveDomains) ?? defaultAggressiveDomains }
        set {
            if parseDomains(newValue) == parseDomains(defaultAggressiveDomains) {
                defaults.removeObject(forKey: Key.aggressiveDomains)
            } else {
                defaults.set(newValue, forKey: Key.aggressiveDomains)
            }
        }
    }

    /// Splits the user-editable domain list on whitespace, commas or semicolons.
    static func parseDomains(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty })
    }
}
