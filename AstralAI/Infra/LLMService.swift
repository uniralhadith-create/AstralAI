import Foundation

// MARK: - LLM service

/// Concrete LLM client implementing the `LLMProviding` contract.
///
/// Two protocol flavours are supported:
/// - OpenAI-compatible APIs: `/v1/chat/completions`, SSE streaming with
///   incremental tool-call assembly, and `/v1/models` discovery.
/// - Fully custom providers: every request path, HTTP method, header,
///   auth style, stream format and response field is mapped through
///   user-configured dot-paths (`CustomProtocolConfig`).
///
/// The service is intentionally NOT MainActor: it is invoked from agent
/// execution contexts running on background tasks.
final class LLMService: LLMProviding {

    private let configProvider: () -> ProviderConfig?

    /// A single shared session for the lifetime of the service. Per-request
    /// timeouts are applied through `URLRequest.timeoutInterval`, which
    /// overrides the session-wide default for each task.
    private let session: URLSession

    init(configProvider: @escaping () -> ProviderConfig?) {
        self.configProvider = configProvider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - LLMProviding

    func streamChat(
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    let config = try self.resolveConfig()
                    let apiKey = Self.storedKey(for: config)

                    // AWS Bedrock: native Converse streaming with SigV4.
                    if config.protocolKind == .bedrock {
                        let client = try Self.bedrockClient(config: config, apiKey: apiKey)
                        for try await event in client.streamChat(
                            messages: messages,
                            tools: tools,
                            session: self.session)
                        {
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    }

                    // OpenAI-compatible & custom: probe endpoint candidates
                    // until one answers (fixes /v1 vs /v1/v1 URL mismatches
                    // that broke NVIDIA NIM, xAI Grok and friends).
                    //
                    // V4.0 — the universal tool protocol: when the provider
                    // rejects the native `tools` schema (or the protocol
                    // simply cannot carry tool calls), the request is NOT
                    // downgraded into a plain chatbot anymore. Instead the
                    // tool suite rides inside the system prompt as text and
                    // the model's marker lines are parsed back into tool
                    // calls — every tool keeps working with every provider.
                    let (bytes, _) = try await Self.probeStream(
                        session: self.session,
                        config: config,
                        apiKey: apiKey,
                        messages: messages,
                        tools: tools,
                        model: model)

                    try await Self.runStream(
                        config: config,
                        bytes: bytes,
                        continuation: continuation,
                        tools: tools)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func complete(messages: [ChatMessage], model: String?) async throws -> String {
        let config = try resolveConfig()
        let apiKey = Self.storedKey(for: config)

        if config.protocolKind == .bedrock {
            let client = try Self.bedrockClient(config: config, apiKey: apiKey)
            let (text, _) = try await client.converse(
                messages: messages, tools: nil, session: session)
            guard !text.isEmpty else { throw LLMError.badResponse("Empty completion") }
            return text
        }

        let (data, _) = try await Self.probeData(
            session: session,
            config: config,
            apiKey: apiKey,
            messages: messages,
            tools: nil,
            model: model)
        return try Self.extractCompletionText(config: config, data: data)
    }

    func structured<T: Decodable>(
        messages: [ChatMessage],
        type: T.Type,
        model: String?
    ) async throws -> T {
        var conversation = messages
        conversation.append(ChatMessage.system(
            "Respond with ONLY valid JSON matching the requested structure. No markdown fences, no commentary."))

        let firstReply = try await complete(messages: conversation, model: model)
        if let decoded = JSONExtractor.decode(type, from: firstReply) {
            return decoded
        }

        // One self-correction attempt before giving up.
        conversation.append(ChatMessage.assistant(firstReply))
        conversation.append(ChatMessage.system(
            "Your previous reply was not valid JSON for the target type. Reply again with ONLY the corrected JSON."))
        let secondReply = try await complete(messages: conversation, model: model)
        if let decoded = JSONExtractor.decode(type, from: secondReply) {
            return decoded
        }

        throw LLMError.decoding(String(secondReply.prefix(200)))
    }

    func listModels() async throws -> [ModelInfo] {
        let config = try resolveConfig()
        return try await Self.fetchModels(config: config, apiKey: Self.storedKey(for: config))
    }

    func modelID(for role: ModelRole) -> String? {
        guard let value = configProvider()?.model(for: role), !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Static provider utilities

    /// Lists the models of an arbitrary provider configuration (used by the
    /// settings UI for providers that are not necessarily active).
    static func fetchModels(config: ProviderConfig, apiKey: String?) async throws -> [ModelInfo] {
        if config.protocolKind == .bedrock {
            let credentials = try bedrockCredentials(config: config, apiKey: apiKey)
            return try await BedrockClient.listModels(
                region: credentials.region,
                accessKey: credentials.access,
                secretKey: credentials.secret)
        }

        // AWS Bedrock hosts used through the OpenAI-compatible protocol:
        // sign the /openai/v1/models endpoint with SigV4 instead of probing
        // paths that do not exist on those hosts (the old 404 source).
        if config.protocolKind == .openAICompatible,
           let region = EndpointResolver.bedrockRegion(from: config.baseURL) {
            let credentials = try bedrockCredentials(config: config, apiKey: apiKey)
            let url = EndpointResolver.bedrockOpenAIModelsEndpoint(region: region)
            guard let request = BedrockClient.signedOpenAIRequest(
                region: region,
                accessKey: credentials.access,
                secretKey: credentials.secret,
                url: url,
                method: "GET",
                payload: Data()) else {
                throw LLMError.invalidURL(url)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw httpFailure(
                    status: http.statusCode,
                    body: String(data: data.prefix(2000), encoding: .utf8) ?? "")
            }
            guard let body = try? JSONSerialization.jsonObject(with: data, options: []) else {
                throw LLMError.badResponse("Non-JSON models response")
            }
            return Self.parseModelsList(config: config, body: body)
        }

        let candidates: [String]
        switch config.protocolKind {
        case .openAICompatible:
            candidates = EndpointResolver.modelsEndpointCandidates(config.baseURL)
        case .custom:
            guard let modelsPath = config.custom.modelsPath, !modelsPath.isEmpty else {
                throw LLMError.badResponse("Models endpoint not configured")
            }
            candidates = [try customEndpoint(config: config, path: modelsPath)]
        case .bedrock:
            candidates = []
        }

        var probeError: Error?
        for endpoint in candidates {
            var request = try makeRequest(
                config: config,
                apiKey: apiKey,
                endpoint: endpoint,
                method: "GET",
                body: nil,
                sendKey: config.sendKeyForModels)
            request.timeoutInterval = min(max(config.timeout, 5), 60)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                probeError = httpFailure(
                    status: http.statusCode,
                    body: String(data: data.prefix(2000), encoding: .utf8) ?? "")
                if (http.statusCode == 404 || http.statusCode == 400), candidates.count > 1 {
                    continue
                }
                throw probeError!
            }

            guard let body = try? JSONSerialization.jsonObject(with: data, options: []) else {
                throw LLMError.badResponse("Non-JSON models response")
            }
            return Self.parseModelsList(config: config, body: body)
        }
        throw probeError ?? LLMError.badResponse("Models endpoint unreachable")
    }

    /// Parses a models-list JSON document into `ModelInfo` entries.
    private static func parseModelsList(config: ProviderConfig, body: Any) -> [ModelInfo] {
        var models: [ModelInfo] = []
        switch config.protocolKind {
        case .openAICompatible:
            let entries: [Any]
            if let root = body as? [String: Any], let list = root["data"] as? [Any] {
                entries = list
            } else if let list = body as? [Any] {
                entries = list
            } else {
                entries = []
            }
            for entry in entries {
                guard let dictionary = entry as? [String: Any],
                      let id = dictionary["id"] as? String,
                      !id.isEmpty else { continue }
                let contextLength = (dictionary["context_length"] as? NSNumber)?.intValue
                // OpenRouter advertises per-model capabilities through
                // `supported_parameters`; "tools" marks native function
                // calling. (V4.0: drives the tools badge in the picker —
                // models without it still work via the text protocol.)
                var supportsTools: Bool?
                if let parameters = dictionary["supported_parameters"] as? [String] {
                    supportsTools = parameters.contains("tools")
                }
                models.append(ModelInfo(
                    id: id,
                    name: dictionary["name"] as? String,
                    ownedBy: dictionary["owned_by"] as? String,
                    contextLength: contextLength,
                    supportsTools: supportsTools))
            }
        case .custom:
            for entry in DotPath.extractArray(from: body, path: config.custom.modelsIDPath) {
                if let id = DotPath.stringValue(entry), !id.isEmpty {
                    models.append(ModelInfo(id: id))
                }
            }
        case .bedrock:
            break
        }
        return models.sorted { $0.id < $1.id }
    }

    /// Sends a minimal chat request and returns (reply, elapsed seconds).
    /// Any error propagates to the caller.
    static func testConnection(config: ProviderConfig, apiKey: String?) async throws -> (String, TimeInterval) {
        let started = Date()

        if config.protocolKind == .bedrock {
            let client = try bedrockClient(config: config, apiKey: apiKey)
            let (reply, _) = try await client.converse(
                messages: [ChatMessage.user("Reply with exactly: OK")],
                tools: nil,
                session: URLSession.shared)
            return (reply, Date().timeIntervalSince(started))
        }

        let (data, _) = try await Self.probeData(
            session: URLSession.shared,
            config: config,
            apiKey: apiKey,
            messages: [ChatMessage.user("Reply with exactly: OK")],
            tools: nil,
            model: nil,
            timeout: 30)
        let reply = try extractCompletionText(config: config, data: data)
        return (reply, Date().timeIntervalSince(started))
    }

    // MARK: - Endpoint probing

    /// Probes chat endpoints (streaming flavor) until one answers. When the
    /// provider rejects the native tool schemas, the request is retried on
    /// the universal TEXT tool protocol instead of dropping the tools —
    /// the agent never degrades into a plain chatbot anymore. The bool
    /// result reports whether the text protocol is active.
    static func probeStream(
        session: URLSession,
        config: ProviderConfig,
        apiKey: String?,
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?
    ) async throws -> (URLSession.AsyncBytes, Bool) {
        let wantsTools = !(tools ?? []).isEmpty
        var useNativeTools = wantsTools
        var useTextProtocol = false
        var lastError: Error?

        // Custom SSE protocols cannot carry native tool_calls at all —
        // start directly on the text protocol so tools work there too.
        if wantsTools, config.protocolKind == .custom, config.custom.streamFormat == .sse {
            useNativeTools = false
            useTextProtocol = true
        }

        while true {
            let wireMessages = useTextProtocol
                ? Self.textModeWireMessages(messages, tools: tools)
                : messages
            let requests = try makeChatRequests(
                config: config,
                apiKey: apiKey,
                messages: wireMessages,
                tools: useNativeTools ? tools : nil,
                model: model,
                stream: true)

            for request in requests {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        let body = await ByteLineReader.drain(bytes, limit: 2000)
                        lastError = Self.httpFailure(status: http.statusCode, body: body)
                        // 404/400/422 usually mean a wrong path or rejected
                        // payload — try the next candidate. Other statuses
                        // (401, 429, 5xx) are endpoint-independent: fail fast.
                        if http.statusCode == 404 || http.statusCode == 400 || http.statusCode == 422 {
                            continue
                        }
                        throw lastError!
                    }
                    return (bytes, useTextProtocol)
                } catch let error as LLMError {
                    throw error
                }
            }

            // Every candidate failed with a path/schema-level error.
            if useNativeTools, let error = lastError,
               Self.looksLikeToolRejection(error) {
                // V4.0: switch to the universal text tool protocol rather
                // than silently stripping the agent's tools.
                useNativeTools = false
                useTextProtocol = true
                continue
            }
            throw lastError ?? LLMError.badResponse("No endpoint reachable")
        }
    }

    /// Probes chat endpoints (non-streaming flavor) until one answers,
    /// returning the response body.
    static func probeData(
        session: URLSession,
        config: ProviderConfig,
        apiKey: String?,
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, HTTPURLResponse?) {
        var includeTools = !(tools ?? []).isEmpty
        var lastError: Error?

        while true {
            let requests = try makeChatRequests(
                config: config,
                apiKey: apiKey,
                messages: messages,
                tools: includeTools ? tools : nil,
                model: model,
                stream: false)

            for request in requests {
                var mutable = request
                if let timeout { mutable.timeoutInterval = timeout }
                let (data, response) = try await session.data(for: mutable)
                let http = response as? HTTPURLResponse
                if let http, !(200...299).contains(http.statusCode) {
                    lastError = httpFailure(
                        status: http.statusCode,
                        body: String(data: data.prefix(2000), encoding: .utf8) ?? "")
                    if http.statusCode == 404 || http.statusCode == 400 || http.statusCode == 422 {
                        continue
                    }
                    throw lastError!
                }
                return (data, http)
            }

            if includeTools, let error = lastError,
               Self.looksLikeToolRejection(error) {
                includeTools = false
                continue
            }
            throw lastError ?? LLMError.badResponse("No endpoint reachable")
        }
    }

    /// Heuristic: does this 400/422-style failure complain about the tools
    /// themselves? V3.6: the match is now STRICT — the message must BOTH
    /// reference tools/function-calling AND read as a complaint. The old
    /// broad markers ("parameters", "schema", "invalid request",
    /// "invalid_request_error") matched completely unrelated 400s (bad
    /// model ids, message-shape errors…) and silently stripped the agent's
    /// tools on every such request — the "agent acts like a plain chatbot"
    /// bug.
    static func looksLikeToolRejection(_ error: Error) -> Bool {
        guard let llmError = error as? LLMError,
              case .badResponse(let detail) = llmError else { return false }
        let lowered = detail.lowercased()

        // The failure must explicitly be about tools or function calling.
        let toolMarkers = ["tool", "function call", "function calling", "functions"]
        guard toolMarkers.contains(where: { lowered.contains($0) }) else {
            return false
        }

        // …and it must read as a rejection of them.
        let rejectionMarkers = [
            "not support", "unsupported", "does not support", "disabled",
            "invalid", "unknown field", "unexpected", "no longer",
            "required", "must", "cannot", "not found", "malformed",
            "missing", "error", "failed",
        ]
        return rejectionMarkers.contains { lowered.contains($0) }
    }

    // MARK: - Request building

    private func resolveConfig() throws -> ProviderConfig {
        guard let config = configProvider() else { throw LLMError.noActiveProvider }
        return config
    }

    /// Bedrock credentials parsed from the stored API key + base URL.
    private struct BedrockCredentials {
        let access: String
        let secret: String
        let region: String
    }

    private static func bedrockCredentials(config: ProviderConfig, apiKey: String?) throws -> BedrockCredentials {
        guard let apiKey, !apiKey.isEmpty,
              let parsed = BedrockClient.parseCredentials(apiKey) else {
            throw LLMError.badResponse("Bedrock API key must be ACCESS_KEY_ID:SECRET_ACCESS_KEY")
        }
        guard let region = BedrockClient.region(fromBase: config.baseURL) else {
            throw LLMError.badResponse("Use a bedrock-runtime.<region>.amazonaws.com base URL")
        }
        return BedrockCredentials(access: parsed.access, secret: parsed.secret, region: region)
    }

    /// Builds a ready-to-use Bedrock client from the provider config.
    static func bedrockClient(config: ProviderConfig, apiKey: String?) throws -> BedrockClient {
        let credentials = try bedrockCredentials(config: config, apiKey: apiKey)
        guard !config.mainModel.isEmpty else {
            throw LLMError.badResponse("Select a Bedrock model first")
        }
        return BedrockClient(
            region: credentials.region,
            modelID: config.mainModel,
            accessKey: credentials.access,
            secretKey: credentials.secret,
            temperature: config.temperature,
            maxTokens: config.maxTokens)
    }

    /// Builds the chat request candidates for the active provider. For
    /// OpenAI-compatible providers this returns every plausible endpoint so
    /// the caller can probe; custom protocols yield their single mapped URL.
    /// AWS Bedrock hosts configured through the OpenAI-compatible protocol
    /// are signed with SigV4 against `/openai/v1/chat/completions`.
    static func makeChatRequests(
        config: ProviderConfig,
        apiKey: String?,
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?,
        stream: Bool
    ) throws -> [URLRequest] {
        var body: [String: Any] = [
            "messages": Self.orderedMessages(Self.sanitizedForWire(messages))
                .map { encodeMessage($0) },
            "stream": stream,
            "temperature": config.temperature,
        ]

        // The caller's model override wins; fall back to the provider's
        // main model; omit the key entirely when nothing is configured.
        let resolvedModel = model.flatMap { $0.isEmpty ? nil : $0 } ?? config.mainModel
        if !resolvedModel.isEmpty {
            body["model"] = resolvedModel
        }
        if let maxTokens = config.maxTokens, maxTokens > 0 {
            body["max_tokens"] = maxTokens
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { encodeTool($0) }
            // V4.0: explicit auto-selection — several providers (Groq,
            // some OpenRouter models) behave more reliably with it set.
            body["tool_choice"] = "auto"
        }
        if config.protocolKind == .custom {
            for (key, value) in config.custom.extraBody {
                body[key] = encodeJSONValue(value)
            }
        }

        switch config.protocolKind {
        case .openAICompatible:
            // AWS Bedrock OpenAI-compatible layer: SigV4-signed request
            // against /openai/v1 — the plain candidates 404 on these hosts.
            if let region = EndpointResolver.bedrockRegion(from: config.baseURL) {
                let credentials = try bedrockCredentials(config: config, apiKey: apiKey)
                let endpoint = EndpointResolver.bedrockOpenAIChatEndpoint(region: region)
                let payload = try Self.jsonBody(body)
                guard var request = BedrockClient.signedOpenAIRequest(
                    region: region,
                    accessKey: credentials.access,
                    secretKey: credentials.secret,
                    url: endpoint,
                    method: "POST",
                    payload: payload) else {
                    throw LLMError.invalidURL(endpoint)
                }
                request.timeoutInterval = min(max(config.timeout, 5), 600)
                return [request]
            }
            return try EndpointResolver.chatEndpointCandidates(config.baseURL)
                .map { endpoint in
                    try makeRequest(
                        config: config,
                        apiKey: apiKey,
                        endpoint: endpoint,
                        method: "POST",
                        body: body,
                        sendKey: true)
                }
        case .custom:
            let request = try makeRequest(
                config: config,
                apiKey: apiKey,
                endpoint: customEndpoint(config: config, path: config.custom.chatPath),
                method: config.custom.method.uppercased() == "GET" ? "GET" : "POST",
                body: body,
                sendKey: true)
            return [request]
        case .bedrock:
            // Bedrock requests are built and signed by BedrockClient.
            throw LLMError.badResponse("Bedrock requests are routed through BedrockClient")
        }
    }

    /// Converts a native-shape message history into the text-protocol wire
    /// form: assistant tool_calls become marker lines, tool results become
    /// TOOL_RESULT user messages, and the protocol instructions ride along
    /// in a trailing system message. This keeps the universal text tool
    /// protocol completely transparent to the agent loop above — the
    /// session keeps working with native-shape ChatMessage values.
    static func textModeWireMessages(
        _ messages: [ChatMessage],
        tools: [ToolSpec]?
    ) -> [ChatMessage] {
        guard let tools, !tools.isEmpty else { return messages }
        var output: [ChatMessage] = []

        for message in Self.orderedMessages(Self.sanitizedForWire(messages)) {
            switch message.role {
            case .system, .user:
                output.append(message)
            case .assistant:
                if let calls = message.toolCalls, !calls.isEmpty {
                    var content = message.content
                    if !content.isEmpty { content += "\n" }
                    content += calls.map(Self.renderTextCall).joined(separator: "\n")
                    output.append(ChatMessage(
                        role: .assistant,
                        content: content,
                        createdAt: message.createdAt))
                } else if !message.content.isEmpty {
                    output.append(message)
                }
            case .tool:
                let name = message.name ?? "tool"
                output.append(ChatMessage.user(
                    TextToolProtocol.resultMessage(name: name, content: message.content)))
            }
        }

        output.append(ChatMessage.system(TextToolProtocol.prompt(for: tools)))
        return output
    }

    /// Renders one tool call back into its marker-line wire form.
    static func renderTextCall(_ call: ToolCall) -> String {
        let argumentsLiteral: String
        if let data = call.arguments.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
           let compact = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let text = String(data: compact, encoding: .utf8) {
            argumentsLiteral = text
        } else {
            // Fall back to the string form — always valid JSON.
            argumentsLiteral = Self.jsonQuoted(call.arguments)
        }
        return "\(TextToolProtocol.marker) {\"name\": \(Self.jsonQuoted(call.name)), \"arguments\": \(argumentsLiteral)}"
    }

    /// JSON-escapes a string (via a single-element array to reuse the
    /// Foundation escaper).
    private static func jsonQuoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              let arrayText = String(data: data, encoding: .utf8),
              arrayText.hasPrefix("["), arrayText.hasSuffix("]") else {
            return "\"\""
        }
        return String(arrayText.dropFirst().dropLast())
    }

