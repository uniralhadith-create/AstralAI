import Foundation

// MARK: - System tools

/// Creates a reminder in the system Reminders app.
@MainActor
final class ReminderTool: AgentTool {

    let name = "create_reminder"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Create a reminder in the system Reminders app.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("The reminder title"),
                    ]),
                    "due_date": .object([
                        "type": .string("string"),
                        "description": .string("Optional due date in ISO 8601 format, e.g. 2025-06-01T09:00:00Z"),
                    ]),
                ]),
                "required": .array([.string("title")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'title'.", isError: true)
        }
        guard let system = context.system else {
            return ToolResult(content: "Error: system services are unavailable.", isError: true)
        }

        var dueDate: Date?
        if let raw = arguments["due_date"]?.stringValue, !raw.isEmpty {
            guard let parsed = Self.parseDate(raw) else {
                return ToolResult(
                    content: "Error: invalid 'due_date'. Use ISO 8601 format, e.g. 2025-06-01T09:00:00Z.",
                    isError: true)
            }
            dueDate = parsed
        }

        do {
            let confirmation = try await system.createReminder(title: title, dueDate: dueDate)
            return ToolResult(content: confirmation)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    static func parseDate(_ raw: String) -> Date? {
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: raw) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: raw)
    }
}

/// Creates an event in the system Calendar app.
@MainActor
final class CalendarTool: AgentTool {

    let name = "create_event"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Create an event in the system Calendar app.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("The event title"),
                    ]),
                    "start": .object([
                        "type": .string("string"),
                        "description": .string("Event start in ISO 8601 format, e.g. 2025-06-01T15:00:00Z"),
                    ]),
                    "end": .object([
                        "type": .string("string"),
                        "description": .string("Optional event end in ISO 8601 format"),
                    ]),
                    "notes": .object([
                        "type": .string("string"),
                        "description": .string("Optional event notes"),
                    ]),
                ]),
                "required": .array([.string("title"), .string("start")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'title'.", isError: true)
        }
        guard let rawStart = arguments["start"]?.stringValue, !rawStart.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'start'.", isError: true)
        }
        guard let start = ReminderTool.parseDate(rawStart) else {
            return ToolResult(
                content: "Error: invalid 'start'. Use ISO 8601 format, e.g. 2025-06-01T15:00:00Z.",
                isError: true)
        }
        guard let system = context.system else {
            return ToolResult(content: "Error: system services are unavailable.", isError: true)
        }

        var end: Date?
        if let rawEnd = arguments["end"]?.stringValue, !rawEnd.isEmpty {
            guard let parsed = ReminderTool.parseDate(rawEnd) else {
                return ToolResult(
                    content: "Error: invalid 'end'. Use ISO 8601 format.",
                    isError: true)
            }
            end = parsed
        }
        let notes = arguments["notes"]?.stringValue

        do {
            let confirmation = try await system.createCalendarEvent(
                title: title, start: start, end: end, notes: notes)
            return ToolResult(content: confirmation)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Sends a local notification to the user.
@MainActor
final class NotifyTool: AgentTool {

    let name = "notify_user"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Send a local notification to the user, e.g. when a long-running task finishes or needs attention.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("Notification title"),
                    ]),
                    "message": .object([
                        "type": .string("string"),
                        "description": .string("Notification body text"),
                    ]),
                ]),
                "required": .array([.string("title"), .string("message")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue, !title.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'title'.", isError: true)
        }
        guard let message = arguments["message"]?.stringValue, !message.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'message'.", isError: true)
        }
        guard let system = context.system else {
            return ToolResult(content: "Error: system services are unavailable.", isError: true)
        }
        system.notifyUser(title: title, body: message)
        return ToolResult(content: "Notification sent")
    }
}
