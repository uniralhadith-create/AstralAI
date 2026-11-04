import Foundation

// MARK: - App Identity

/// Global app identity constants shared across the whole project.
public enum AppIdentity {
    public static let appName = "Astral AI"
    public static let developer = "Tariq El-Fares"
    public static let company = "UNIRAL"
    public static let instagramURL = "https://www.instagram.com/astral.tariq"
    public static let bundleIDPrefix = "com.uniral.astralai"
}

// MARK: - JSON Value

/// A JSON-friendly value type used for tool schemas, custom request bodies
/// and generic tool arguments.
public enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        }
    }

    // Convenience accessors
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    public var intValue: Int? {
        if case .number(let n) = self { return n == n.rounded() ? Int(n) : nil }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Converts any Codable-compatible primitive into a JSONValue.
    public static func from(any: Any) -> JSONValue {
        switch any {
        case let v as String: return .string(v)
        case let v as Bool: return .bool(v)
        case let v as Int: return .number(Double(v))
        case let v as Double: return .number(v)
        case let v as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, val) in v { out[k] = .from(any: val) }
            return .object(out)
        case let v as [Any]:
            return .array(v.map { .from(any: $0) })
        case is NSNull: return .null
        case Optional<Any>.none: return .null
        default: return .string("\(any)")
        }
    }

    /// Encodes this value into raw JSON Data.
    public func jsonData(pretty: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try? encoder.encode(self)
    }

    /// Decodes JSONValue from raw Data.
    public static func from(data: Data) -> JSONValue? {
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - Chat Messages

public enum MessageRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// A single tool invocation requested by the model.
public struct ToolCall: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Raw JSON-encoded arguments string.
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Parses the arguments string into a dictionary. Falls back to
    /// `["raw": <string>]` when the payload is not valid JSON.
    public var parsedArguments: [String: JSONValue] {
        guard let data = arguments.data(using: .utf8),
              let value = JSONValue.from(data: data),
              let object = value.objectValue else {
            return ["raw": .string(arguments)]
        }
        return object
    }
}

/// An image attached to a user message (vision input). Binary data lives in
/// the `MediaStore` folder; messages only persist this lightweight reference.
public struct MessageImage: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// File name inside `Documents/AstralMedia`.
    public var fileName: String
    /// Always `image/jpeg` after normalization.
    public var mimeType: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String = "image/jpeg"
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

/// A video attached to a user message or delivered by the agent in chat.
/// The video file is stored inside the Workspace (`Documents/AstralWorkspace/Videos/...`
/// or the relative workspace path) so it is always accessible in the Files tab.
public struct MessageVideo: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// Display or file name, e.g. "demo.mp4".
    public var fileName: String
    /// Workspace-relative path where the video is saved, e.g. "Videos/demo.mp4".
    public var workspacePath: String
    /// MIME type, e.g. "video/mp4" or "video/quicktime".
    public var mimeType: String
    /// Optional duration in seconds.
    public var durationSeconds: Double?
    /// Optional file size in bytes.
    public var fileSize: Int64?

    public init(
        id: UUID = UUID(),
        fileName: String,
        workspacePath: String,
        mimeType: String = "video/mp4",
        durationSeconds: Double? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.workspacePath = workspacePath
        self.mimeType = mimeType
        self.durationSeconds = durationSeconds
        self.fileSize = fileSize
    }
}

/// A file attached to a user message. The extracted plain text travels
/// with the message (capped by the importer) so the model can read it;
/// the UI shows only the lightweight name chip.
public struct MessageAttachment: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// Display name including extension, e.g. "report.pdf".
    public var name: String
    /// Extracted plain text sent to the model.
    public var text: String

    public init(
        id: UUID = UUID(),
        name: String,
        text: String
    ) {
        self.id = id
        self.name = name
        self.text = text
    }
}

