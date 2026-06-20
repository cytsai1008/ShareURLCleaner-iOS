import Foundation
import Observation

/// Drives the settings screen and persists changes to the shared `Settings`.
@MainActor
@Observable
final class SettingsModel {
    var filterURL: String = Settings.filterURL
    var autoUpdate: Bool = Settings.autoUpdate
    var ruleCount: Int = Settings.ruleCount
    var lastUpdated: Date? = Settings.lastUpdated

    var isUpdating = false
    var errorMessage: String?

    func saveFilterURL() {
        Settings.filterURL = filterURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetFilterURL() {
        filterURL = Settings.defaultFilterURL
        saveFilterURL()
    }

    func setAutoUpdate(_ on: Bool) {
        autoUpdate = on
        Settings.autoUpdate = on
        BackgroundRefresh.reschedule()
    }

    func updateNow() async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        saveFilterURL()
        do {
            try await FilterDownloader.update(from: filterURL)
            ruleCount = Settings.ruleCount
            lastUpdated = Settings.lastUpdated
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdating = false
    }
}
