import XCTest
@testable import AstralAI

/// Unit tests for JSONExtractor: locating the first complete JSON value
/// inside free-form model output (plans, structured replies, tool
/// arguments). The extractor must survive fences, surrounding prose and
/// braces nested inside string literals.
final class JSONExtractorTests: XCTestCase {

    func testFencedJSONInsideText() throws {
        let text = "Here is the plan: ```json\n{\"steps\":[1,2]}\n``` done"
        let data = try XCTUnwrap(JSONExtractor.firstJSON(in: text))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )
        XCTAssertEqual(object["steps"] as? [Int], [1, 2])
    }

    func testNestedBracesInsideStringValues() throws {
        // The closing brace inside the string value must not terminate
        // the JSON object prematurely.
        let text = "result {\"a\":\"}\"} trailing text"
        let data = try XCTUnwrap(JSONExtractor.firstJSON(in: text))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
        )
        XCTAssertEqual(object["a"], "}")
    }

    func testUnfencedObjectInsideText() throws {
        let text = "prefix {\"ok\":true} suffix"
        let data = try XCTUnwrap(JSONExtractor.firstJSON(in: text))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )
        XCTAssertEqual(object["ok"] as? Bool, true)
    }

    func testFirstObjectWinsWhenMultipleObjectsPresent() throws {
        let text = "first {\"a\":1} then {\"b\":2}"
        let data = try XCTUnwrap(JSONExtractor.firstJSON(in: text))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )
        XCTAssertEqual(object["a"] as? Int, 1)
        XCTAssertNil(object["b"])
    }

    func testArrayOnlyText() throws {
        let data = try XCTUnwrap(JSONExtractor.firstJSON(in: "[1,2,3]"))
        let array = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [Any]
        )
        XCTAssertEqual((array as? [Int])?.count, 3)
    }

    func testTextWithoutJSONReturnsNil() {
        XCTAssertNil(JSONExtractor.firstJSON(in: "plain text with no json at all"))
    }

    func testUnbalancedBraceReturnsNil() {
        XCTAssertNil(JSONExtractor.firstJSON(in: "text with { an unclosed brace"))
    }
}
