import Foundation

/// Error thrown when shared text cannot be encoded.
enum ShareSaveError: Error {
    case encodingFailed
}

/// Self-contained storage helpers for the share extension target. Everything
/// the user shares is written into the app-group inbox; the main app imports
/// it on next foreground (AppEnvironment.importInboxIfNeeded).
///
/// This file cannot import the app module or WidgetsShared, so the app-group
/// id is declared locally and must stay in sync with SharedAppGroup.id.
enum ShareSupport {
    static let appGroupID = "group.com.uniral.astralai"

    /// The Inbox directory inside the app-group container (falls back to a
    /// temporary directory when the group is unavailable, e.g. simulator
    /// runs without entitlements).
    static var inboxURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
    }

    /// Creates the inbox directory if needed.
    static func ensureInbox() {
        try? FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true)
    }

    /// Writes one combined metadata file ("shared-<uuid>.astralmeta").
    /// The main app collects the file content as the task prompt text.
    @discardableResult
    static func saveMeta(_ text: String) throws -> URL {
        ensureInbox()
        guard let data = text.data(using: .utf8) else {
            throw ShareSaveError.encodingFailed
        }
        let url = inboxURL.appendingPathComponent("shared-\(UUID().uuidString.lowercased()).astralmeta")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Writes one image blob ("img-<uuid>.jpg"). The main app copies these
    /// into the agent workspace as attachments.
    @discardableResult
    static func saveImage(_ data: Data) throws -> URL {
        ensureInbox()
        let url = inboxURL.appendingPathComponent("img-\(UUID().uuidString.lowercased()).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}
