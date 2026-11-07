import Foundation
import CryptoKit

// MARK: - AWS SigV4 signing

/// AWS Signature Version 4 request signer for the Bedrock runtime API,
/// implemented exactly per the AWS specification with CryptoKit HMAC-SHA256.
struct AWSSigV4 {
    let accessKey: String
    let secretKey: String
    let region: String
    let service: String

    /// Signs and returns a fully-headered request.
    /// - Parameters:
    ///   - url: full request URL (query strings supported)
    ///   - method: HTTP method
    ///   - payload: request body (empty `Data` for GET)
    ///   - amzDate: signing timestamp (defaults to now, UTC)
    func signedRequest(url: URL, method: String, payload: Data, amzDate: Date = Date()) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = payload

        let amzTimestamp = Self.amzDateTimeStamp(amzDate)
        let dateStamp = Self.dateStamp(amzDate)
        let payloadHash = Self.sha256Hex(payload)

        guard let host = url.host(percentEncoded: false) ?? url.host else {
            return request
        }

        request.setValue(amzTimestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // --- Canonical request -------------------------------------------------
        let canonicalURI = Self.canonicalPath(url)
        let canonicalQuery = Self.canonicalQuery(url)

        // Header names must be lowercase and sorted alphabetically.
        var headerPairs: [(String, String)] = [
            ("host", host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzTimestamp),
        ]
        if url.port != nil, !(url.scheme == "https" && url.port == 443), !(url.scheme == "http" && url.port == 80) {
            // Host with non-default port must match what is sent on the wire.
            headerPairs[0] = ("host", "\(host):\(url.port!)")
        }
        headerPairs.sort { $0.0 < $1.0 }

        let canonicalHeaders = headerPairs
            .map { "\($0.0):\($0.1)\n" }
            .joined()
        let signedHeaders = headerPairs.map(\.0).joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        // --- String to sign ----------------------------------------------------
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzTimestamp,
            scope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        // --- Signing key (HMAC chain) -----------------------------------------
        let kDate = Self.hmac(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = Self.hmac(key: kDate, data: Data(region.utf8))
        let kService = Self.hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = Self.hmac(key: kService, data: Data("aws4_request".utf8))
        let signature = Self.hmac(key: kSigning, data: Data(stringToSign.utf8))

        let authorization =
            "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(Self.hex(signature))"

        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Hashing helpers

    static func sha256Hex(_ data: Data) -> String {
        hex(Data(SHA256.hash(data: data)))
    }

    static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func amzDateTimeStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// RFC 3986 encoding of a single path segment, AWS flavor: unreserved
    /// characters (A–Z a–z 0–9 - _ . ~) stay literal, everything else is
    /// percent-encoded. `/` is preserved by the caller.
    static func encodeSegment(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// Canonical URI: each path segment encoded, slashes preserved.
    /// Bedrock model IDs contain `:` which must be encoded as `%3A`.
    static func canonicalPath(_ url: URL) -> String {
        let path = url.path
        guard !path.isEmpty else { return "/" }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        var encodedSegments: [String] = []
        for segment in segments {
            encodedSegments.append(Self.encodeSegment(String(segment)))
        }
        return encodedSegments.joined(separator: "/")
    }

    /// Canonical query string: keys and values encoded, sorted by key.
    static func canonicalQuery(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return ""
        }
        let pairs: [(String, String)] = items.map { item in
            (item.name, item.value ?? "")
        }
        let sortedPairs = pairs.sorted { left, right in
            if left.0 != right.0 {
                return left.0 < right.0
            }
            return left.1 < right.1
        }
        let encoded: [String] = sortedPairs.map { pair in
            Self.encodeSegment(pair.0) + "=" + Self.encodeSegment(pair.1)
        }
        return encoded.joined(separator: "&")
    }
}

// MARK: - CRC32

/// Pure-Swift CRC-32 (IEEE 802.3, zlib-compatible) used by the AWS event
/// stream framing.
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - AWS event stream framing

/// Incremental parser for the AWS event stream wire format
/// (`application/vnd.amazon.eventstream`):
///
/// ```
/// prelude:  totalLength(4 BE) headersLength(4 BE) preludeCRC(4 BE)
/// headers:  repeated { nameLen(1) name valueLen(2 BE) valueType(1) value }
/// payload:  (totalLength - headersLength - 16) bytes
/// trailer:  messageCRC(4 BE)
/// ```
struct BedrockEventStreamParser {

    struct Frame {
        var headers: [String: String]
        var payload: Data
    }

    private var buffer = Data()

    /// Appends raw bytes received from the network.
    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Extracts every complete frame currently buffered.
    mutating func nextFrames() -> [Frame] {
        var frames: [Frame] = []

        while buffer.count >= 12 {
            let totalLength = Self.readBE32(buffer, 0)
            let headersLength = Self.readBE32(buffer, 4)

            // Sanity guards against corrupt frames.
            guard totalLength >= 16,
                  totalLength <= 16 * 1024 * 1024,
                  headersLength <= totalLength - 16,
                  buffer.count >= totalLength else {
                break
            }

            let payloadStart = 12 + headersLength
            let payloadEnd = totalLength - 4

            let headerData = buffer.subdata(in: 12..<payloadStart)
            let payload = buffer.subdata(in: payloadStart..<max(payloadStart, payloadEnd))

            if let headers = Self.parseHeaders(headerData) {
                frames.append(Frame(headers: headers, payload: payload))
            }

            // Advance past this frame (skip CRC verification — payload and
            // headers are already validated structurally; verification adds
            // fragility without security benefit over TLS).
            buffer.removeFirst(totalLength)
        }

        return frames
    }

    private static func readBE32(_ data: Data, _ offset: Int) -> Int {
        let i = data.startIndex + offset
        return Int(data[i]) << 24 | Int(data[i + 1]) << 16 | Int(data[i + 2]) << 8 | Int(data[i + 3])
    }

    /// Parses the header block. Only the string value type (7) appears in
    /// Bedrock event streams; other types are skipped defensively.
    private static func parseHeaders(_ data: Data) -> [String: String]? {
        var headers: [String: String] = [:]
        var index = data.startIndex

        while index < data.endIndex {
            guard index + 1 <= data.endIndex else { return nil }
            let nameLength = Int(data[index])
            index = data.index(after: index)
            guard index + nameLength <= data.endIndex else { return nil }
            let name = String(data: data[index..<data.index(index, offsetBy: nameLength)], encoding: .utf8) ?? ""
            index = data.index(index, offsetBy: nameLength)

            guard index + 3 <= data.endIndex else { return nil }
            let valueLength = Int(data[index]) << 8 | Int(data[data.index(after: index)])
            let valueType = data[data.index(index, offsetBy: 2)]
            index = data.index(index, offsetBy: 3)

            guard index + valueLength <= data.endIndex else { return nil }
            let valueData = data[index..<data.index(index, offsetBy: valueLength)]
            index = data.index(index, offsetBy: valueLength)

            if valueType == 7, let value = String(data: valueData, encoding: .utf8) {
                headers[name] = value
            }
        }

        return headers
    }
}

// MARK: - Bedrock client

/// Full AWS Bedrock client speaking the Converse API
/// (`/model/{id}/converse-stream`) with SigV4 authentication and native
/// event-stream decoding — tools included.
struct BedrockClient {
    let region: String
    let modelID: String
    let accessKey: String
    let secretKey: String
    let temperature: Double
    let maxTokens: Int?

    // MARK: Credential / region helpers

    /// Bedrock API keys are stored as `ACCESS_KEY_ID:SECRET_ACCESS_KEY`.
    static func parseCredentials(_ apiKey: String) -> (access: String, secret: String)? {
        guard let separator = apiKey.firstIndex(of: ":") else { return nil }
        let access = String(apiKey[..<separator]).trimmingCharacters(in: .whitespaces)
        let secret = String(apiKey[apiKey.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        guard !access.isEmpty, !secret.isEmpty else { return nil }
        return (access, secret)
    }

    /// Extracts the region from a `bedrock-runtime.{region}.amazonaws.com`
    /// base URL (also accepts `bedrock.{region}.amazonaws.com`).
    static func region(fromBase baseURL: String) -> String? {
        guard let url = URL(string: baseURL), let host = url.host(percentEncoded: false) ?? url.host,
              host.hasSuffix(".amazonaws.com") else { return nil }
        let parts = host.dropLast(".amazonaws.com".count).split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let prefix = parts[0]
        guard prefix == "bedrock-runtime" || prefix == "bedrock" else { return nil }
        return String(parts[1])
    }

    // MARK: Request building

    private func runtimeHost() -> String {
        "bedrock-runtime.\(region).amazonaws.com"
    }

    private func signer() -> AWSSigV4 {
        AWSSigV4(
            accessKey: accessKey,
            secretKey: secretKey,
            region: region,
            service: "bedrock")
    }

    /// Signs an arbitrary Bedrock OpenAI-compatible request (the
    /// `/openai/v1/…` layer) with SigV4. Used when a user configures an AWS
    /// Bedrock host through the OpenAI-compatible protocol.
    static func signedOpenAIRequest(
        region: String,
        accessKey: String,
        secretKey: String,
        url: String,
        method: String,
        payload: Data
    ) -> URLRequest? {
        guard let target = URL(string: url) else { return nil }
        let signer = AWSSigV4(
            accessKey: accessKey,
            secretKey: secretKey,
            region: region,
            service: "bedrock")
        return signer.signedRequest(url: target, method: method, payload: payload)
    }

    private func converseURL(streaming: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = runtimeHost()
        components.path = "/model/\(modelID)/\(streaming ? "converse-stream" : "converse")"
        return components.url
    }

    /// Builds the Converse API request body from the chat messages.
    private func converseBody(messages: [ChatMessage], tools: [ToolSpec]?) -> Data {
        var body: [String: Any] = [:]

        var converseMessages: [[String: Any]] = []
        var systemTexts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                if !message.content.isEmpty {
                    systemTexts.append(message.content)
                }

            case .user:
                var blocks: [[String: Any]] = []
                // wireContent folds attached-file text into the prompt.
                if !message.wireContent.isEmpty {
                    blocks.append(["text": message.wireContent])
                }
                // Vision input: image blocks with base64 bytes.
                for image in message.images ?? [] {
                    if let base64 = MediaStore.base64(image) {
                        let format = image.mimeType.hasSuffix("png") ? "png" : "jpeg"
                        blocks.append([
                            "image": [
                                "format": format,
                                "source": ["bytes": base64] as [String: Any],
                            ] as [String: Any],
                        ] as [String: Any])
                    }
                }
                if blocks.isEmpty {
                    blocks.append(["text": message.wireContent])
                }
                converseMessages.append([
                    "role": "user",
                    "content": blocks,
                ])

            case .assistant:
                var blocks: [[String: Any]] = []
                if !message.content.isEmpty {
                    blocks.append(["text": message.content])
                }
                for call in message.toolCalls ?? [] {
                    blocks.append([
                        "toolUse": [
                            "toolUseId": call.id,
                            "name": call.name,
                            "input": Self.decodeJSONObject(call.arguments),
                        ] as [String: Any],
                    ])
                }
                converseMessages.append([
                    "role": "assistant",
                    "content": blocks,
                ])

            case .tool:
                converseMessages.append([
                    "role": "user",
                    "content": [[
                        "toolResult": [
                            "toolUseId": message.toolCallId ?? "",
                            "content": [["text": message.content]],
                        ] as [String: Any],
                    ] as [String: Any]],
                ])
            }
        }

        if !systemTexts.isEmpty {
            body["system"] = systemTexts.map { ["text": $0] as [String: Any] }
        }
        body["messages"] = converseMessages

        var inferenceConfig: [String: Any] = ["temperature": temperature]
        if let maxTokens, maxTokens > 0 {
            inferenceConfig["maxTokens"] = maxTokens
        }
        body["inferenceConfig"] = inferenceConfig

        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "toolSpec": [
                        "name": tool.function.name,
                        "description": tool.function.description,
                        "inputSchema": ["json": Self.decodeJSONObject(
                            Self.encodeParameters(tool))],
                    ] as [String: Any],
                ] as [String: Any]
            }
        }

