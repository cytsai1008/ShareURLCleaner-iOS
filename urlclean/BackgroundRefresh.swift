import BackgroundTasks
import Foundation

/// Daily background refresh of the filter list via BGTaskScheduler.
/// Mirrors the Android app's daily WorkManager job, gated on the auto-update toggle.
enum BackgroundRefresh {

    static let taskID = "com.cytsai.urlclean.refresh"

    /// Register the task handler. Call once at app launch, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next run (~24h out) when auto-update is on, otherwise cancel any pending request.
    static func reschedule() {
        guard Settings.autoUpdate else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        reschedule() // queue the next one regardless of this run's outcome

        let work = Task {
            do {
                try await FilterDownloader.update(from: Settings.filterURL)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
