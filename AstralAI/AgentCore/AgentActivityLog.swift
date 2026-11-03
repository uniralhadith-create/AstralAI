import Foundation
import Combine

// MARK: - Agent activity log

/// One observable unit of agent work — a tool call in flight or finished.
/// The unified "what is the AI doing right now" feed that powers the
/// Agent tab of the terminal: every tool call from every turn (searches,
/// page fetches, browser actions, shell commands, file writes, code runs,
/// task-board updates) is recorded here the moment it starts and completed
/// with a result preview when it ends — a Claude-Code-style live console.
struct AgentActivityEntry: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case command
        case search
        case fetch
        case browser
        case file
        case code
        case data
        case taskBoard
        case system
        case other

        /// Maps a snake_case tool name to its display family.
        static func kind(forTool name: String) -> Kind {
            switch name {
            case "exec": return .command
            case "cloud_exec", "cloud_file_pull": return .command
            case "web_search": return .search
            case "web_fetch": return .fetch
            case "browser_open", "browser_click", "browser_type",
                 "browser_read", "browser_scroll", "browser_back",
                 "browser_elements": return .browser
            case "file_write", "file_read", "file_mkdir", "file_list", "file_delete",
                 "file_zip", "file_pdf", "project_create": return .file
            case "run_javascript", "run_python": return .code
            case "analyze_data": return .data
            case "update_tasks": return .taskBoard
            case "skill_install": return .system
            case "notify_user", "create_reminder", "create_event": return .system
            default: return .other
            }
        }
    }

    enum Status: Equatable {
        case running
        case done
        case failed
    }

    let id: UUID
    let kind: Kind
    let toolName: String
    /// The tool's primary argument: the command, query, URL or path.
    let title: String
    let startedAt: Date
    var status: Status = .running
    /// Short result preview (already capped — never the full payload).
    var outputPreview: String = ""
    var duration: TimeInterval?
}

/// The shared, observable agent-activity console. `ToolRegistry` is the
/// single writer: it opens an entry before every tool execution and
/// completes it with the outcome, so the terminal's Agent tab is always a
/// truthful, live mirror of what the model is doing.
@MainActor
final class AgentActivityLog: ObservableObject {

    static let shared = AgentActivityLog()

    @Published private(set) var entries: [AgentActivityEntry] = []

    /// The session the current entries belong to; turns from a new session
    /// reset the log.
    private(set) var sessionID: UUID?

    private static let previewLimit = 320
    private static let entryLimit = 300

    private init() {}

    /// Opens a running entry and returns its id for `complete`.
    @discardableResult
    func begin(session: UUID, tool: String, title: String) -> UUID {
        if sessionID != session {
            sessionID = session
            entries.removeAll()
        }
        let id = UUID()
        entries.append(AgentActivityEntry(
            id: id,
            kind: AgentActivityEntry.Kind.kind(forTool: tool),
            toolName: tool,
            title: String(title.prefix(220)),
            startedAt: Date()))
        if entries.count > Self.entryLimit {
            entries.removeFirst(entries.count - Self.entryLimit)
        }
        return id
    }

    /// Completes an entry with the tool outcome.
    func complete(id: UUID, output: String, isError: Bool, duration: TimeInterval) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let preview = String(output.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.previewLimit))
        entries[index].status = isError ? .failed : .done
        entries[index].outputPreview = preview
        entries[index].duration = max(0, duration)
    }

    /// Clears the console (trash button in the terminal).
    func clear() {
        entries.removeAll()
        sessionID = nil
    }
}
