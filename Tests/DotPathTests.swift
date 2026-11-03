import XCTest
@testable import AstralAI

/// Unit tests for DotPath: dot-notation extraction from parsed JSON
/// payloads. DotPath is the engine behind the custom provider protocol,
/// mapping provider responses (streamed fragments, tool calls, model ids)
/// into the app's unified representation.
final class DotPathTests: XCTestCase {

    /// The canonical OpenAI-shaped sample payload used across these tests.
    private func makePayload() throws -> Any {
        let json = """
        {"choices":[{"delta":{"content":"Hello"}},{"delta":{"tool_calls":[{"index":0}]}}],"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}
        """
        let data = Data(json.utf8)
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    // MARK: extract(from:path:)

    func testExtractStringNestedInArrays() throws {
        let payload = try makePayload()
        let result = DotPath.extract(from: payload, path: "choices.0.delta.content")
        XCTAssertEqual(result as? String, "Hello")
    }

    func testExtractReturnsNilWhenKeyIsMissing() throws {
        let payload = try makePayload()
        // The second choice carries tool_calls but no content.
        XCTAssertNil(DotPath.extract(from: payload, path: "choices.1.delta.content"))
    }

    func testExtractReturnsNilForUnknownPaths() throws {
        let payload = try makePayload()
        XCTAssertNil(DotPath.extract(from: payload, path: "nonexistent.key"))
        XCTAssertNil(DotPath.extract(from: payload, path: "choices.5.delta.content"))
    }

    func testExtractNumericIndexIntoArray() throws {
        let payload = try makePayload()
        XCTAssertEqual(DotPath.extract(from: payload, path: "data.1.id") as? String, "gpt-4o-mini")
    }

    func testExtractNumberValue() throws {
        let payload = try makePayload()
        let result = DotPath.extract(from: payload, path: "choices.1.delta.tool_calls.0.index")
        XCTAssertEqual((result as? NSNumber)?.intValue, 0)
    }

    func testEmptyPathReturnsTheValueItself() throws {
        let payload = try makePayload()
        let root = try XCTUnwrap(DotPath.extract(from: payload, path: ""))
        // The returned value must behave like the original root object.
        XCTAssertEqual(
            DotPath.extract(from: root, path: "choices.0.delta.content") as? String,
            "Hello"
        )
    }

    // MARK: extractArray(from:path:)

    func testExtractArrayMapsOverArrayElements() throws {
        let payload = try makePayload()
        let ids = DotPath.extractArray(from: payload, path: "data.[].id")
        XCTAssertEqual(ids as? [String], ["gpt-4o", "gpt-4o-mini"])
    }

    func testExtractArraySkipsMissingValues() throws {
        let payload = try makePayload()
        // Only the first choice carries delta.content.
        let contents = DotPath.extractArray(from: payload, path: "choices.[].delta.content")
        XCTAssertEqual(contents as? [String], ["Hello"])
    }

    func testExtractArrayReturnsEmptyWhenNothingMatches() throws {
        let payload = try makePayload()
        XCTAssertTrue(DotPath.extractArray(from: payload, path: "choices.[].missing").isEmpty)
    }

    // MARK: stringValue(_:)

    func testStringValueOfSwiftString() {
        XCTAssertEqual(DotPath.stringValue("Hello"), "Hello")
    }

    func testStringValueOfNumbers() {
        XCTAssertEqual(DotPath.stringValue(NSNumber(value: 42)), "42")
        XCTAssertEqual(DotPath.stringValue(NSNumber(value: 3)), "3")
        XCTAssertEqual(DotPath.stringValue(NSNumber(value: 3.5)), "3.5")
    }

    func testStringValueOfNonScalarValuesIsNil() {
        XCTAssertNil(DotPath.stringValue(["a", "b"]))
        XCTAssertNil(DotPath.stringValue(["key": 1] as [String: Any]))
        XCTAssertNil(DotPath.stringValue(NSNull()))
    }
}
