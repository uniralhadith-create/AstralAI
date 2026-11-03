import Foundation
import Combine

// MARK: - Agent task board

/// One todo item defined by the model itself through the `update_tasks`
/// tool — the Claude-Code TodoWrite equivalent. The board is what the
/// Liquid Glass task strip in the chat renders live.
struct AgentTask: Identifiable, Equatable {
    enum Status: String, Equatable {
        case pending
        case inProgress = "in_progress"
        case completed

        /// Tolerates the common synonyms models emit ("in-progress",
        /// "done", "complete", "inprogress").
        static func parse(_ raw: String) -> Status {
            switch raw.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines) {
            case "in_progress", "in-progress", "inprogress", "active",
                 "working", "current":
                return .inProgress
            case "completed", "complete", "done", "finished", "success":
                return .completed
            default:
                return .pending
            }
        }
    }

    let id: UUID
    var title: String
    var status: Status
}

/// The shared observable task board. The `update_tasks` tool is the only
/// writer; the chat's task strip observes it. A new turn (new user goal)
/// resets the board because the model re-plans from scratch.
@MainActor
final class AgentTaskBoard: ObservableObject {

    static let shared = AgentTaskBoard()

    @Published private(set) var tasks: [AgentTask] = []
    @Published private(set) var sessionID: UUID?

    private init() {}

    var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    var currentTask: AgentTask? {
        tasks.first { $0.status == .inProgress }
    }

    /// Replaces the board, keeping stable ids for tasks whose title is
    /// unchanged so SwiftUI rows animate instead of flickering.
    func update(session: UUID, titles: [(title: String, status: AgentTask.Status)]) {
        if sessionID != session {
            sessionID = session
            tasks.removeAll()
        }
        var previous: [String: UUID] = [:]
        for task in tasks where task.status != .completed {
            previous[task.title] = task.id
        }
        tasks = titles.prefix(12).map { pair in
            AgentTask(
                id: previous[pair.title] ?? UUID(),
                title: pair.title,
                status: pair.status)
        }
    }

    /// Arms the board for a brand-new turn: the previous plan stays
    /// visible until the model publishes its first new list.
    func resetForNewTurn(session: UUID) {
        sessionID = session
        tasks.removeAll()
    }

    func clear() {
        tasks.removeAll()
        sessionID = nil
    }
}

// MARK: - UpdateTasksTool

/// `update_tasks` — the model's own todo list. For any multi-step piece of
/// work it first publishes its plan (3-6 concrete tasks), then keeps the
/// board truthful as it works: exactly one task in progress at a time,
/// completed items checked off. The user watches this happen live in the
/// Liquid Glass task strip — exactly like Claude Code's TodoWrite.
@MainActor
final class UpdateTasksTool: AgentTool {

    let name = "update_tasks"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Publish or update your task list (todo board) for the current goal. "
                + "Call this BEFORE starting multi-step work (3+ steps) with every task as 'pending', "
                + "then again whenever a task starts or finishes. Keep exactly one task 'in_progress' at a time. "
                + "The user sees this board live while you work. "
                + "Statuses: pending | in_progress | completed.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "tasks": .object([
                        "type": .string("array"),
                        "description": .string(
                            "The full current task list, in execution order"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "title": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Short concrete task title, max ~60 chars"),
                                ]),
                                "status": .object([
                                    "type": .string("string"),
                                    "enum": .array([
                                        .string("pending"),
                                        .string("in_progress"),
                                        .string("completed"),
                                    ]),
                                    "description": .string(
                                        "pending | in_progress | completed"),
                                ]),
                            ]),
                            "required": .array([.string("title"), .string("status")]),
                        ]),
                    ]),
                ]),
                "required": .array([.string("tasks")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let rawTasks = arguments["tasks"]?.arrayValue, !rawTasks.isEmpty else {
            return ToolResult(
                content: "Error: missing required parameter 'tasks' (a non-empty array).",
                isError: true)
        }

        var parsed: [(title: String, status: AgentTask.Status)] = []
        for raw in rawTasks {
            guard let object = raw.objectValue,
                  let title = object["title"]?.stringValue,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            let status = object["status"]?.stringValue
                .flatMap(AgentTask.Status.parse)
                ?? .pending
            parsed.append((
                title: title.trimmingCharacters(in: .whitespaces),
                status: status))
        }

        guard !parsed.isEmpty else {
            return ToolResult(
                content: "Error: no valid task objects found — each needs 'title' and 'status'.",
                isError: true)
        }

        AgentTaskBoard.shared.update(
            session: context.session.sessionID,
            titles: parsed)

        let counts = (
            pending: parsed.filter { $0.status == .pending }.count,
            inProgress: parsed.filter { $0.status == .inProgress }.count,
            completed: parsed.filter { $0.status == .completed }.count)
        return ToolResult(content: String(
            format: "Task board updated: %d tasks (%d pending, %d in progress, %d completed). Continue working through the remaining tasks.",
            parsed.count, counts.pending, counts.inProgress, counts.completed))
    }
}
