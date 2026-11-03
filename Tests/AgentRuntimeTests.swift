import XCTest
@testable import AstralAI

// MARK: - Test doubles

/// Minimal WorkspaceRouting stub — the UpdateTasksTool never touches the
/// workspace, but ToolContext requires one.
@MainActor
private final class StubWorkspace: WorkspaceRouting {
    var rootURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    func write(path: String, content: String) throws -> URL { rootURL }
    func writeData(path: String, data: Data) throws -> URL { rootURL }
    func createFolder(path: String) throws -> URL { rootURL }
    func read(path: String) throws -> String { "" }
    func list() -> [WorkspaceFile] { [] }
    func delete(path: String) throws {}
    func zip(paths: [String], archiveName: String) throws -> URL { rootURL }
    func url(for path: String) -> URL? { nil }
}

// MARK: - V3.6 agent runtime tests

/// Covers the V3.6 agent-runtime pieces:
/// - the fixed Bing parser (both mobile `<a><h2>` and legacy `<h2><a>`
///   title layouts, `ck/a` redirect filtering and `u=a1` unwrapping),
/// - the strict tool-rejection heuristic (no more silent chatbot
///   downgrades on unrelated 400s),
/// - the task board and its status parsing.
@MainActor
final class AgentRuntimeTests: XCTestCase {

    // MARK: Bing parsing

    func testBingMobileLayoutParses() {
        let html = """
        <li class="b_algo" data-id="1"><div class="b_title"><a href="https://example.com/news" h="ID=SERP"><h2><strong>Latest</strong> AI News</h2></a></div><div class="b_caption"><p class="b_lineclamp2">All the breaking AI headlines today.</p></div></li>
        <li class="b_algo" data-id="2"><div class="b_title"><a href="https://example.org/research" h="ID=SERP"><h2>AI Research Weekly</h2></a></div><div class="b_caption"><p class="b_lineclamp3">Papers and deep dives.</p></div></li>
        """
        let results = WebSearchService.parseBingResultsForTests(html)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Latest AI News")
        XCTAssertEqual(results[0].url, "https://example.com/news")
        XCTAssertEqual(results[0].snippet, "All the breaking AI headlines today.")
        XCTAssertEqual(results[1].title, "AI Research Weekly")
    }

    func testBingLegacyLayoutParses() {
        let html = """
        <li class="b_algo"><h2><a href="https://example.com/legacy" target="_blank">Legacy Layout Result</a></h2><div class="b_caption"><p class="b_lineclamp2">A caption.</p></div></li>
        """
        let results = WebSearchService.parseBingResultsForTests(html)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Legacy Layout Result")
        XCTAssertEqual(results[0].url, "https://example.com/legacy")
    }

    func testBingRedirectLinksAreFilteredOrUnwrapped() {
        // A ck/a wrapper whose u=a1 payload decodes to a real URL → unwrapped.
        let wrapped = """
        <li class="b_algo"><h2><a href="https://www.bing.com/ck/a?!&&p=abc&amp;u=a1aHR0cHM6Ly9leGFtcGxlLmNvbS91bndyYXBwZWQ&amp;ntb=1">Unwrapped Target</a></h2></li>
        """
        // "aHR0cHM6Ly9leGFtcGxlLmNvbS91bndyYXBwZWQ" = base64url("https://example.com/unwrapped")
        var results = WebSearchService.parseBingResultsForTests(wrapped)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url, "https://example.com/unwrapped")

        // A pure Bing search link (no payload) → filtered out entirely.
        let bingOnly = """
        <li class="b_algo"><h2><a href="https://www.bing.com/search?q=x">Bing Self Link</a></h2></li>
        """
        results = WebSearchService.parseBingResultsForTests(bingOnly)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: Strict tool-rejection heuristic

    func testUnrelated400IsNotToolRejection() {
        // V3.5 bug: these generic 400s matched the broad marker list and
        // silently stripped the tools.
        XCTAssertFalse(LLMService.looksLikeToolRejection(
            LLMError.badResponse("{\"error\":{\"message\":\"Model llama-3-x not found\",\"type\":\"invalid_request_error\"}}")))
        XCTAssertFalse(LLMService.looksLikeToolRejection(
            LLMError.badResponse("Invalid request: max_tokens must be a positive integer")))
    }