    /// Serializes a request body dictionary, throwing on invalid JSON.
    private static func jsonBody(_ body: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw LLMError.badResponse("Invalid request body")
        }
        do {
            return try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw LLMError.badResponse("Request body encoding failed")
        }
    }

    /// Reorders a message list so every system message precedes everything
    /// else (relative order preserved). Strict providers such as xAI Grok
    /// reject system messages that appear mid-conversation.
    static func orderedMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        let system = messages.filter { $0.role == .system }
        guard !system.isEmpty else { return messages }
        let rest = messages.filter { $0.role != .system }
        return system + rest
    }

    /// Sanitizes a message window for the wire so strict providers never
    /// see broken tool structure:
    /// - a `tool` message survives only when its parent assistant message
    ///   (with the matching tool call id) is also in the window;
    /// - assistant tool_calls whose results were cut off by the window are
    ///   stripped (the text content survives);
    /// - duplicate tool responses for the same call id are dropped (first
    ///   response wins);
    /// - the window never starts with a `tool` message.
    ///
    /// This runs on every request path before encoding, so a history that
    /// was truncated by `suffix(24)` or interrupted mid-tool-loop can never
    /// produce a 400 "invalid message structure" from the provider.
    static func sanitizedForWire(_ messages: [ChatMessage]) -> [ChatMessage] {
        // Call ids defined by assistant tool_calls inside the window.
        var defined = Set<String>()
        for message in messages where message.role == .assistant {
            for call in message.toolCalls ?? [] where !call.id.isEmpty {
                defined.insert(call.id)
            }
        }

        // Call ids that are defined AND answered by a tool message in the
        // window (orphan tool messages whose parent was cut off can never
        // enter this set).
        var answered = Set<String>()
        for message in messages where message.role == .tool {
            guard let id = message.toolCallId, !id.isEmpty,
                  defined.contains(id), !answered.contains(id) else {
                continue
            }
            answered.insert(id)
        }

        var result: [ChatMessage] = []
        for message in messages {
            switch message.role {
            case .system, .user:
                result.append(message)
            case .assistant:
                guard let calls = message.toolCalls, !calls.isEmpty else {
                    if !message.content.isEmpty {
                        result.append(message)
                    }
                    continue
                }
                let supported = calls.filter { answered.contains($0.id) }
                if supported.count == calls.count {
                    result.append(message)
                } else if supported.isEmpty {
                    // Every call lost its result: keep the text as a plain
                    // assistant message, drop the calls.
                    if !message.content.isEmpty {
                        result.append(ChatMessage(
                            role: .assistant,
                            content: message.content,
                            createdAt: message.createdAt))
                    }
                } else {
                    // Some calls still have results: trim to the answered
                    // subset so the wire stays consistent.
                    var trimmed = message
                    trimmed.toolCalls = supported
                    result.append(trimmed)
                }
            case .tool:
                // Tool messages are filtered in the second pass below,
                // where duplicate detection happens.
                result.append(message)
            }
        }

        // Second pass: drop tool messages whose call was stripped and
        // tool messages that duplicate an earlier response for the same
        // call id, then drop any leading tool messages left over.
        var seenToolResponses = Set<String>()
        var cleaned: [ChatMessage] = []
        for message in result {
            guard message.role == .tool else {
                cleaned.append(message)
                continue
            }
            guard let id = message.toolCallId, answered.contains(id),
                  !seenToolResponses.contains(id) else {
                continue
            }
            seenToolResponses.insert(id)
            cleaned.append(message)
        }
        while cleaned.first?.role == .tool {
            cleaned.removeFirst()
        }
        return cleaned
    }

    /// Joins a normalized base URL with a custom protocol path.
    private static func customEndpoint(config: ProviderConfig, path: String) -> String {
        guard let base = EndpointResolver.normalizeBaseURL(config.baseURL) else {
            return config.baseURL
        }
        var normalizedPath = path.hasPrefix("/") ? path : "/" + path
        if normalizedPath.isEmpty { normalizedPath = "/" }
        return base + normalizedPath
    }

    /// Generic request builder for a full endpoint URL: headers, auth, body.
    private static func makeRequest(
        config: ProviderConfig,
        apiKey: String?,
        endpoint: String,
        method: String,
        body: [String: Any]?,
        sendKey: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(max(config.timeout, 5), 600)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if sendKey, let key = apiKey, !key.isEmpty {
            applyAuth(to: &request, config: config, key: key)
        }

        if config.protocolKind == .custom {
            for (name, value) in config.custom.extraHeaders where !name.isEmpty {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        if let body, method.uppercased() != "GET" {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw LLMError.badResponse("Invalid request body")
            }
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            } catch {
                throw LLMError.badResponse("Request body encoding failed")
            }
        }
        return request
    }

    /// Applies the provider's authentication header.
    private static func applyAuth(
        to request: inout URLRequest,
        config: ProviderConfig,
        key: String
    ) {
        switch config.protocolKind {
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .custom:
            switch config.custom.authStyle {
            case .bearer:
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            case .customHeader:
                let name = config.custom.authHeaderName.isEmpty
                    ? "Authorization"
                    : config.custom.authHeaderName
                let format = config.custom.authValueFormat.isEmpty
                    ? "%@"
                    : config.custom.authValueFormat
                request.setValue(String(format: format, key), forHTTPHeaderField: name)
            case .none:
                break
            }
        case .bedrock:
            // SigV4 signs the request itself; no static auth header.
            break
        }
    }

    // MARK: - Payload encoding

    /// Encodes one message for the wire. User messages carrying images are
    /// encoded in the OpenAI vision content format (text part + image_url
    /// parts with data URIs); the text part (and the plain content path)
    /// uses `wireContent` so attached files reach the model. Assistant
    /// messages that only carry tool calls use JSON null content — strict
    /// providers (xAI Grok) reject "".
    static func encodeMessage(_ message: ChatMessage) -> [String: Any] {
        switch message.role {
        case .system, .user:
            if message.role == .user, let images = message.images, !images.isEmpty {
                var parts: [[String: Any]] = []
                if !message.wireContent.isEmpty {
                    parts.append(["type": "text", "text": message.wireContent])
                }
                for image in images {
                    if let uri = MediaStore.dataURI(image) {
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": uri] as [String: Any],
                        ])
                    }
                }
                if parts.isEmpty {
                    parts.append(["type": "text", "text": message.wireContent])
                }
                return [
                    "role": "user",
                    "content": parts,
                ]
            }
            return [
                "role": message.role.rawValue,
                "content": message.wireContent,
            ]
        case .assistant:
            var dictionary: [String: Any] = [
                "role": "assistant",
                "content": message.content.isEmpty ? NSNull() : message.content,
            ]
            if let calls = message.toolCalls, !calls.isEmpty {
                dictionary["tool_calls"] = calls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.arguments,
                        ] as [String: Any],
                    ] as [String: Any]
                }
            }
            return dictionary
        case .tool:
            return [
                "role": "tool",
                "tool_call_id": message.toolCallId ?? "",
                "content": message.content,
            ]
        }
    }

    /// Encodes a tool spec. Strict providers (xAI in particular) require a
    /// `parameters` object on every function — inject an empty-but-valid
    /// schema when the tool did not define one.
    static func encodeTool(_ tool: ToolSpec) -> [String: Any] {
        var function: [String: Any] = [
            "name": tool.function.name,
            "description": tool.function.description,
        ]
        if let parameters = tool.function.parameters {
            function["parameters"] = encodeJSONValue(parameters)
        } else {
            function["parameters"] = [
                "type": "object",
                "properties": [String: Any](),
            ] as [String: Any]
        }
        return [
            "type": tool.type,
            "function": function,
        ]
    }

    private static func encodeJSONValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        case .object(let object):
            var output: [String: Any] = [:]
            for (key, inner) in object {
                output[key] = encodeJSONValue(inner)
            }
            return output
        case .array(let array):
            return array.map { encodeJSONValue($0) }
        }
    }

    // MARK: - Response parsing (non-streaming)

    private static func extractCompletionText(config: ProviderConfig, data: Data) throws -> String {
        let text: String?
        switch config.protocolKind {
        case .openAICompatible:
            text = openAICompletionText(data: data)
        case .custom:
            text = customCompletionText(data: data, custom: config.custom)
        case .bedrock:
            text = bedrockCompletionText(data: data)
        }
        guard let value = text, !value.isEmpty else {
            throw LLMError.badResponse("Empty completion")
        }
        return value
    }

    /// Defensive parser for a non-streamed Converse response (the streaming
    /// path normally handles Bedrock; this covers test/direct calls).
    private static func bedrockCompletionText(data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let output = body["output"] as? [String: Any],
              let message = output["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    private static func openAICompletionText(data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        if let content = DotPath.extract(from: body, path: "choices.0.message.content")
            .flatMap(DotPath.stringValue) {
            return content
        }
        return DotPath.extract(from: body, path: "choices.0.text")
            .flatMap(DotPath.stringValue)
    }

    private static func customCompletionText(data: Data, custom: CustomProtocolConfig) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        return DotPath.extract(from: body, path: custom.fullTextPath)
            .flatMap(DotPath.stringValue)
    }

    // MARK: - Stream execution

    /// Accumulated fragments of one streamed tool call.
    private struct ToolCallPart {
        var id: String?
        var name: String?
        var arguments: String = ""
    }

    private static func runStream(
        config: ProviderConfig,
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        tools: [ToolSpec]?
    ) async throws {
        // Text-marker interception is active whenever tools were requested:
        // in text-protocol mode it IS the tool channel; in native mode it
        // catches models that emit marker lines instead of tool_calls.
        let interceptTextCalls = !(tools ?? []).isEmpty
        switch config.protocolKind {
        case .openAICompatible, .bedrock:
            // Bedrock never reaches here (routed through BedrockClient),
            // but its SSE-free stream shape is OpenAI-compatible were it
            // ever proxied through an OpenAI-compatible gateway.
            try await streamOpenAI(
                bytes: bytes,
                continuation: continuation,
                interceptTextCalls: interceptTextCalls)
        case .custom:
            switch config.custom.streamFormat {
            case .sse:
                try await streamCustomSSE(
                    custom: config.custom,
                    bytes: bytes,
                    continuation: continuation,
                    interceptTextCalls: interceptTextCalls)
            case .ndjson:
                try await streamCustomNDJSON(
                    custom: config.custom,
                    bytes: bytes,
                    continuation: continuation,
                    interceptTextCalls: interceptTextCalls)
            case .none:
                try await streamCustomSingle(
                    custom: config.custom,
                    bytes: bytes,
                    continuation: continuation,
                    interceptTextCalls: interceptTextCalls)
            }
        }
    }

    /// OpenAI-compatible SSE stream: text deltas, incremental tool calls,
    /// finish reason and the [DONE] sentinel. Also tolerates providers
    /// that ignore the stream flag and return a full "message" shape.
    ///
    /// V4.0: when `interceptTextCalls` is set, marker-line tool calls
    /// (ASTRAL_TOOL / Hermes format) emitted as TEXT are filtered out of
    /// the visible stream and re-emitted as real `.toolCalls` — the
    /// universal protocol that keeps tools working with any model.
    private static func streamOpenAI(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        interceptTextCalls: Bool
    ) async throws {
        var parser = SSEParser()
        var toolParts: [Int: ToolCallPart] = [:]
        var finishReason: String?
        var done = false
        var rawText = ""
        var filter = TextToolProtocol.StreamFilter()

        func handlePayload(_ payload: String) {
            if payload == "[DONE]" {
                done = true
                return
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: data, options: [])
                      as? [String: Any] else { return }
            guard let choices = chunk["choices"] as? [[String: Any]],
                  let choice = choices.first else { return }

            // Streaming chunks carry "delta"; non-streamed fallback carries
            // the full "message". Prefer delta when both are present.
            let delta = (choice["delta"] as? [String: Any])
                ?? (choice["message"] as? [String: Any])
                ?? [:]

            // Reasoning models (deepseek-r1 style) stream their chain of
            // thought under "reasoning_content". It is deliberately NOT
            // treated as content — only "content" reaches the user.

            if let content = delta["content"] as? String, !content.isEmpty {
                if interceptTextCalls {
                    rawText += content
                    let safe = filter.feed(content)
                    if !safe.isEmpty {
                        continuation.yield(.textDelta(safe))
                    }
                } else {
                    continuation.yield(.textDelta(content))
                }
            }

            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    accumulateToolCallDelta(call, into: &toolParts)
                }
            }

            if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
                finishReason = reason
            }
        }

        for try await line in ByteLineReader.lines(bytes) {
            if Task.isCancelled || done { break }
            for payload in parser.feed(line + "\n") {
                handlePayload(payload)
            }
        }
        if !done {
            for payload in parser.flush() {
                handlePayload(payload)
            }
        }

        emitToolCalls(toolParts, continuation: continuation)
        if interceptTextCalls {
            let tail = filter.flush()
            if !tail.isEmpty {
                continuation.yield(.textDelta(tail))
            }
            // Marker-line calls only when the provider delivered no native
            // tool_calls (avoiding duplicates).
            if toolParts.isEmpty {
                let textCalls = TextToolProtocol.parseCalls(in: rawText)
                let calls = textCalls.enumerated().map { index, call in
                    ToolCall(
                        id: "text_\(index)_\(UUID().uuidString.prefix(8))",
                        name: call.name,
                        arguments: call.argumentsJSON)
                }
                if !calls.isEmpty {
                    continuation.yield(.toolCalls(calls))
                }
            }
        }
        continuation.yield(.finished(finishReason: finishReason))
    }

    /// Accumulates one streamed `delta.tool_calls` entry into `parts`
    /// (shared by the OpenAI and custom-SSE stream parsers).
    private static func accumulateToolCallDelta(
        _ call: [String: Any],
        into toolParts: inout [Int: ToolCallPart]
    ) {
        let index = (call["index"] as? NSNumber)?.intValue ?? toolParts.count
        var part = toolParts[index] ?? ToolCallPart()
        if let id = call["id"] as? String, part.id == nil {
            part.id = id
        }
        if let function = call["function"] as? [String: Any] {
            if let name = function["name"] as? String, part.name == nil {
                part.name = name
            }
            if let arguments = function["arguments"] as? String {
                part.arguments += arguments
            }
        }
        toolParts[index] = part
    }

    /// Custom protocol over SSE: each "data:" payload is a JSON chunk whose
    /// text fragment and finish reason are located via dot-paths.
    ///
    /// V4.0: two additions — (1) OpenAI-shaped `delta.tool_calls` entries
    /// inside the chunks are accumulated (many custom gateways pass them
    /// through even though the dot-paths ignore them), and (2) text-marker
    /// tool calls are intercepted, which is the primary tool channel when
    /// the provider cannot carry native tool calls at all.
    private static func streamCustomSSE(
        custom: CustomProtocolConfig,
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        interceptTextCalls: Bool
    ) async throws {
        var parser = SSEParser()
        var finishReason: String?
        var rawText = ""
        var filter = TextToolProtocol.StreamFilter()
        var toolParts: [Int: ToolCallPart] = [:]
        var completeCalls: [ToolCall] = []

        func handlePayload(_ payload: String) {
            if payload == "[DONE]" { return }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return
            }
            if let text = DotPath.extract(from: chunk, path: custom.streamTextPath) as? String,
               !text.isEmpty {
                if interceptTextCalls {
                    rawText += text
                    let safe = filter.feed(text)
                    if !safe.isEmpty {
                        continuation.yield(.textDelta(safe))
                    }
                } else {
                    continuation.yield(.textDelta(text))
                }
            }
            // OpenAI-shaped tool-call deltas riding inside custom chunks.
            if let dictionary = chunk as? [String: Any],
               let choices = dictionary["choices"] as? [[String: Any]],
               let choice = choices.first {
                let delta = (choice["delta"] as? [String: Any])
                    ?? (choice["message"] as? [String: Any])
                    ?? [:]
                if let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        accumulateToolCallDelta(call, into: &toolParts)
                    }
                }
            }
            // Complete tool calls located through the configured dot-path.
            if !custom.toolCallsPath.isEmpty {
                let rawCalls = DotPath.extractArray(from: chunk, path: custom.toolCallsPath)
                for call in parseToolCalls(rawCalls) where !completeCalls.contains(where: { $0.id == call.id }) {
                    completeCalls.append(call)
                }
            }
            if let reason = DotPath.extract(from: chunk, path: custom.finishPath)
                .flatMap(DotPath.stringValue) {
                finishReason = reason
            }
        }

        for try await line in ByteLineReader.lines(bytes) {
            if Task.isCancelled { break }
            for payload in parser.feed(line + "\n") {
                handlePayload(payload)
            }
        }
        for payload in parser.flush() {
            handlePayload(payload)
        }

        emitToolCalls(toolParts, continuation: continuation)
        if !completeCalls.isEmpty {
            continuation.yield(.toolCalls(completeCalls))
        }
        if interceptTextCalls {
            let tail = filter.flush()
            if !tail.isEmpty {
                continuation.yield(.textDelta(tail))
            }
            if toolParts.isEmpty, completeCalls.isEmpty {
                let textCalls = TextToolProtocol.parseCalls(in: rawText)
                let calls = textCalls.enumerated().map { index, call in
                    ToolCall(
                        id: "text_\(index)_\(UUID().uuidString.prefix(8))",
                        name: call.name,
                        arguments: call.argumentsJSON)
                }
                if !calls.isEmpty {
                    continuation.yield(.toolCalls(calls))
                }
            }
        }
        continuation.yield(.finished(finishReason: finishReason))
    }

    /// Custom protocol over NDJSON: every line is a standalone JSON chunk.
    private static func streamCustomNDJSON(
        custom: CustomProtocolConfig,
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        interceptTextCalls: Bool
    ) async throws {
        var finishReason: String?
        var rawText = ""
        var filter = TextToolProtocol.StreamFilter()
        var completeCalls: [ToolCall] = []

        for try await line in ByteLineReader.lines(bytes) {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: data, options: []) else {
                continue
            }
            if let text = DotPath.extract(from: chunk, path: custom.streamTextPath) as? String,
               !text.isEmpty {
                if interceptTextCalls {
                    rawText += text
                    let safe = filter.feed(text)
                    if !safe.isEmpty {
                        continuation.yield(.textDelta(safe))
                    }
                } else {
                    continuation.yield(.textDelta(text))
                }
            }
            if !custom.toolCallsPath.isEmpty {
                let rawCalls = DotPath.extractArray(from: chunk, path: custom.toolCallsPath)
                for call in parseToolCalls(rawCalls) where !completeCalls.contains(where: { $0.id == call.id }) {
                    completeCalls.append(call)
                }
            }
            if let reason = DotPath.extract(from: chunk, path: custom.finishPath)
                .flatMap(DotPath.stringValue) {
                finishReason = reason
            }
        }

        if !completeCalls.isEmpty {
            continuation.yield(.toolCalls(completeCalls))
        }
        if interceptTextCalls {
            let tail = filter.flush()
            if !tail.isEmpty {
                continuation.yield(.textDelta(tail))
            }
            if completeCalls.isEmpty {
                let textCalls = TextToolProtocol.parseCalls(in: rawText)
                let calls = textCalls.enumerated().map { index, call in
                    ToolCall(
                        id: "text_\(index)_\(UUID().uuidString.prefix(8))",
                        name: call.name,
                        arguments: call.argumentsJSON)
                }
                if !calls.isEmpty {
                    continuation.yield(.toolCalls(calls))
                }
            }
        }
        continuation.yield(.finished(finishReason: finishReason))
    }

    /// Custom protocol with no streaming: the whole response body is one
    /// JSON document; a single text delta (plus any tool calls) is emitted.
    private static func streamCustomSingle(
        custom: CustomProtocolConfig,
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        interceptTextCalls: Bool
    ) async throws {
        var bodyText = ""
        for try await line in ByteLineReader.lines(bytes) {
            if Task.isCancelled { break }
            bodyText += line
            bodyText += "\n"
            if bodyText.count > 4_000_000 { break }
        }

        guard let data = bodyText.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data, options: []) else {
            continuation.yield(.finished(finishReason: nil))
            return
        }

        var textCalls: [TextToolProtocol.Call] = []
        if let text = DotPath.extract(from: body, path: custom.fullTextPath) as? String,
           !text.isEmpty {
            if interceptTextCalls {
                textCalls = TextToolProtocol.parseCalls(in: text)
                let safe = TextToolProtocol.stripCalls(in: text)
                if !safe.isEmpty {
                    continuation.yield(.textDelta(safe))
                }
            } else {
                continuation.yield(.textDelta(text))
            }
        }

        let calls = parseToolCalls(
            DotPath.extractArray(from: body, path: custom.toolCallsPath))
        if !calls.isEmpty {
            continuation.yield(.toolCalls(calls))
        } else if interceptTextCalls, !textCalls.isEmpty {
            let parsed = textCalls.enumerated().map { index, call in
                ToolCall(
                    id: "text_\(index)_\(UUID().uuidString.prefix(8))",
                    name: call.name,
                    arguments: call.argumentsJSON)
            }
            continuation.yield(.toolCalls(parsed))
        }

        let finishReason = DotPath.extract(from: body, path: custom.finishPath)
            .flatMap(DotPath.stringValue)
        continuation.yield(.finished(finishReason: finishReason))
    }

    /// Emits the fully assembled tool calls sorted by their stream index.
    private static func emitToolCalls(
        _ parts: [Int: ToolCallPart],
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) {
        let calls: [ToolCall] = parts
            .sorted { $0.key < $1.key }
            .compactMap { index, part in
                guard let name = part.name, !name.isEmpty else { return nil }
                let id: String
                if let existing = part.id, !existing.isEmpty {
                    id = existing
                } else {
                    id = "call_\(index)"
                }
                let arguments = part.arguments.isEmpty ? "{}" : part.arguments
                return ToolCall(id: id, name: name, arguments: arguments)
            }
        if !calls.isEmpty {
            continuation.yield(.toolCalls(calls))
        }
    }

    /// Converts raw tool-call entries (OpenAI function shape) into ToolCall
    /// values. Arguments may arrive as a JSON string or a nested object.
    private static func parseToolCalls(_ raw: [Any]) -> [ToolCall] {
        raw.compactMap { entry in
            guard let dictionary = entry as? [String: Any] else { return nil }
            let function = dictionary["function"] as? [String: Any] ?? [:]
            guard let name = function["name"] as? String, !name.isEmpty else { return nil }

            let id: String
            if let existing = dictionary["id"] as? String, !existing.isEmpty {
                id = existing
            } else if let index = (dictionary["index"] as? NSNumber)?.intValue {
                id = "call_\(index)"
            } else {
                id = "call_\(UUID().uuidString.prefix(8))"
            }

            let arguments: String
            if let string = function["arguments"] as? String, !string.isEmpty {
                arguments = string
            } else if let object = function["arguments"] as? [String: Any],
                let data = try? JSONSerialization.data(withJSONObject: object, options: []),
                let text = String(data: data, encoding: .utf8) {
                arguments = text
            } else if let array = function["arguments"] as? [Any],
                let data = try? JSONSerialization.data(withJSONObject: array, options: []),
                let text = String(data: data, encoding: .utf8) {
                arguments = text
            } else {
                arguments = "{}"
            }
            return ToolCall(id: id, name: name, arguments: arguments)
        }
    }

    // MARK: - Error mapping

    private static func storedKey(for config: ProviderConfig) -> String? {
        try? KeychainStore.get(account: config.id.uuidString)
    }

    private static func httpFailure(status: Int, body: String) -> LLMError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited
        case 404:
            return .badResponse("Endpoint not found (404). Check the base URL — try it with and without /v1 at the end.")
        case 408:
            return .network("Request timed out (408). The provider may be slow or overloaded.")
        case 500...599:
            let detail = body.isEmpty ? "" : " — " + String(body.prefix(200))
            return .badResponse("Provider server error (HTTP \(status))\(detail)")
        default:
            let detail = body.isEmpty ? "HTTP \(status)" : body
            return .badResponse(detail)
        }
    }

    private static func mapError(_ error: Error) -> Error {
        if let llmError = error as? LLMError { return llmError }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return LLMError.cancelled }
            return LLMError.network(urlError.localizedDescription)
        }
        if error is CancellationError { return LLMError.cancelled }
        return error
    }
}
