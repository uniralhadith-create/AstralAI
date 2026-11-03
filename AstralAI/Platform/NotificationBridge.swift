import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter`: authorization handling and
/// immediate local notification posting. Posting while unauthorized is a
/// silent no-op; if authorization was never decided, the system prompt is
/// shown first and the notification is delivered only when granted.
final class NotificationBridge {
    static let shared = NotificationBridge()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    /// Requests alert / sound / badge authorization.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[NotificationBridge] authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Posting

    /// Posts an immediate local notification (no trigger).
    func notify(title: String, body: String) {
        Task { [weak self] in
            guard let self else { return }
            let settings = await self.center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.post(title: title, body: body)
            case .notDetermined:
                // First time the agent notifies the user: ask, then deliver
                // only if the user accepts.
                if await self.requestAuthorization() {
                    self.post(title: title, body: body)
                }
            default:
                // Denied — silent no-op.
                break
            }
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)

        center.add(request) { error in
            if let error {
                print("[NotificationBridge] add request failed: \(error)")
            }
        }
    }
}