    func testRealToolRejectionsAreDetected() {
        XCTAssertTrue(LLMService.looksLikeToolRejection(
            LLMError.badResponse("This model does not support tool calling")))
        XCTAssertTrue(LLMService.looksLikeToolRejection(
            LLMError.badResponse("Invalid parameter: tools[0].function is malformed")))
    }

    // MARK: Task board

    func testTaskStatusParsingSynonyms() {
        XCTAssertEqual(AgentTask.Status.parse("pending"), .pending)
        XCTAssertEqual(AgentTask.Status.parse("in_progress"), .inProgress)
        XCTAssertEqual(AgentTask.Status.parse("in-progress"), .inProgress)
        XCTAssertEqual(AgentTask.Status.parse("working"), .inProgress)
        XCTAssertEqual(AgentTask.Status.parse("completed"), .completed)
        XCTAssertEqual(AgentTask.Status.parse("done"), .completed)
        XCTAssertEqual(AgentTask.Status.parse("weird-value"), .pending)
    }

    func testTaskBoardUpdateKeepsStableIDsAndCounts() {
        let board = AgentTaskBoard.shared
        let session = UUID()
        board.update(session: session, titles: [
            ("Search the web", .pending),
            ("Write the report", .pending),
            ("Save to /home/astral", .pending),
        ])
        XCTAssertEqual(board.tasks.count, 3)
        XCTAssertEqual(board.completedCount, 0)

        let firstID = board.tasks[0].id
        board.update(session: session, titles: [
            ("Search the web", .completed),
            ("Write the report", .inProgress),
            ("Save to /home/astral", .pending),
        ])
        XCTAssertEqual(board.completedCount, 1)
        XCTAssertEqual(board.tasks[0].id, firstID, "unchanged titles must keep stable row ids")
        XCTAssertEqual(board.currentTask?.title, "Write the report")

        board.clear()
        XCTAssertTrue(board.tasks.isEmpty)
    }

    func testUpdateTasksToolParsesAndPublishes() async throws {
        let board = AgentTaskBoard.shared
        board.clear()
        let session = UUID()
        let context = ToolContext(
            browser: nil,
            workspace: StubWorkspace(),
            system: nil,
            session: SessionInfo(sessionID: session, goal: "test"),
            isSubAgent: false)

        let tool = UpdateTasksTool()
        let arguments: [String: JSONValue] = [
            "tasks": .array([
                .object([
                    "title": .string("Research sources"),
                    "status": .string("completed"),
                ]),
                .object([
                    "title": .string("Draft the answer"),
                    "status": .string("in_progress"),
                ]),
            ]),
        ]

        let result = try await tool.execute(arguments: arguments, context: context)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(board.tasks.count, 2)
        XCTAssertEqual(board.tasks[0].status, .completed)
        XCTAssertEqual(board.tasks[1].status, .inProgress)
        XCTAssertTrue(result.content.contains("2 tasks"))

        board.clear()
    }

    // MARK: Activity log

    func testActivityLogRecordsBeginAndComplete() {
        let log = AgentActivityLog.shared
        log.clear()
        let session = UUID()

        let id = log.begin(session: session, tool: "web_search", title: "weather in cairo")
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].status, .running)
        XCTAssertEqual(log.entries[0].kind, .search)

        log.complete(
            id: id,
            output: "1. Weather Cairo\n   URL: https://weather.com",
            isError: false,
            duration: 0.42)
        XCTAssertEqual(log.entries[0].status, .done)
        XCTAssertEqual(log.entries[0].duration ?? 0, 0.42, accuracy: 0.01)
        XCTAssertTrue(log.entries[0].outputPreview.hasPrefix("1. Weather"))

        // A new session resets the log.
        log.begin(session: UUID(), tool: "exec", title: "ls")
        XCTAssertEqual(log.entries.count, 1)
        log.clear()
    }

    func testActivityKindMapping() {
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "exec"), .command)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "web_search"), .search)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "web_fetch"), .fetch)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "browser_click"), .browser)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "file_write"), .file)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "run_javascript"), .code)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "update_tasks"), .taskBoard)
        XCTAssertEqual(AgentActivityEntry.Kind.kind(forTool: "mystery_tool"), .other)
    }
}
