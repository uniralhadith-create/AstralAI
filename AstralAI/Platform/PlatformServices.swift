import Foundation

/// The concrete `SystemServicing` implementation used by the agent runtime.
/// Bridges agent side effects to the Live Activity bridge, the notification
/// bridge and the EventKit bridge. All methods are non-blocking: they hand
/// the work off and return immediately.
@MainActor
final class PlatformServices: SystemServicing {
    static let shared = PlatformServices()

    private init() {}

    // MARK: - SystemServicing: notifications

    func notifyUser(title: String, body: String) {
        NotificationBridge.shared.notify(title: title, body: body)
    }

    // MARK: - SystemServicing: Live Activity

    func startLiveActivity(goal: String) {
        LiveActivityBridge.shared.startActivity(goal: goal)
    }

    func updateLiveActivity(step: String, progress: Double) {
        LiveActivityBridge.shared.update(step: step, progress: progress)
    }

    func endLiveActivity(success: Bool) {
        LiveActivityBridge.shared.end(success: success)
    }

    // MARK: - SystemServicing: EventKit

    @discardableResult
    func createReminder(title: String, dueDate: Date?) async throws -> String {
        try await EventKitBridge.shared.createReminder(title: title, dueDate: dueDate)
    }

    @discardableResult
    func createCalendarEvent(title: String, start: Date, end: Date?, notes: String?) async throws -> String {
        try await EventKitBridge.shared.createEvent(title: title, start: start, end: end, notes: notes)
    }
}
