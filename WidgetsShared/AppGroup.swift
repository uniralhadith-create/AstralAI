import Foundation

/// Constants for the app group shared by the main app, the widget extension
/// and the share extension.
public enum SharedAppGroup {
    public static let id = "group.com.uniral.astralai"

    /// Container shared with the widgets + share extension.
    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Where the share extension drops incoming items for the main app.
    public static var inboxURL: URL {
        containerURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Where the current agent status snapshot is stored for widgets.
    public static var statusFileURL: URL {
        containerURL.appendingPathComponent("status.json")
    }

    public static func ensureInboxExists() {
        try? FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true)
    }
}
