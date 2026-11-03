import XCTest
@testable import AstralAI

/// Unit tests for LLMService.sanitizedForWire: the history sanitizer that
/// guarantees strict providers (xAI, OpenAI, Groq, AWS…) never see broken
/// tool structure after a `suffix(24)` window cut or an interrupted
/// tool loop.
final class HistorySanitizerTests: XCTestCase {

    /// Comparable projection of a ChatMessage (ChatMessage.== compares ids
    /// only, which is useless for these assertions).
    private struct Shape: Equatable {
        let role: MessageRole
        let content: String
        let callIDs: [String]
        let toolCallID: String?

        /// Explicit memberwise initializer (the custom ChatMessage init in
        /// the body suppresses Swift's synthesized one).
        init(role: MessageRole, content: String, callIDs: [String], toolCallID: String?) {
            self.role = role
            self.content = content
            self.callIDs = callIDs
            self.toolCallID = toolCallID
        }

        init(_ message: ChatMessage) {
            role = message.role
            content = message.content
            callIDs = (message.toolCalls ?? []).map { $0.id }
            toolCallID = message.toolCallId
        }

        static func system(_ text: String) -> Shape {
            Shape(role: .system, content: text, callIDs: [], toolCallID: nil)
        }
        static func user(_ text: String) -> Shape {
            Shape(role: .user, content: text, callIDs: [], toolCallID: nil)
        }
        static func assistant(_ text: String, calls: [String] = []) -> Shape {
            Shape(role: .assistant, content: text, callIDs: calls, toolCallID: nil)
        }
        static func tool(_ callID: String, content: String) -> Shape {
            Shape(role: .tool, content: content, callIDs: [], toolCallID: callID)
        }
    }

    private func shapes(_ messages: [ChatMessage]) -> [Shape] {
        messages.map(Shape.init)
    }

    private func assistant(_ text: String, calls: [ToolCall]) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, toolCalls: calls)
    }

    private func call(_ id: String) -> ToolCall {
        ToolCall(id: id, name: "web_search", arguments: "{}")
    }

    // MARK: Orphans

    func testOrphanToolMessageDroppedWhenParentCutOff() {
        // Window starts with tool results whose parent assistant message
        // was cut off by suffix(24).
        let input = [
            ChatMessage.tool(name: "web_search", callId: "a", content: "r1"),
            ChatMessage.tool(name: "web_search", callId: "b", content: "r2"),
            ChatMessage.user("continue"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .user("continue"),
        ])
    }

    func testToolMessageWithoutCallIdDropped() {
        let input = [
            ChatMessage(role: .tool, content: "no id"),
            ChatMessage.user("hi"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .user("hi"),
        ])
    }

    // MARK: Partial tool-call sets

    func testAssistantWithTwoCallsOneAnsweredIsTrimmed() {
        let input = [
            ChatMessage.system("sys"),
            ChatMessage.user("hi"),
            assistant("checking", calls: [call("a"), call("b")]),
            ChatMessage.tool(name: "web_search", callId: "a", content: "ra"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .system("sys"),
            .user("hi"),
            .assistant("checking", calls: ["a"]),
            .tool("a", content: "ra"),
        ])
    }

    func testAssistantWithAllCallsUnansweredKeptAsPlainText() {
        // A turn interrupted right after the model requested tools leaves
        // an assistant tool_calls message with no results.
        let input = [
            ChatMessage.user("hi"),
            assistant("let me check", calls: [call("a"), call("b")]),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .user("hi"),
            .assistant("let me check", calls: []),
        ])
    }

    func testAssistantWithNoCallsAndEmptyContentDropped() {
        let input = [
            ChatMessage.user("hi"),
            ChatMessage(role: .assistant, content: ""),
            ChatMessage.user("again"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .user("hi"),
            .user("again"),
        ])
    }

    // MARK: Duplicates

    func testDuplicateToolResponsesKeepFirst() {
        let input = [
            assistant("", calls: [call("a")]),
            ChatMessage.tool(name: "web_search", callId: "a", content: "first"),
            ChatMessage.tool(name: "web_search", callId: "a", content: "second"),
            ChatMessage.user("go on"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .assistant("", calls: ["a"]),
            .tool("a", content: "first"),
            .user("go on"),
        ])
    }

    // MARK: Leading tool messages

    func testWindowNeverStartsWithToolMessage() {
        let input = [
            ChatMessage.tool(name: "web_search", callId: "a", content: "r"),
            assistant("", calls: [call("a")]),
            ChatMessage.tool(name: "web_search", callId: "a", content: "r"),
            ChatMessage.user("next"),
        ]
        let output = LLMService.sanitizedForWire(input)
        XCTAssertNotEqual(output.first?.role, .tool)
        XCTAssertTrue(output.contains { $0.role == .user && $0.content == "next" })
    }

    // MARK: Intact histories pass through

    func testValidToolConversationIsUntouched() {
        let input = [
            ChatMessage.system("sys"),
            ChatMessage.user("search"),
            assistant("", calls: [call("a"), call("b")]),
            ChatMessage.tool(name: "web_search", callId: "a", content: "ra"),
            ChatMessage.tool(name: "web_search", callId: "b", content: "rb"),
            ChatMessage.user("thanks"),
            ChatMessage.assistant("done"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .system("sys"),
            .user("search"),
            .assistant("", calls: ["a", "b"]),
            .tool("a", content: "ra"),
            .tool("b", content: "rb"),
            .user("thanks"),
            .assistant("done"),
        ])
    }

    func testSystemAndUserMessagesAreUntouched() {
        let input = [
            ChatMessage.system("s1"),
            ChatMessage.user("u1"),
            ChatMessage.system("s2"),
            ChatMessage.user("u2"),
        ]
        XCTAssertEqual(shapes(LLMService.sanitizedForWire(input)), [
            .system("s1"),
            .user("u1"),
            .system("s2"),
            .user("u2"),
        ])
    }

    func testEmptyHistoryStaysEmpty() {
        XCTAssertEqual(LLMService.sanitizedForWire([]), [])
    }

    // MARK: Integration with the request builder

    func testMakeChatRequestsSanitizesMessagesOnTheWire() throws {
        // A sanitized payload must never contain an orphan tool message:
        // build a request with broken history and inspect the JSON body.
        let config = ProviderConfig(name: "Test", baseURL: "https://api.example.com")
        let broken = [
            ChatMessage.tool(name: "web_search", callId: "zzz", content: "orphan"),
            ChatMessage.user("hello"),
        ]
        let requests = try LLMService.makeChatRequests(
            config: config,
            apiKey: "k",
            messages: broken,
            tools: nil,
            model: "m",
            stream: false)
        guard let body = requests.first?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body, options: [])
                  as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return XCTFail("Request body not decodable")
        }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hello")
    }
}
