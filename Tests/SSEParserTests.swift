import XCTest
@testable import AstralAI

/// Unit tests for SSEParser: incremental Server-Sent Events stream parsing
/// used by the streaming LLM client. The parser must survive arbitrary
/// chunk boundaries, CRLF endings, and the OpenAI [DONE] sentinel (which is
/// surfaced as a plain payload for the service layer to interpret).
final class SSEParserTests: XCTestCase {

    func testTwoCompleteEventsInOneChunk() {
        var parser = SSEParser()
        let events = parser.feed("data: hello\n\ndata: world\n\n")
        XCTAssertEqual(events, ["hello", "world"])
    }

    func testEventSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: hel"), [])
        XCTAssertEqual(parser.feed("lo\n\n"), ["hello"])
    }

    func testEventSplitAcrossThreeChunks() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: he"), [])
        XCTAssertEqual(parser.feed("ll"), [])
        XCTAssertEqual(parser.feed("o\n\n"), ["hello"])
    }

    func testSecondEventSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: one\n\ndata: tw"), ["one"])
        XCTAssertEqual(parser.feed("o\n\n"), ["two"])
    }

    func testDoneSentinelIsReturnedAsPayload() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: [DONE]\n\n"), ["[DONE]"])
    }

    func testDoneSentinelWithoutSpaceAfterColon() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data:[DONE]\n\n"), ["[DONE]"])
    }

    func testCRLFLineEndings() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: a\r\n\r\n"), ["a"])
    }

    func testMultipleDataLinesAreJoinedWithNewline() {
        var parser = SSEParser()
        // Per the SSE specification, consecutive data lines of a single
        // event are joined with "\n".
        XCTAssertEqual(parser.feed("data: x\ndata: y\n\n"), ["x\ny"])
    }

    func testCommentLinesAreIgnored() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed(": keepalive\n\ndata: hi\n\n"), ["hi"])
    }

    func testEventFieldLinesAreIgnored() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("event: message\ndata: bar\n\n"), ["bar"])
    }

    func testFlushEmitsBufferedPartialEvent() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: tail"), [])
        XCTAssertEqual(parser.flush(), ["tail"])
    }

    func testFlushWithEmptyBufferReturnsNothing() {
        var parser = SSEParser()
        _ = parser.feed("data: a\n\n")
        XCTAssertEqual(parser.flush(), [])
    }

    func testParserIsReusableAfterFlush() {
        var parser = SSEParser()
        _ = parser.feed("data: partial")
        _ = parser.flush()
        XCTAssertEqual(parser.feed("data: next\n\n"), ["next"])
    }
}
