import XCTest
@testable import AstralAI

/// Round-trip Codable tests for the shared contract types defined in
/// Core/Contracts.swift, plus behavior tests for ToolCall.parsedArguments,
/// the ProviderConfig model-role fallback and the FileKind extension
/// mapping. These tests pin the persistence/transport contract of the app.
final class ContractsCodableTests: XCTestCase {

    /// Encodes then decodes a value, asserting a lossless round trip.
    private func roundtrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: JSONValue

    func testJSONValueRoundtripAllVariants() throws {
        let value: JSONValue = .object([
            "string": .string("hello"),
            "int": .number(42),
            "double": .number(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.string("a"), .number(7), .bool(false), .null]),
            "nested": .object([
                "deep": .array([.object(["key": .string("value")])])
            ])
        ])
        let decoded = try roundtrip(value)
        XCTAssertEqual(decoded, value)
        // Spot-check the accessors on the decoded tree.
        XCTAssertEqual(decoded.objectValue?["string"], JSONValue.string("hello"))
        XCTAssertEqual(decoded.objectValue?["double"]?.doubleValue, 3.14)
        XCTAssertEqual(decoded.objectValue?["array"]?.arrayValue?.count, 4)
        XCTAssertEqual(decoded.objectValue?["nested"], value.objectValue?["nested"])
    }

    // MARK: ChatMessage

    func testChatMessageRoundtripWithToolCalls() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let message = ChatMessage(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            role: .assistant,
            content: "I will write the file now.",
            toolCalls: [
                ToolCall(
                    id: "call_1",
                    name: "write_file",
                    arguments: "{\"path\":\"report.md\",\"content\":\"# Hi\"}"
                )
            ],
            toolCallId: nil,
            name: nil,
            createdAt: createdAt
        )
        let decoded = try roundtrip(message)
        // ChatMessage equality is identity-based (id only), so compare fields.
        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "I will write the file now.")
        XCTAssertEqual(decoded.toolCalls, message.toolCalls)
        XCTAssertEqual(decoded.toolCalls?.first?.name, "write_file")
        XCTAssertEqual(
            decoded.createdAt.timeIntervalSinceReferenceDate,
            createdAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }

    func testToolMessageRoundtrip() throws {
        let message = ChatMessage.tool(
            name: "browser_open",
            callId: "call_9",
            content: "{\"title\":\"Astral\"}"
        )
        let decoded = try roundtrip(message)
        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.role, .tool)
        XCTAssertEqual(decoded.toolCallId, "call_9")
        XCTAssertEqual(decoded.name, "browser_open")
        XCTAssertEqual(decoded.content, "{\"title\":\"Astral\"}")
    }

    // MARK: ProviderConfig

    func testProviderConfigRoundtripWithCustomProtocol() throws {
        var custom = CustomProtocolConfig()
        custom.chatPath = "/api/chat"
        custom.modelsPath = "/api/tags"
        custom.method = "POST"
        custom.authStyle = .customHeader
        custom.authHeaderName = "x-api-key"
        custom.authValueFormat = "%@"
        custom.extraHeaders = ["X-Client": "astral"]
        custom.extraBody = ["stream": .bool(false), "temperature": .number(0.2)]
        custom.streamFormat = .ndjson
        custom.streamTextPath = "message.content"
        custom.fullTextPath = "message.content"
        custom.toolCallsPath = "message.tool_calls"
        custom.finishPath = "done_reason"
        custom.modelsIDPath = "models.[].name"

        let config = ProviderConfig(
            name: "Local Ollama",
            baseURL: "http://localhost:11434",
            protocolKind: .custom,
            custom: custom,
            sendKeyForModels: false,
            mainModel: "llama3.1",
            plannerModel: "",
            subAgentModel: "qwen2.5",
            temperature: 0.2,
            maxTokens: 4096,
            timeout: 120
        )
        let decoded = try roundtrip(config)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.protocolKind, .custom)
        XCTAssertEqual(decoded.custom.chatPath, "/api/chat")
        XCTAssertEqual(decoded.custom.streamTextPath, "message.content")
        XCTAssertEqual(decoded.custom.modelsIDPath, "models.[].name")
    }

    func testProviderConfigDefaultsRoundtrip() throws {
        let config = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com")
        let decoded = try roundtrip(config)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.protocolKind, .openAICompatible)
        XCTAssertEqual(decoded.custom.streamTextPath, "choices.0.delta.content")
        XCTAssertEqual(decoded.custom.authValueFormat, "Bearer %@")
    }

    func testModelRoleFallback() {
        let config = ProviderConfig(
            name: "Mixed",
            baseURL: "https://api.groq.com/openai/v1",
            mainModel: "llama-3.3-70b",
            plannerModel: "",
            subAgentModel: "mixtral-8x7b"
        )
        XCTAssertEqual(config.model(for: .main), "llama-3.3-70b")
        // An empty planner model falls back to the main model.
        XCTAssertEqual(config.model(for: .planner), "llama-3.3-70b")
        // A configured sub-agent model is used as-is.
        XCTAssertEqual(config.model(for: .subAgent), "mixtral-8x7b")
    }

    // MARK: ExecutionPlan

    func testExecutionPlanRoundtrip() throws {
        let plan = ExecutionPlan(
            goal: "Research the Mars mission and produce a report",
            summary: "Search, draft, export",
            steps: [
                PlanStep(
                    index: 0,
                    title: "Search for the latest mission updates",
                    detail: "Use the browser to collect facts",
                    status: .pending,
                    result: "",
                    parallelizable: true,
                    needsBrowser: true
                ),
                PlanStep(
                    index: 1,
                    title: "Draft the markdown report",
                    detail: "Write the file into the workspace",
                    status: .inProgress,
                    result: "Draft started"
                ),
                PlanStep(
                    index: 2,
                    title: "Export deliverables",
                    detail: "Zip the workspace output",
                    status: .pending,
                    parallelizable: false
                )
            ]
        )
        let decoded = try roundtrip(plan)
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.steps.count, 3)
        XCTAssertEqual(decoded.steps[0].needsBrowser, true)
        XCTAssertEqual(decoded.steps[1].status, .inProgress)
        XCTAssertEqual(decoded.steps[2].parallelizable, false)
    }

    // MARK: ToolSpec

    func testToolSpecRoundtripWithParameters() throws {
        let spec = ToolSpec(
            name: "write_file",
            description: "Writes a text file into the agent workspace",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Relative workspace path")
                    ]),
                    "content": .object(["type": .string("string")])
                ]),
                "required": .array([.string("path"), .string("content")])
            ])
        )
        let decoded = try roundtrip(spec)
        XCTAssertEqual(decoded, spec)
        XCTAssertEqual(decoded.type, "function")
        XCTAssertEqual(decoded.function.name, "write_file")
        XCTAssertEqual(
            decoded.function.parameters?.objectValue?["required"]?.arrayValue?.count,
            2
        )
    }

    // MARK: ToolCall.parsedArguments

    func testParsedArgumentsWithValidJSONObject() {
        let call = ToolCall(
            id: "call_1",
            name: "write_file",
            arguments: "{\"path\":\"notes.md\",\"overwrite\":true,\"retries\":2}"
        )
        let args = call.parsedArguments
        XCTAssertEqual(args["path"], JSONValue.string("notes.md"))
        XCTAssertEqual(args["overwrite"], JSONValue.bool(true))
        XCTAssertEqual(args["retries"], JSONValue.number(2))
    }

    func testParsedArgumentsWithInvalidJSONFallsBackToRaw() {
        let call = ToolCall(id: "call_2", name: "broken_tool", arguments: "not json at all")
        XCTAssertEqual(call.parsedArguments, ["raw": JSONValue.string("not json at all")])
    }

    func testParsedArgumentsWithNonObjectJSONFallsBackToRaw() {
        let call = ToolCall(id: "call_3", name: "array_args", arguments: "[1,2,3]")
        XCTAssertEqual(call.parsedArguments, ["raw": JSONValue.string("[1,2,3]")])
    }

    // MARK: FileKind

    func testFileKindExtensionMapping() {
        XCTAssertEqual(FileKind(fileName: "report.md"), .markdown)
        XCTAssertEqual(FileKind(fileName: "notes.markdown"), .markdown)
        XCTAssertEqual(FileKind(fileName: "a.csv"), .spreadsheet)
        XCTAssertEqual(FileKind(fileName: "data.tsv"), .spreadsheet)
        XCTAssertEqual(FileKind(fileName: "s.py"), .code)
        XCTAssertEqual(FileKind(fileName: "main.swift"), .code)
        XCTAssertEqual(FileKind(fileName: "x.zip"), .archive)
        XCTAssertEqual(FileKind(fileName: "photo.png"), .image)
        XCTAssertEqual(FileKind(fileName: "demo.mp4"), .video)
        XCTAssertEqual(FileKind(fileName: "clip.mov"), .video)
        XCTAssertEqual(FileKind(fileName: "index.html"), .web)
        XCTAssertEqual(FileKind(fileName: "doc.pdf"), .pdf)
        XCTAssertEqual(FileKind(fileName: "trace.log"), .text)
        // Extensions are matched case-insensitively.
        XCTAssertEqual(FileKind(fileName: "README.MD"), .markdown)
        // Unknown or missing extensions fall back to .other.
        XCTAssertEqual(FileKind(fileName: "mystery.dat"), .other)
        XCTAssertEqual(FileKind(fileName: "noextension"), .other)
    }

    // MARK: V2 — Message images & videos

    func testChatMessageRoundtripWithImages() throws {
        let image = MessageImage(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            fileName: "ABC.jpg",
            mimeType: "image/jpeg")
        let message = ChatMessage.user("What is in this picture?", images: [image])

        let decoded = try roundtrip(message)
        XCTAssertEqual(decoded.role, .user)
        XCTAssertEqual(decoded.content, "What is in this picture?")
        XCTAssertEqual(decoded.images, [image])
        XCTAssertEqual(decoded.images?.first?.fileName, "ABC.jpg")
    }

    func testChatMessageRoundtripWithVideos() throws {
        let video = MessageVideo(
            id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            fileName: "demo.mp4",
            workspacePath: "Videos/demo.mp4",
            mimeType: "video/mp4",
            durationSeconds: 4.0,
            fileSize: 12000)
        let message = ChatMessage.user("Check this video", videos: [video])

        let decoded = try roundtrip(message)
        XCTAssertEqual(decoded.role, .user)
        XCTAssertEqual(decoded.videos, [video])
        XCTAssertEqual(decoded.videos?.first?.workspacePath, "Videos/demo.mp4")
    }

    func testChatMessageDecodesV1PayloadWithoutImagesKey() throws {
        // A V1 snapshot: no "images" key at all. Decoding must succeed with
        // images == nil so old conversations keep loading in V2.
        let json = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","role":"user","content":"hello","createdAt":700000000.0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.content, "hello")
        XCTAssertEqual(decoded.role, .user)
        XCTAssertNil(decoded.images)
        XCTAssertNil(decoded.videos)
    }

    func testChatMessageEncodeOmitsNilImages() throws {
        let message = ChatMessage.assistant("done")
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        XCTAssertFalse(object.keys.contains("images"), "nil images must not be encoded")
        XCTAssertFalse(object.keys.contains("videos"), "nil videos must not be encoded")
    }
}
