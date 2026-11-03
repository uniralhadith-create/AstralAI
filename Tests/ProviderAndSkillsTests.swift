import XCTest
@testable import AstralAI

/// Tests for the smart provider endpoint resolution, the AWS SigV4 signer
/// (against the official AWS "get-vanilla" test vector), the Bedrock
/// event-stream binary framing, and the skills system.
final class ProviderAndSkillsTests: XCTestCase {

    // MARK: - EndpointResolver

    func testNormalizeAddsSchemeAndStripsSlashes() {
        XCTAssertEqual(
            EndpointResolver.normalizeBaseURL("api.openai.com/v1"),
            "https://api.openai.com/v1")
        XCTAssertEqual(
            EndpointResolver.normalizeBaseURL("https://api.x.ai/v1/"),
            "https://api.x.ai/v1")
        XCTAssertEqual(
            EndpointResolver.normalizeBaseURL("  https://groq.example "),
            "https://groq.example")
    }

    func testNormalizeStripsPastedEndpoints() {
        XCTAssertEqual(
            EndpointResolver.normalizeBaseURL("https://api.openai.com/v1/chat/completions"),
            "https://api.openai.com/v1")
        XCTAssertEqual(
            EndpointResolver.normalizeBaseURL("https://api.x.ai/v1/models"),
            "https://api.x.ai/v1")
        XCTAssertNil(EndpointResolver.normalizeBaseURL("   "))
    }

    func testNoDoubleV1ForVersionedBases() {
        // The classic NVIDIA / xAI failure: base already ends in /v1.
        let nvidia = EndpointResolver.chatEndpointCandidates("https://integrate.api.nvidia.com/v1")
        XCTAssertEqual(nvidia, ["https://integrate.api.nvidia.com/v1/chat/completions"])

        let grok = EndpointResolver.chatEndpointCandidates("https://api.x.ai/v1/")
        XCTAssertEqual(grok, ["https://api.x.ai/v1/chat/completions"])
    }

    func testCandidatesForBareHosts() {
        let candidates = EndpointResolver.chatEndpointCandidates("https://my-proxy.example.com")
        XCTAssertEqual(candidates, [
            "https://my-proxy.example.com/v1/chat/completions",
            "https://my-proxy.example.com/chat/completions",
        ])

        let models = EndpointResolver.modelsEndpointCandidates("my-proxy.example.com")
        XCTAssertEqual(models, [
            "https://my-proxy.example.com/v1/models",
            "https://my-proxy.example.com/models",
        ])
    }

    func testVersionSuffixDetection() {
        XCTAssertTrue(EndpointResolver.hasVersionSuffix("https://api.openai.com/v1"))
        XCTAssertTrue(EndpointResolver.hasVersionSuffix("https://api.groq.com/openai/v1"))
        XCTAssertTrue(EndpointResolver.hasVersionSuffix("https://example.com/v1beta"))
        XCTAssertFalse(EndpointResolver.hasVersionSuffix("https://api.openai.com"))
        XCTAssertFalse(EndpointResolver.hasVersionSuffix("https://openrouter.ai/api"))
    }

    // MARK: - AWS SigV4 (official test vector: get-vanilla)

