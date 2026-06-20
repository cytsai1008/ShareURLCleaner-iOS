import Foundation

/// App-Group-backed settings, shared between the app and the share extension.
enum Settings {

    static let defaultFilterURL =
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt"

    private static let defaults = UserDefaults(suiteName: FilterStore.appGroupID) ?? .standard

    private enum Key {
        static let filterURL = "filter_url"
        static let autoUpdate = "auto_update"
        static let lastUpdated = "last_updated"
        static let ruleCount = "rule_count"
    }

    static var filterURL: String {
        get { defaults.string(forKey: Key.filterURL) ?? defaultFilterURL }
        set { defaults.set(newValue, forKey: Key.filterURL) }
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
}