/// A conversation message exchanged with the model.
public struct ChatMessage: Codable, Equatable, Identifiable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    /// Tool calls requested by the assistant (role == .assistant).
    public var toolCalls: [ToolCall]?
    /// Tool-call id this message answers (role == .tool).
    public var toolCallId: String?
    /// Tool or function name (role == .tool).
    public var name: String?
    /// Images attached to this message (role == .user) for vision input.
    public var images: [MessageImage]?
    /// Videos attached to this message or delivered by a tool in chat.
    public var videos: [MessageVideo]?
    /// Files attached to this message (role == .user); their extracted
    /// text is appended to the wire content (see `wireContent`).
    public var attachments: [MessageAttachment]?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil,
        images: [MessageImage]? = nil,
        videos: [MessageVideo]? = nil,
        attachments: [MessageAttachment]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
        self.images = images
        self.videos = videos
        self.attachments = attachments
        self.createdAt = createdAt
    }

    /// The content actually sent to the model: the message text plus every
    /// attachment's extracted text and any attached video workspace paths
    /// in clearly-delimited blocks.
    public var wireContent: String {
        let hasAttachments = !(attachments ?? []).isEmpty
        let hasVideos = !(videos ?? []).isEmpty
        guard hasAttachments || hasVideos else {
            return content
        }
        var blocks: [String] = []
        if !content.isEmpty {
            blocks.append(content)
        }
        if let videos {
            for video in videos {
                var meta = "[Attached video saved in workspace: \(video.workspacePath) (file: \(video.fileName))"
                if let dur = video.durationSeconds, dur > 0 {
                    meta += String(format: ", duration: %.1fs", dur)
                }
                if let size = video.fileSize, size > 0 {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    meta += ", size: \(sizeStr)"
                }
                meta += "]"
                blocks.append(meta)
            }
        }
        if let attachments {
            for attachment in attachments where !attachment.text.isEmpty {
                blocks.append(
                    "[Attached file: \(attachment.name)]\n\(attachment.text)")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: text)
    }
    public static func user(
        _ text: String,
        images: [MessageImage]? = nil,
        videos: [MessageVideo]? = nil,
        attachments: [MessageAttachment]? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .user,
            content: text,
            images: images,
            videos: videos,
            attachments: attachments)
    }
    public static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: text)
    }
    public static func tool(name: String, callId: String, content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCallId: callId, name: name)
    }

    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Codable (manual: keeps decoding snapshots written by earlier versions lossless)

    private enum CodingKeys: String, CodingKey {
        case id, role, content, toolCalls, toolCallId, name, images, videos, attachments, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        images = try container.decodeIfPresent([MessageImage].self, forKey: .images)
        videos = try container.decodeIfPresent([MessageVideo].self, forKey: .videos)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(videos, forKey: .videos)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Tool Specifications

/// A tool/function definition following the OpenAI function-calling shape.
public struct ToolSpec: Codable, Equatable {
    public var type: String
    public var function: FunctionSpec

    public struct FunctionSpec: Codable, Equatable {
        public var name: String
        public var description: String
        /// JSON-schema style parameters object.
        public var parameters: JSONValue?

        public init(name: String, description: String, parameters: JSONValue? = nil) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public init(name: String, description: String, parameters: JSONValue? = nil) {
        self.type = "function"
        self.function = FunctionSpec(name: name, description: description, parameters: parameters)
    }
}

/// The result of running a tool, handed back to the model.
public struct ToolResult: Codable, Equatable {
    public var content: String
    public var isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

/// Information about the session a tool runs inside.
public struct SessionInfo: Codable, Equatable {
    public let sessionID: UUID
    public let goal: String
    public init(sessionID: UUID, goal: String) {
        self.sessionID = sessionID
        self.goal = goal
    }
}

/// Context handed to every tool execution.
@MainActor
public final class ToolContext {
    public let browser: BrowserControlling?
    public let workspace: WorkspaceRouting
    public let system: SystemServicing?
    public let session: SessionInfo
    public let isSubAgent: Bool
    /// The id of the tool call this context was built for. Set by
    /// `ToolRegistry.execute` so tools that produce deliverables (like
    /// `browser_screenshot` and `send_video`) can register them against the exact call.
    public var callID: String?

    public init(
        browser: BrowserControlling?,
        workspace: WorkspaceRouting,
        system: SystemServicing?,
        session: SessionInfo,
        isSubAgent: Bool = false
    ) {
        self.browser = browser
        self.workspace = workspace
        self.system = system
        self.session = session
        self.isSubAgent = isSubAgent
    }
}

/// A capability the agent can invoke.
@MainActor
public protocol AgentTool {
    /// Unique snake_case tool name used by the model.
    var name: String { get }
    /// The schema advertised to the model.
    var spec: ToolSpec { get }
    /// Executes the tool.
    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult
}

// MARK: - LLM Provider Abstraction

/// Events emitted while streaming a chat completion.
public enum LLMEvent {
    case textDelta(String)
    /// Complete tool calls (emitted once, when the model requests them).
    case toolCalls([ToolCall])
    /// The provider rejected the tool schemas, so this request is being
    /// retried without tools — the turn degrades to a plain chat reply.
    /// Emitted BEFORE any text so listeners can surface the downgrade.
    case toolsDropped(reason: String)
    case finished(finishReason: String?)
}

/// Unified LLM errors.
public enum LLMError: LocalizedError, Equatable {
    case noActiveProvider
    case invalidURL(String)
    case unauthorized
    case rateLimited
    case badResponse(String)
    case network(String)
    case decoding(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noActiveProvider:
            return L("error.noProvider", "Shared")
        case .invalidURL(let u):
            return L("error.invalidURL", "Shared") + ": " + u
        case .unauthorized:
            return L("error.unauthorized", "Shared")
        case .rateLimited:
            return L("error.rateLimited", "Shared")
        case .badResponse(let detail):
            return L("error.badResponse", "Shared") + ": " + detail
        case .network(let detail):
            return L("error.network", "Shared") + ": " + detail
        case .decoding(let detail):
            return L("error.decoding", "Shared") + ": " + detail
        case .cancelled:
            return L("error.cancelled", "Shared")
        }
    }
}

/// Abstract LLM access — implemented by `LLMService` (Infra module),
/// consumed by the AgentCore module.
public protocol LLMProviding: AnyObject {
    /// Streams a chat completion. Emits `textDelta` chunks live, then
    /// `toolCalls` (if any) and finally `finished`.
    func streamChat(
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?
    ) -> AsyncThrowingStream<LLMEvent, Error>

    /// Non-streaming completion returning the full text.
    func complete(messages: [ChatMessage], model: String?) async throws -> String

    /// Asks the model for strict JSON and decodes it into `T`.
    func structured<T: Decodable>(
        messages: [ChatMessage],
        type: T.Type,
        model: String?
    ) async throws -> T

    /// Lists the models available at the provider.
    func listModels() async throws -> [ModelInfo]

    /// Resolves the model id configured for a role at the active provider
    /// (nil = provider default).
    func modelID(for role: ModelRole) -> String?
}

// MARK: - Provider Configuration

public enum APIProtocolKind: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case custom
    /// Native AWS Bedrock Converse API with SigV4 authentication.
    /// The API key is stored as `ACCESS_KEY_ID:SECRET_ACCESS_KEY` and the
    /// region is parsed from the `bedrock-runtime.{region}.amazonaws.com`
    /// base URL.
    case bedrock
    public var id: String { rawValue }
}

public enum AuthStyle: String, Codable, CaseIterable, Identifiable {
    case bearer
    case customHeader
    case none
    public var id: String { rawValue }
}

public enum StreamFormat: String, Codable, CaseIterable, Identifiable {
    case sse
    case ndjson
    case none
    public var id: String { rawValue }
}

/// Fully user-configurable request/response mapping for custom providers.
public struct CustomProtocolConfig: Codable, Equatable {
    public var chatPath: String
    public var modelsPath: String?
    public var method: String
    public var authStyle: AuthStyle
    public var authHeaderName: String
    /// Format string containing %@ where the key should be inserted,
    /// e.g. "Bearer %@" or just "%@".
    public var authValueFormat: String
    public var extraHeaders: [String: String]
    /// Merged into the top level of the request JSON body.
    public var extraBody: [String: JSONValue]
    public var streamFormat: StreamFormat
    /// Dot-path to the streamed text fragment inside each chunk.
    public var streamTextPath: String
    /// Dot-path to the full text inside a non-streamed response.
    public var fullTextPath: String
    /// Dot-path to tool calls inside a non-streamed response.
    public var toolCallsPath: String
    /// Dot-path to the finish reason.
    public var finishPath: String
    /// Dot-path (with [] for array) to model ids inside the models response.
    public var modelsIDPath: String

    public init(
        chatPath: String = "/v1/chat/completions",
        modelsPath: String? = "/v1/models",
        method: String = "POST",
        authStyle: AuthStyle = .bearer,
        authHeaderName: String = "Authorization",
        authValueFormat: String = "Bearer %@",
        extraHeaders: [String: String] = [:],
        extraBody: [String: JSONValue] = [:],
        streamFormat: StreamFormat = .sse,
        streamTextPath: String = "choices.0.delta.content",
        fullTextPath: String = "choices.0.message.content",
        toolCallsPath: String = "choices.0.message.tool_calls",
        finishPath: String = "choices.0.finish_reason",
        modelsIDPath: String = "data.[].id"
    ) {
        self.chatPath = chatPath
        self.modelsPath = modelsPath
        self.method = method
        self.authStyle = authStyle
        self.authHeaderName = authHeaderName
        self.authValueFormat = authValueFormat
        self.extraHeaders = extraHeaders
        self.extraBody = extraBody
        self.streamFormat = streamFormat
        self.streamTextPath = streamTextPath
        self.fullTextPath = fullTextPath
        self.toolCallsPath = toolCallsPath
        self.finishPath = finishPath
        self.modelsIDPath = modelsIDPath
    }
}

/// User-defined provider endpoint configuration.
public struct ProviderConfig: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Base URL, e.g. https://api.openai.com
    public var baseURL: String
    public var protocolKind: APIProtocolKind
    public var custom: CustomProtocolConfig
    /// Whether the API key should be sent with the models request.
    public var sendKeyForModels: Bool
    public var mainModel: String
    public var plannerModel: String
    public var subAgentModel: String
    public var temperature: Double
    public var maxTokens: Int?
    public var timeout: Double

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        protocolKind: APIProtocolKind = .openAICompatible,
        custom: CustomProtocolConfig = CustomProtocolConfig(),
        sendKeyForModels: Bool = true,
        mainModel: String = "",
        plannerModel: String = "",
        subAgentModel: String = "",
        temperature: Double = 0.4,
        maxTokens: Int? = nil,
        timeout: Double = 180
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.protocolKind = protocolKind
        self.custom = custom
        self.sendKeyForModels = sendKeyForModels
        self.mainModel = mainModel
        self.plannerModel = plannerModel
        self.subAgentModel = subAgentModel
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
    }

    public func model(for role: ModelRole) -> String {
        switch role {
        case .main: return mainModel
        case .planner: return plannerModel.isEmpty ? mainModel : plannerModel
        case .subAgent: return subAgentModel.isEmpty ? mainModel : subAgentModel
        }
    }
}