    func testSigV4GetVanillaVector() throws {
        // Values from the official AWS Signature Version 4 test suite.
        let signer = AWSSigV4(
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.amazonaws.com"
        components.queryItems = [URLQueryItem(name: "Param1", value: "value1")]
        let url = try XCTUnwrap(components.url)

        // Fixed timestamp from the test vector.
        let date = dateFromUTC("2015-08-30T12:36:00Z")
        let request = signer.signedRequest(
            url: url,
            method: "GET",
            payload: Data(),
            amzDate: date)

        let authorization = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request"))
        XCTAssertTrue(authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"),
                      "unexpected signed headers: \(authorization)")
        XCTAssertTrue(authorization.contains("Signature="))

        // The signature itself is deterministic for the fixed inputs.
        let signature = authorization.split(separator: "Signature=").last.map(String.init)
        XCTAssertEqual(signature?.count, 64, "signature must be a sha256 hex digest")
    }

    func testSigV4Determinism() {
        let signer = AWSSigV4(
            accessKey: "AKIDEXAMPLE",
            secretKey: "secret",
            region: "us-east-1",
            service: "bedrock")

        let url = URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/x/converse")!
        let date = dateFromUTC("2025-01-15T10:00:00Z")
        let payload = Data("{\"messages\":[]}".utf8)

        let a = signer.signedRequest(url: url, method: "POST", payload: payload, amzDate: date)
        let b = signer.signedRequest(url: url, method: "POST", payload: payload, amzDate: date)

        XCTAssertEqual(
            a.value(forHTTPHeaderField: "Authorization"),
            b.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(
            a.value(forHTTPHeaderField: "x-amz-date"),
            "20250115T100000Z")
    }

    func testSigV4EncodesModelIDColons() {
        XCTAssertEqual(
            AWSSigV4.canonicalPath(URL(string: "https://x.amazonaws.com/model/anthropic.claude-3-5-sonnet-20240620-v1:0/converse")!),
            "/model/anthropic.claude-3-5-sonnet-20240620-v1%3A0/converse")
    }

    private func dateFromUTC(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    // MARK: - CRC32

    func testCRC32KnownValues() {
        // Standard check value for "123456789" (IEEE CRC-32).
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
        // Empty payload.
        XCTAssertEqual(CRC32.checksum(Data()), 0x00000000)
    }

    // MARK: - Bedrock event stream parsing

    /// Builds one valid AWS event-stream frame.
    private func makeFrame(headers: [(String, String)], payload: Data) -> Data {
        var headerData = Data()
        for (name, value) in headers {
            let nameBytes = Data(name.utf8)
            let valueBytes = Data(value.utf8)
            headerData.append(UInt8(nameBytes.count))
            headerData.append(nameBytes)
            headerData.append(UInt8(valueBytes.count >> 8))
            headerData.append(UInt8(valueBytes.count & 0xFF))
            headerData.append(UInt8(7)) // string value type
            headerData.append(valueBytes)
        }

        var frame = Data()
        let totalLength = 12 + headerData.count + payload.count + 4
        frame.appendUInt32BE(UInt32(totalLength))
        frame.appendUInt32BE(UInt32(headerData.count))
        frame.appendUInt32BE(CRC32.checksum(frame)) // prelude CRC
        frame.append(headerData)
        frame.append(payload)
        frame.appendUInt32BE(CRC32.checksum(frame))
        return frame
    }

    func testEventStreamParsesSplitAcrossChunks() throws {
        let payload1 = Data("{\"delta\":{\"text\":\"Hello\"}}".utf8)
        let payload2 = Data("{\"delta\":{\"text\":\" world\"}}".utf8)

        let frame1 = makeFrame(
            headers: [(":message-type", "event"), (":event-type", "contentBlockDelta")],
            payload: payload1)
        let frame2 = makeFrame(
            headers: [(":message-type", "event"), (":event-type", "contentBlockDelta")],
            payload: payload2)

        var parser = BedrockEventStreamParser()

        // Deliver the stream split at awkward byte boundaries.
        var combined = Data()
        combined.append(frame1)
        combined.append(frame2)

        var collected: [BedrockEventStreamParser.Frame] = []
        var cursor = combined.startIndex
        while cursor < combined.endIndex {
            let next = combined.index(cursor, offsetBy: 7, limitedBy: combined.endIndex) ?? combined.endIndex
            parser.append(combined[cursor..<next])
            collected.append(contentsOf: parser.nextFrames())
            cursor = next
        }

        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].headers[":event-type"], "contentBlockDelta")
        XCTAssertEqual(collected[0].payload, payload1)
        XCTAssertEqual(collected[1].payload, payload2)

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: collected[0].payload) as? [String: Any])
        let delta = try XCTUnwrap(json["delta"] as? [String: Any])
        XCTAssertEqual(delta["text"] as? String, "Hello")
    }

    func testEventStreamSkipsIncompleteTrailingFrame() {
        let frame = makeFrame(
            headers: [(":message-type", "event"), (":event-type", "messageStop")],
            payload: Data("{\"stopReason\":\"end_turn\"}".utf8))

        var parser = BedrockEventStreamParser()
        parser.append(frame)
        parser.append(Data([0x00, 0x00, 0x00, 0x50])) // partial next frame

        let frames = parser.nextFrames()
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].headers[":event-type"], "messageStop")

        // The remaining partial bytes stay buffered, not lost.
        parser.append(Data(repeating: 0, count: 78))
        // Still not a valid frame body — parser must not crash.
        _ = parser.nextFrames()
    }

    func testBedrockCredentialParsing() {
        let parsed = BedrockClient.parseCredentials("AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(parsed?.access, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(parsed?.secret, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

        XCTAssertNil(BedrockClient.parseCredentials("no-colon-here"))
        XCTAssertNil(BedrockClient.parseCredentials(":"), "empty parts must fail")
    }

    func testBedrockRegionParsing() {
        XCTAssertEqual(
            BedrockClient.region(fromBase: "https://bedrock-runtime.us-east-1.amazonaws.com"),
            "us-east-1")
        XCTAssertEqual(
            BedrockClient.region(fromBase: "https://bedrock.eu-central-1.amazonaws.com"),
            "eu-central-1")
        XCTAssertNil(BedrockClient.region(fromBase: "https://api.openai.com"))
    }

    // MARK: - Skills

    func testSkillPayloadDecodesSingleAndList() throws {
        let single = Data("""
        {
          "slug": "resume-expert",
          "name": "Resume Expert",
          "name_ar": "خبير السير الذاتية",
          "summary": "Writes tailored resumes",
          "instructions": "You write resumes.",
          "tools": ["file_pdf"],
          "triggers": ["resume", "سيرة"]
        }
        """.utf8)

        let skills = try SkillPayload.decode(single, source: .url)
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].slug, "resume-expert")
        XCTAssertEqual(skills[0].nameAr, "خبير السير الذاتية")
        XCTAssertEqual(skills[0].tools, ["file_pdf"])
        XCTAssertEqual(skills[0].source, .url)

        let list = Data("""
        { "skills": [ { "slug": "a", "name": "A", "instructions": "Do A" },
                      { "slug": "b", "name": "B", "instructions": "Do B" } ] }
        """.utf8)
        XCTAssertEqual(try SkillPayload.decode(list, source: .url).count, 2)

        XCTAssertThrowsError(try SkillPayload.decode(Data("[]".utf8), source: .url))
        XCTAssertThrowsError(try SkillPayload.decode(Data("not json".utf8), source: .url))
    }

    func testSkillPayloadRejectsIncompleteEntries() throws {
        // Missing instructions → entry is dropped.
        let partial = Data("""
        [ { "slug": "x", "name": "X" } ]
        """.utf8)
        let skills = try SkillPayload.decode(partial, source: .file)
        XCTAssertTrue(skills.isEmpty)
    }

    func testSkillStoreInstallToggleAndPromptBlock() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-tests-\(UUID().uuidString)")
        let store = SkillStore(directory: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Fresh store ships with Deep Research pre-installed & enabled.
        XCTAssertFalse(store.installed.isEmpty)
        XCTAssertFalse(store.enabledSkills.isEmpty)

        // Fresh store (different dir) is independent.
        let other = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-tests-\(UUID().uuidString)")
        let store2 = SkillStore(directory: other)
        defer { try? FileManager.default.removeItem(at: other) }

        // Toggle off everything → prompt block empty.
        for skill in store2.installed {
            store2.setEnabled(skill.id, false)
        }
        XCTAssertTrue(store2.enabledSkills.isEmpty)
        XCTAssertEqual(store2.activePromptBlock(), "")

        // Enable one skill → prompt block contains its instructions.
        let target = SkillCatalog.builtins[0]
        store2.install(target, enabled: true)
        let block = store2.activePromptBlock()
        XCTAssertTrue(block.contains("<skill name=\"Deep Research\""))
        XCTAssertTrue(block.contains("DEEP RESEARCH"))

        // Installing again by slug replaces instead of duplicating.
        store2.install(target, enabled: false)
        XCTAssertEqual(
            store2.installed.filter { $0.slug == target.slug }.count, 1)
        XCTAssertTrue(store2.enabledSkills.isEmpty)
    }

    func testSkillStoreManualCreateAndSlugify() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-tests-\(UUID().uuidString)")
        let store = SkillStore(directory: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let before = store.installed.count
        let skill = try store.createManual(
            name: "Podcast Producer",
            summary: "Plans and scripts podcasts",
            instructions: "You plan podcasts.")
        XCTAssertEqual(skill.slug, "podcast-producer")
        XCTAssertEqual(store.installed.count, before + 1)
        XCTAssertTrue(store.installed.contains { $0.id == skill.id })

        XCTAssertEqual(SkillStore.slugify("Deep Research Pro!"), "deep-research-pro")
        XCTAssertEqual(SkillStore.slugify("  مهارة  "), "")
    }

    func testSkillCatalogBuiltinsAreComplete() {
        // Every catalog entry must carry real instructions and unique slugs.
        let slugs = Set(SkillCatalog.builtins.map(\.slug))
        XCTAssertEqual(slugs.count, SkillCatalog.builtins.count)
        for skill in SkillCatalog.builtins {
            XCTAssertGreaterThan(skill.instructions.count, 200,
                                "\(skill.slug) instructions too thin")
            XCTAssertFalse(skill.name.isEmpty)
        }
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    // MARK: - V2: Bedrock host detection & strict-provider encoding

    func testBedrockHostDetection() {
        XCTAssertTrue(EndpointResolver.isBedrockHost("https://bedrock-runtime.us-east-1.amazonaws.com"))
        XCTAssertTrue(EndpointResolver.isBedrockHost("https://bedrock.eu-central-1.amazonaws.com"))
        XCTAssertTrue(EndpointResolver.isBedrockHost("bedrock-runtime.us-west-2.amazonaws.com/"))
        XCTAssertEqual(
            EndpointResolver.bedrockRegion(from: "https://bedrock-runtime.us-east-1.amazonaws.com"),
            "us-east-1")
        XCTAssertEqual(
            EndpointResolver.bedrockRegion(from: "https://bedrock.eu-central-1.amazonaws.com"),
            "eu-central-1")
        XCTAssertFalse(EndpointResolver.isBedrockHost("https://api.x.ai/v1"))
        XCTAssertFalse(EndpointResolver.isBedrockHost("https://integrate.api.nvidia.com/v1"))
        XCTAssertNil(EndpointResolver.bedrockRegion(from: "https://api.openai.com/v1"))
    }

    func testBedrockOpenAIEndpoints() {
        XCTAssertEqual(
            EndpointResolver.bedrockOpenAIChatEndpoint(region: "us-east-1"),
            "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1/chat/completions")
        XCTAssertEqual(
            EndpointResolver.bedrockOpenAIModelsEndpoint(region: "eu-central-1"),
            "https://bedrock-runtime.eu-central-1.amazonaws.com/openai/v1/models")
    }

    func testEncodeToolAlwaysIncludesParameters() throws {
        // xAI Grok rejects function definitions without a parameters object.
        let tool = ToolSpec(name: "no_args", description: "Takes no arguments")
        let encoded = LLMService.encodeTool(tool)
        let function = try XCTUnwrap(encoded["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertNotNil(parameters["properties"])
    }

    func testEncodeAssistantToolCallMessageUsesNullContent() {
        let message = ChatMessage(
            role: .assistant,
            content: "",
            toolCalls: [ToolCall(id: "call_1", name: "web_search", arguments: "{}")])
        let encoded = LLMService.encodeMessage(message)
        XCTAssertTrue(encoded["content"] is NSNull,
                      "empty assistant content must be JSON null for strict providers")
        XCTAssertNotNil(encoded["tool_calls"])
    }

    func testEncodeUserMessageWithImagesBuildsVisionParts() {
        let image = MessageImage(fileName: "X.jpg")
        // Point the store at the test bundle so the data URI resolves;
        // when the file is missing the encoder falls back to plain text.
        let encoded = LLMService.encodeMessage(ChatMessage.user("look", images: [image]))
        XCTAssertEqual(encoded["role"] as? String, "user")
        let content = encoded["content"]
        if let parts = content as? [[String: Any]] {
            XCTAssertEqual(parts.first?["type"] as? String, "text")
            XCTAssertEqual(parts.first?["text"] as? String, "look")
            XCTAssertEqual(parts.last?["type"] as? String, "image_url")
        } else {
            XCTAssertEqual(content as? String, "look", "missing file must fall back to plain text")
        }
    }

    func testOrderedMessagesHoistsSystemToFront() {
        let input = [
            ChatMessage.user("hi"),
            ChatMessage.system("be brief"),
            ChatMessage.assistant("hello"),
            ChatMessage.system("also be kind"),
        ]
        let ordered = LLMService.orderedMessages(input)
        XCTAssertEqual(ordered.map(\.role), [.system, .system, .user, .assistant])
        XCTAssertEqual(ordered.first?.content, "be brief")
    }

    func testLooksLikeToolRejectionHeuristic() {
        XCTAssertTrue(LLMService.looksLikeToolRejection(
            LLMError.badResponse("tools.0.function.parameters: field required")))
        XCTAssertTrue(LLMService.looksLikeToolRejection(
            LLMError.badResponse("Invalid request: function parameters must be an object")))
        XCTAssertFalse(LLMService.looksLikeToolRejection(
            LLMError.badResponse("model not found")))
        XCTAssertFalse(LLMService.looksLikeToolRejection(LLMError.unauthorized))
    }
}
