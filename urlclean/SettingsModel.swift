import Foundation
import Observation

/// Drives the settings screen and persists changes to the shared `Settings`.
@MainActor
@Observable
final class SettingsModel {
    var sources: [FilterSource] = Settings.filterSources
    var autoUpdate: Bool = Settings.autoUpdate
    var aggressiveMode: RedirectResolver.Mode = Settings.aggressiveMode
    var aggressiveDomains: String = Settings.aggressiveDomains
    var ruleCount: Int = Settings.ruleCount
    var lastUpdated: Date? = Settings.lastUpdated

    var isUpdating = false
    var errorMessage: String?

    var aggressiveDomainCount: Int { Settings.parseDomains(aggressiveDomains).count }

    func setEnabled(_ source: FilterSource, _ enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.url == source.url }) else { return }
        sources[index].enabled = enabled
        Settings.filterSources = sources
    }

    /// Built-ins can only be unticked, never removed — see `Settings.withMissingBuiltIns`.
    func remove(_ source: FilterSource) {
        guard !source.isBuiltIn else { return }
        sources.removeAll { $0.url == source.url }
        Settings.filterSources = sources
    }

    func add(_ rawURL: String) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http"), !sources.contains(where: { $0.url == url }) else { return }
        sources.append(FilterSource(url: url, enabled: true))
        Settings.filterSources = sources
    }

    func setAutoUpdate(_ on: Bool) {
        autoUpdate = on
        Settings.autoUpdate = on
        BackgroundRefresh.reschedule()
    }

    func setAggressiveMode(_ mode: RedirectResolver.Mode) {
        aggressiveMode = mode
        Settings.aggressiveMode = mode
    }

    func saveAggressiveDomains() {
        Settings.aggressiveDomains = aggressiveDomains
        // The setter drops a list equal to the shipped default, so read back what stuck.
        aggressiveDomains = Settings.aggressiveDomains
    }

    func resetAggressiveDomains() {
        aggressiveDomains = Settings.defaultAggressiveDomains
        saveAggressiveDomains()
    }

    func updateNow() async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        do {
            try await FilterDownloader.update(from: Settings.enabledFilterURLs)
            ruleCount = Settings.ruleCount
            lastUpdated = Settings.lastUpdated
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdating = false
    }
}