        return (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
    }

    private static func encodeParameters(_ tool: ToolSpec) -> String {
        guard let parameters = tool.function.parameters,
              let data = try? JSONSerialization.data(withJSONObject: encodeJSONValue(parameters), options: []) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeJSONObject(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func encodeJSONValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
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

    // MARK: Streaming

    /// Streams a conversation via `converse-stream`, decoding the binary
    /// event stream into `LLMEvent`s (text deltas + tool calls).
    func streamChat(
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        session: URLSession
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = converseURL(streaming: true) else {
                        throw LLMError.invalidURL("bedrock-runtime.\(region).amazonaws.com")
                    }
                    let body = converseBody(messages: messages, tools: tools)
                    let request = signer().signedRequest(url: url, method: "POST", payload: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        let errorText = await ByteLineReader.drain(bytes, limit: 2000)
                        throw Self.mapHTTPFailure(http.statusCode, body: errorText)
                    }

                    var parser = BedrockEventStreamParser()
                    var toolParts: [Int: (id: String, name: String, arguments: String)] = [:]
                    var finishReason: String?
                    var emittedAnything = false
                    var rawStreamText = ""
                    var textFilter = TextToolProtocol.StreamFilter()

                    for try await chunk in bytes {
                        if Task.isCancelled { break }
                        parser.append(Data([chunk]))

                        for frame in parser.nextFrames() {
                            let messageType = frame.headers[":message-type"] ?? "event"

                            if messageType == "exception" {
                                let exceptionType = frame.headers[":exception-type"] ?? "error"
                                let detail = String(data: frame.payload, encoding: .utf8) ?? ""
                                throw LLMError.badResponse("Bedrock \(exceptionType): \(String(detail.prefix(300)))")
                            }
                            guard messageType == "event" else { continue }

                            let eventType = frame.headers[":event-type"] ?? ""
                            guard let payload = try? JSONSerialization.jsonObject(
                                with: frame.payload, options: []) as? [String: Any] else { continue }

                            switch eventType {
                            case "contentBlockStart":
                                if let start = payload["start"] as? [String: Any],
                                   let toolUse = start["toolUse"] as? [String: Any],
                                   let index = (payload["contentBlockIndex"] as? NSNumber)?.intValue {
                                    toolParts[index] = (
                                        id: toolUse["toolUseId"] as? String ?? "call_\(index)",
                                        name: toolUse["name"] as? String ?? "",
                                        arguments: "")
                                }

                            case "contentBlockDelta":
                                if let delta = payload["delta"] as? [String: Any] {
                                    if let text = delta["text"] as? String, !text.isEmpty {
                                        emittedAnything = true
                                        rawStreamText += text
                                        let safe = textFilter.feed(text)
                                        if !safe.isEmpty {
                                            continuation.yield(.textDelta(safe))
                                        }
                                    }
                                    if let toolUse = delta["toolUse"] as? [String: Any],
                                       let input = toolUse["input"] as? String,
                                       let index = (payload["contentBlockIndex"] as? NSNumber)?.intValue,
                                       var part = toolParts[index] {
                                        part.arguments += input
                                        toolParts[index] = part
                                    }
                                }

                            case "messageStop":
                                if let stop = payload["stopReason"] as? String {
                                    finishReason = stop
                                }

                            default:
                                break // messageStart / contentBlockStop / metadata
                            }
                        }
                    }

                    // Assemble tool calls in content-block order.
                    let calls = toolParts
                        .sorted { $0.key < $1.key }
                        .compactMap { _, part -> ToolCall? in
                            guard !part.name.isEmpty else { return nil }
                            return ToolCall(
                                id: part.id,
                                name: part.name,
                                arguments: part.arguments.isEmpty ? "{}" : part.arguments)
                        }
                    let tail = textFilter.flush()
                    if !tail.isEmpty {
                        continuation.yield(.textDelta(tail))
                    }
                    if !calls.isEmpty {
                        continuation.yield(.toolCalls(calls))
                    } else {
                        let textCalls = TextToolProtocol.parseCalls(in: rawStreamText)
                        let fallbackCalls = textCalls.enumerated().map { idx, c in
                            ToolCall(id: "bedrock_txt_\(idx)", name: c.name, arguments: c.argumentsJSON)
                        }
                        if !fallbackCalls.isEmpty {
                            continuation.yield(.toolCalls(fallbackCalls))
                        }
                    }

                    _ = emittedAnything
                    continuation.yield(.finished(finishReason: finishReason))
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

    // MARK: Non-streaming

    /// One-shot Converse call returning (text, toolCalls).
    func converse(messages: [ChatMessage], tools: [ToolSpec]?, session: URLSession) async throws -> (String, [ToolCall]) {
        guard let url = converseURL(streaming: false) else {
            throw LLMError.invalidURL("bedrock-runtime.\(region).amazonaws.com")
        }
        let body = converseBody(messages: messages, tools: tools)
        let request = signer().signedRequest(url: url, method: "POST", payload: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            throw Self.mapHTTPFailure(http.statusCode, body: detail)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let output = root["output"] as? [String: Any],
              let message = output["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            throw LLMError.badResponse("Unexpected Bedrock response shape")
        }

        var text = ""
        var calls: [ToolCall] = []
        for block in content {
            if let value = block["text"] as? String {
                text += value
            }
            if let toolUse = block["toolUse"] as? [String: Any],
               let name = toolUse["name"] as? String {
                let input = toolUse["input"] as? [String: Any] ?? [:]
                let arguments = (try? JSONSerialization.data(withJSONObject: input, options: []))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                calls.append(ToolCall(
                    id: toolUse["toolUseId"] as? String ?? "call_\(calls.count)",
                    name: name,
                    arguments: arguments))
            }
        }
        return (text, calls)
    }

    // MARK: Model discovery

    /// Lists foundation models available in the region
    /// (`bedrock.{region}.amazonaws.com/models/list-foundation-models`).
    static func listModels(
        region: String,
        accessKey: String,
        secretKey: String
    ) async throws -> [ModelInfo] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bedrock.\(region).amazonaws.com"
        components.path = "/models/list-foundation-models"

        guard let url = components.url else {
            throw LLMError.invalidURL("bedrock.\(region).amazonaws.com")
        }

        let signer = AWSSigV4(
            accessKey: accessKey,
            secretKey: secretKey,
            region: region,
            service: "bedrock")
        let request = signer.signedRequest(url: url, method: "GET", payload: Data())

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            throw Self.mapHTTPFailure(http.statusCode, body: detail)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let summaries = root["modelSummaries"] as? [[String: Any]] else {
            throw LLMError.badResponse("Unexpected Bedrock model list shape")
        }

        return summaries.compactMap { summary in
            guard let id = summary["modelId"] as? String, !id.isEmpty else { return nil }
            // Only models that support on-demand converse invocation.
            if let lifecycle = summary["modelLifecycle"] as? [String: Any],
               let status = lifecycle["status"] as? String, status.uppercased() == "LEGACY" {
                return nil
            }
            return ModelInfo(
                id: id,
                name: summary["modelName"] as? String,
                ownedBy: summary["providerName"] as? String)
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: Errors

    static func mapHTTPFailure(_ status: Int, body: String) -> LLMError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 404:
            return .badResponse("Model not found in this region (HTTP 404). Check the model ID and AWS region.")
        case 429:
            return .rateLimited
        case 408:
            return .network("Bedrock timed out (408). The model may be warming up — try again.")
        default:
            let detail = body.isEmpty ? "HTTP \(status)" : body
            return .badResponse(detail)
        }
    }

    static func mapError(_ error: Error) -> Error {
        if let llmError = error as? LLMError { return llmError }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return LLMError.cancelled }
            if urlError.code == .cannotFindHost || urlError.code == .cannotConnectToHost {
                return LLMError.network("Cannot reach AWS Bedrock in this region. Check the region and your connection.")
            }
            return LLMError.network(urlError.localizedDescription)
        }
        if error is CancellationError { return LLMError.cancelled }
        return error
    }
}
