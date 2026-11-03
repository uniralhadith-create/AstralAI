import Foundation

// MARK: - ToolRegistry

/// Assembles the full agent tool suite, advertises their specs to the model
/// and builds execution contexts.
@MainActor
final class ToolRegistry {

    private let tools: [String: AgentTool]
    private let orderedNames: [String]
    private let browser: BrowserControlling?
    private let workspace: WorkspaceRouting
    private let system: SystemServicing?

    init(
        browser: BrowserControlling?,
        workspace: WorkspaceRouting,
        system: SystemServicing?
    ) {
        self.browser = browser
        self.workspace = workspace
        self.system = system

        let suite: [AgentTool] = [
            UpdateTasksTool(),
            ExecTool(),
            RunPythonTool(),
            WebFetchTool(),
            WebSearchTool(),
            BrowserOpenTool(),
            BrowserElementsTool(),
            BrowserClickTool(),
            BrowserTypeTool(),
            BrowserReadTool(),
            BrowserScrollTool(),
            BrowserBackTool(),
            BrowserScreenshotTool(),
            FileWriteTool(),
            FileReadTool(),
            FileMkdirTool(),
            FileListTool(),
            FileDeleteTool(),
            FileZipTool(),
            FilePDFTool(),
            ProjectCreateTool(),
            SkillInstallTool(),
            JavaScriptTool(),
            DataAnalysisTool(),
            ReminderTool(),
            CalendarTool(),
            NotifyTool(),
            CloudExecTool(),
            CloudPullTool(),
            CloudPushTool(),
        ]

        var byName: [String: AgentTool] = [:]
        var names: [String] = []
        for tool in suite {
            if byName[tool.name] == nil {
                byName[tool.name] = tool
                names.append(tool.name)
            }
        }
        self.tools = byName
        self.orderedNames = names
    }

    /// The function schemas advertised to the model. Cloud-computer tools
    /// are only advertised while the user has an E2B API key configured
    /// (Settings > Cloud Computer) so the model never advertises a tool
    /// that would just error out.
    func specs() -> [ToolSpec] {
        let cloudAvailable = E2BComputer.shared.isConfigured
        let cloudTools: Set<String> = ["cloud_exec", "cloud_file_pull", "cloud_file_push"]
        return orderedNames.compactMap { name -> ToolSpec? in
            if cloudTools.contains(name), !cloudAvailable {
                return nil
            }
            return tools[name]?.spec
        }
    }

    /// Looks up a tool by its snake_case name.
    func tool(named name: String) -> AgentTool? {
        tools[name]
    }

    /// Builds the execution context shared by tools during one session.
    func makeContext(session: SessionInfo, isSubAgent: Bool) -> ToolContext {
        ToolContext(
            browser: browser,
            workspace: workspace,
            system: system,
            session: session,
            isSubAgent: isSubAgent)
    }

    /// Executes one tool call safely: unknown tools and thrown errors are
    /// converted into error tool results the model can react to. A hard
    /// per-tool timeout guarantees a hung tool (e.g. a stalled WebView) can
    /// never freeze the whole turn. Every execution is mirrored into the
    /// shared AgentActivityLog so the terminal's Agent tab shows the model
    /// at work live.
    @discardableResult
    func execute(
        call: ToolCall,
        session: SessionInfo,
        isSubAgent: Bool,
        timeout: TimeInterval = 75
    ) async -> ToolResult {
        guard let tool = tool(named: call.name) else {
            AgentActivityLog.shared.complete(
                id: AgentActivityLog.shared.begin(
                    session: session.sessionID, tool: call.name, title: ""),
                output: "Unknown tool \(call.name)",
                isError: true,
                duration: 0)
            return ToolResult(content: "Unknown tool \(call.name)", isError: true)
        }
        // Cooperative cancellation: when the turn was stopped, fail fast
        // instead of dispatching another tool task into the race.
        if Task.isCancelled {
            return ToolResult(content: "Error: tool \(call.name) cancelled", isError: true)
        }
        let context = makeContext(session: session, isSubAgent: isSubAgent)
        // V4.6.0: tools that produce deliverables (browser_screenshot)
        // register them against the exact call.
        context.callID = call.id

        let startedAt = Date()
        let activityID = AgentActivityLog.shared.begin(
            session: session.sessionID,
            tool: call.name,
            title: Self.activityTitle(for: call))

        func finish(_ result: ToolResult) -> ToolResult {
            AgentActivityLog.shared.complete(
                id: activityID,
                output: result.content,
                isError: result.isError,
                duration: Date().timeIntervalSince(startedAt))
            return result
        }

        do {
            let result = try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask {
                    try await tool.execute(arguments: call.parsedArguments, context: context)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ToolTimeoutError(tool: call.name, seconds: timeout)
                }
                defer { group.cancelAll() }
                return try await group.next() ?? ToolResult(
                    content: "Error: tool \(call.name) returned nothing", isError: true)
            }
            return finish(result)
        } catch let timeoutError as ToolTimeoutError {
            return finish(ToolResult(
                content: "Error: \(timeoutError.message)", isError: true))
        } catch {
            return finish(ToolResult(
                content: "Error: \(error.localizedDescription)", isError: true))
        }
    }

    /// The human-readable primary argument of a tool call, used as the
    /// activity-feed title (the command, the query, the URL, the path…).
    private static func activityTitle(for call: ToolCall) -> String {
        let arguments = call.parsedArguments
        for key in ["command", "query", "url", "path", "file_path", "filename", "code"] {
            if let value = arguments[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        if call.name == "update_tasks" {
            let count = arguments["tasks"]?.arrayValue?.count ?? 0
            return "\(count) tasks"
        }
        return call.name
    }
}

/// Raised internally when a tool exceeds its execution deadline.
private struct ToolTimeoutError: Error {
    let tool: String
    let seconds: TimeInterval
    var message: String {
        "tool \(tool) timed out after \(Int(seconds))s"
    }
}
