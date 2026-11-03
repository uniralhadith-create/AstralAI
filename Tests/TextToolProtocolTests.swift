import XCTest
@testable import AstralAI

// MARK: - TextToolProtocol tests (V4.0)

/// The universal text tool protocol is the fallback that keeps the agent
/// working with models that have no native function calling — these tests
/// pin down its parser, stripper and streaming filter.
final class TextToolProtocolTests: XCTestCase {

    // MARK: Parsing

    func testParsesPrimaryMarker() {
        let text = """
        Let me search for that.
        ASTRAL_TOOL {"name": "web_search", "arguments": {"query": "weather cairo"}}
        """
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "web_search")
        XCTAssertTrue(calls[0].argumentsJSON.contains("weather cairo"))
    }

    func testParsesHermesFormat() {
        let text = #"<|tool_call|> {"name": "exec", "arguments": {"command": "ls -la"}}"#
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "exec")
    }

    func testParsesMultipleCallsInOneReply() {
        let text = """
        ASTRAL_TOOL {"name": "web_search", "arguments": {"query": "openrouter"}}
        ASTRAL_TOOL {"name": "file_write", "arguments": {"path": "notes.md", "content": "hi"}}
        """
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].name, "file_write")
    }

    func testArgumentsAsJSONStringAccepted() {
        let text = "ASTRAL_TOOL {\"name\": \"exec\", \"arguments\": \"{\\\"command\\\": \\\"pwd\\\"}\"}"
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].argumentsJSON.contains("pwd"))
    }

    func testMarkerInsideProseIgnored() {
        // The marker must start a line — prose mentioning it mid-sentence
        // is not a call.
        let text = "The ASTRAL_TOOL protocol is documented somewhere; nothing to call here."
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertTrue(calls.isEmpty)
    }

    func testIncompleteJSONIsNotACall() {
        let text = "ASTRAL_TOOL {\"name\": \"web_search\", \"arguments\": {\"query\": \"unstopp"
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertTrue(calls.isEmpty)
    }

    func testJSONWithoutNameIsNotACall() {
        let text = "ASTRAL_TOOL {\"foo\": 1}"
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertTrue(calls.isEmpty)
        // And the text survives stripping untouched.
        XCTAssertEqual(TextToolProtocol.stripCalls(in: text), text)
    }

    func testMultilineJSONArguments() {
        let text = """
        ASTRAL_TOOL {
          "name": "file_write",
          "arguments": {
            "path": "report.md",
            "content": "line one\nline two"
          }
        }
        """
        let calls = TextToolProtocol.parseCalls(in: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "file_write")
        XCTAssertTrue(calls[0].argumentsJSON.contains("report.md"))
    }

    // MARK: Stripping

    func testStripRemovesCallLinesOnly() {
        let text = """
        Working on it.
        ASTRAL_TOOL {"name": "web_search", "arguments": {"query": "test"}}
        Here are the results.
        """
        let stripped = TextToolProtocol.stripCalls(in: text)
        XCTAssertFalse(stripped.contains("ASTRAL_TOOL"))
        XCTAssertTrue(stripped.contains("Working on it."))
        XCTAssertTrue(stripped.contains("Here are the results."))
    }

    // MARK: Streaming filter

    func testStreamFilterSplitsMarkerAcrossChunks() {
        var filter = TextToolProtocol.StreamFilter()
        var visible = ""

        for chunk in ["Here is the plan.\n", "ASTRAL_T", "OOL {\"na", "me\": \"web_se", "arch\", \"argu", "ments\": {\"query\": \"x\"}}", "\nDone."] {
            visible += filter.feed(chunk)
        }
        visible += filter.flush()

        XCTAssertEqual(visible, "Here is the plan.\n\nDone.")
    }

    func testStreamFilterHoldsPendingMarkerPrefix() {
        var filter = TextToolProtocol.StreamFilter()
        var visible = ""
        visible += filter.feed("hello ASTRA")
        // "ASTRA" is a potential marker prefix - held back.
        XCTAssertEqual(visible, "hello ")
        visible += filter.feed("L is not a call")
        visible += filter.flush()
        XCTAssertEqual(visible, "hello ASTRAL is not a call")
    }

    func testStreamFilterSwallowsCompleteCallOnly() {
        var filter = TextToolProtocol.StreamFilter()
        var visible = ""
        visible += filter.feed("before ")
        visible += filter.feed("ASTRAL_TOOL {\"name\": \"exec\", \"arguments\": {\"command\": \"ls\"}}")
        visible += filter.feed(" after")
        visible += filter.flush()
        XCTAssertEqual(visible, "before  after")
    }

    // MARK: Prompt building

    func testPromptListsEveryTool() {
        let tools = [
            ToolSpec(name: "web_search", description: "Search the web", parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("The query")]),
                ]),
                "required": .array([.string("query")]),
            ])),
            ToolSpec(name: "exec", description: "Run a shell command"),
        ]
        let prompt = TextToolProtocol.prompt(for: tools)
        XCTAssertTrue(prompt.contains("TOOL USE PROTOCOL"))
        XCTAssertTrue(prompt.contains("- web_search: Search the web"))
        XCTAssertTrue(prompt.contains("- exec: Run a shell command"))
        XCTAssertTrue(prompt.contains("query (string, required)"))
        XCTAssertTrue(prompt.contains(TextToolProtocol.marker))
    }
}