public enum ModelRole: String, CaseIterable, Identifiable {
    case main, planner, subAgent
    public var id: String { rawValue }
}

/// A model discovered at the provider.
public struct ModelInfo: Codable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String?
    public var ownedBy: String?
    public var contextLength: Int?
    public var supportsTools: Bool?

    public init(id: String, name: String? = nil, ownedBy: String? = nil, contextLength: Int? = nil, supportsTools: Bool? = nil) {
        self.id = id
        self.name = name
        self.ownedBy = ownedBy
        self.contextLength = contextLength
        self.supportsTools = supportsTools
    }
}

// MARK: - Plans & Sessions

public enum StepStatus: String, Codable {
    case pending
    case inProgress
    case done
    case failed
    case skipped
}

public struct PlanStep: Codable, Equatable, Identifiable {
    public var id: UUID
    public var index: Int
    public var title: String
    public var detail: String
    public var status: StepStatus
    public var result: String
    public var parallelizable: Bool
    public var needsBrowser: Bool

    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        detail: String = "",
        status: StepStatus = .pending,
        result: String = "",
        parallelizable: Bool = false,
        needsBrowser: Bool = false
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.detail = detail
        self.status = status
        self.result = result
        self.parallelizable = parallelizable
        self.needsBrowser = needsBrowser
    }
}

