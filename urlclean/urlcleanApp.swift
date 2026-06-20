import SwiftUI

@main
struct urlcleanApp: App {
    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .onAppear { BackgroundRefresh.reschedule() }
        }
    }
}