// MARK: - E2B Connect framing tests (V4.0)

final class E2BConnectFrameTests: XCTestCase {

    func testFrameEncodingRoundTrip() {
        let payload = Data("{\"process\":{\"cmd\":\"/bin/bash\"}}".utf8)
        let frame = E2BComputer.connectFrame(payload)

        // 1 flag byte + 4 length bytes + payload.
        XCTAssertEqual(frame.count, payload.count + 5)
        XCTAssertEqual(frame[0], 0)
        let length = frame[1...4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        XCTAssertEqual(length, UInt32(payload.count))

        let decoded = E2BComputer.parseConnectFrames(frame)
        XCTAssertEqual(decoded, [payload])
    }

    func testParsesMultipleFramesAndSkipsEndOfStream() {
        let first = Data("{\"event\":{\"data\":{\"stdout\":\"hello \"}}}".utf8)
        let second = Data("{\"event\":{\"data\":{\"stdout\":\"world\"}}}".utf8)
        let endStream = Data("{\"error\":null}".utf8)

        var body = E2BComputer.connectFrame(first)
        body.append(E2BComputer.connectFrame(second))
        // End-of-stream frame carries flag 0x02 and is skipped.
        var endFrame = Data([0x02])
        var length = UInt32(endStream.count).bigEndian
        endFrame.append(Data(bytes: &length, count: 4))
        endFrame.append(endStream)
        body.append(endFrame)

        let decoded = E2BComputer.parseConnectFrames(body)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0], first)
        XCTAssertEqual(decoded[1], second)
    }

    func testTruncatedBodyYieldsWhatItHas() {
        let payload = Data("{\"a\":1}".utf8)
        var body = E2BComputer.connectFrame(payload)
        body.removeLast(2) // simulate truncation
        let decoded = E2BComputer.parseConnectFrames(body)
        XCTAssertTrue(decoded.isEmpty)
    }
}

// MARK: - Text-mode wire transform tests (V4.0)

final class TextModeWireTests: XCTestCase {

    func testToolMessagesBecomeUserResults() {
        var messages: [ChatMessage] = [
            .system("You are Astral."),
            .user("List the files."),
        ]
        messages.append(ChatMessage(
            role: .assistant, content: "", toolCalls: [
                ToolCall(id: "call_1", name: "exec", arguments: "{\"command\":\"ls\"}"),
            ]))
        messages.append(ChatMessage.tool(name: "exec", callId: "call_1", content: "fileA\nfileB"))

        let tools = [ToolSpec(name: "exec", description: "Run a shell command")]
        let wire = LLMService.textModeWireMessages(messages, tools: tools)

        // No tool or assistant-with-toolCalls roles on the wire.
        XCTAssertFalse(wire.contains { $0.role == .tool })
        XCTAssertFalse(wire.contains { ($0.toolCalls ?? []).isEmpty == false })

        // The assistant marker line is present.
        XCTAssertTrue(wire.contains {
            $0.role == .assistant && $0.content.contains("ASTRAL_TOOL") && $0.content.contains("exec")
        })
        // The result rides as a user message.
        XCTAssertTrue(wire.contains {
            $0.role == .user && $0.content.contains("TOOL_RESULT[exec]") && $0.content.contains("fileA")
        })
        // The protocol instructions ride as a trailing system message.
        XCTAssertEqual(wire.last?.role, .system)
        XCTAssertTrue(wire.last?.content.contains("TOOL USE PROTOCOL") ?? false)
    }

    func testEmptyToolsLeavesMessagesUntouched() {
        let messages: [ChatMessage] = [.system("hi"), .user("hello")]
        XCTAssertEqual(LLMService.textModeWireMessages(messages, tools: nil).count, 2)
    }

    func testRenderTextCallIsParsableBack() {
        let call = ToolCall(id: "x", name: "web_search", arguments: "{\"query\":\"cairo weather\"}")
        let line = LLMService.renderTextCall(call)
        // The rendered line must parse back into the same call.
        let parsed = TextToolProtocol.parseCalls(in: line)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].name, "web_search")
        XCTAssertTrue(parsed[0].argumentsJSON.contains("cairo weather"))
    }
}