public struct ExecutionPlan: Codable, Equatable {
    public var goal: String
    public var summary: String?
    public var steps: [PlanStep]

    public init(goal: String, summary: String? = nil, steps: [PlanStep]) {
        self.goal = goal
        self.summary = summary
        self.steps = steps
    }
}

public enum SessionPhase: String, Codable {
    case idle
    case planning
    case responding
    case executing
    case merging
    case waitingUser
    case completed
    case failed
    case cancelled
    case interrupted
}

/// Live status of a parallel sub-agent.
public struct SubAgentStatus: Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var role: String
    public var state: SubAgentState
    public var currentAction: String
    public var progress: Double

    public init(
        id: UUID = UUID(),
        name: String,
        role: String,
        state: SubAgentState = .running,
        currentAction: String = "",
        progress: Double = 0
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.currentAction = currentAction
        self.progress = progress
    }
}

public enum SubAgentState: String, Codable {
    case running
    case finished
    case failed
}

/// Live status of the current turn, published by `AgentSession` for
/// the in-app status strip (V3). `label` is already localized.
public struct TurnStatus: Equatable {
    public let label: String
    public let detail: String
    public let progress: Double

    public init(label: String, detail: String, progress: Double) {
        self.label = label
        self.detail = detail
        self.progress = progress
    }
}

// MARK: - Browser Bridge

/// An interactive element extracted from the current web page.
public struct PageElement: Codable, Equatable, Identifiable {
    public var id: Int
    public var tag: String
    public var text: String
    public var selector: String

    public init(id: Int, tag: String, text: String, selector: String) {
        self.id = id
        self.tag = tag
        self.text = text
        self.selector = selector
    }
}

/// High-level browsing commands the agent can issue.
/// Implemented by `BrowserController` (Browser module).
@MainActor
public protocol BrowserControlling: AnyObject {
    func open(url: String) async throws -> String
    func clickElement(index: Int) async throws -> String
    func typeText(index: Int, text: String, submit: Bool) async throws -> String
    func scroll(direction: String, amount: Int) async throws -> String
    func extractText(maxChars: Int) async throws -> String
    func listElements() async throws -> [PageElement]
    func currentPageSummary() async throws -> String
    func goBack() async throws -> String
    func captureScreenshot() async throws -> Data
}

// MARK: - Workspace Bridge

public enum FileKind: String, Codable {
    case markdown
    case text
    case code
    case pdf
    case spreadsheet
    case image
    case video
    case archive
    case web
    case other

    public init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown": self = .markdown
        case "txt", "log", "rtf": self = .text
        case "pdf": self = .pdf
        case "csv", "tsv": self = .spreadsheet
        case "png", "jpg", "jpeg", "gif", "webp", "heic": self = .image
        case "mp4", "mov", "m4v", "webm", "mkv", "avi", "mpeg", "mpg", "3gp": self = .video
        case "zip": self = .archive
        case "html", "htm": self = .web
        case "swift", "py", "js", "ts", "tsx", "jsx", "json", "sh", "bash", "css",
             "java", "kt", "c", "cpp", "h", "go", "rs", "rb", "php", "sql", "yml", "yaml", "xml":
            self = .code
        default: self = .other
        }
    }
}

/// A file inside the workspace.
public struct WorkspaceFile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Path relative to the workspace root.
    public var relativePath: String
    public var size: Int64
    public var modifiedAt: Date
    public var kind: FileKind

    public init(
        id: String,
        name: String,
        relativePath: String,
        size: Int64,
        modifiedAt: Date,
        kind: FileKind
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.size = size
        self.modifiedAt = modifiedAt
        self.kind = kind
    }
}

/// File operations available to the agent. Implemented by `WorkspaceStore`.
@MainActor
public protocol WorkspaceRouting: AnyObject {
    var rootURL: URL { get }
    @discardableResult
    func write(path: String, content: String) throws -> URL
    @discardableResult
    func writeData(path: String, data: Data) throws -> URL
    @discardableResult
    func createFolder(path: String) throws -> URL
    func read(path: String) throws -> String
    func list() -> [WorkspaceFile]
    func delete(path: String) throws
    func zip(paths: [String], archiveName: String) throws -> URL
    func url(for path: String) -> URL?
}

// MARK: - System Services Bridge

@MainActor
public protocol SystemServicing: AnyObject {
    func notifyUser(title: String, body: String)
    func startLiveActivity(goal: String)
    func updateLiveActivity(step: String, progress: Double)
    func endLiveActivity(success: Bool)
    @discardableResult
    func createReminder(title: String, dueDate: Date?) async throws -> String
    @discardableResult
    func createCalendarEvent(title: String, start: Date, end: Date?, notes: String?) async throws -> String
}
