import XCTest
@testable import AstralAI

/// Unit tests for LineSplitter (the pure core of ByteLineReader): the
/// streaming path depends on it delivering byte-exact lines — "\n" is the
/// only terminator, "\r\n" is tolerated, empty lines (SSE event boundaries)
/// are ALWAYS delivered, and chunk boundaries never split a line in half.
final class ByteLineReaderTests: XCTestCase {

    // MARK: Basic splitting

    func testEmptyLinesArePreserved() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\n\nb\n".utf8)), ["a", "", "b"])
    }

    func testUnterminatedTailDeliveredByFinish() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\n\nb".utf8)), ["a", ""])
        XCTAssertEqual(splitter.finish(), "b")
    }

    func testSSEEventSequenceYieldsEmptyLinePerBoundary() {
        var splitter = LineSplitter()
        let lines = splitter.feed(Array("data: one\n\ndata: two\n\n".utf8))
        XCTAssertEqual(lines, ["data: one", "", "data: two", ""])
    }

    func testEmptyInputYieldsNothing() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed([]), [])
        XCTAssertNil(splitter.finish())
    }

    // MARK: CRLF tolerance

    func testCRLFIsStrippedBeforeLF() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\r\nb\r\n".utf8)), ["a", "b"])
    }

    func testCRLFPreservesEmptyLines() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\r\n\r\nb\r\n".utf8)), ["a", "", "b"])
    }

    func testLoneCRIsDataNotTerminator() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\rb\n".utf8)), ["a\rb"])
    }

    func testCRAcrossFeedBoundary() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\r".utf8)), [])
        XCTAssertEqual(splitter.feed(Array("\nb".utf8)), ["a"])
    }

    // MARK: Arbitrary chunk boundaries

    func testOneByteFeeds() {
        var splitter = LineSplitter()
        var lines: [String] = []
        for byte in Array("data: hi\n\ndata: bye\n\n".utf8) {
            lines.append(contentsOf: splitter.feed([byte]))
        }
        XCTAssertEqual(lines, ["data: hi", "", "data: bye", ""])
        XCTAssertNil(splitter.finish())
    }

    func testOneByteFeedsWithCRLF() {
        var splitter = LineSplitter()
        var lines: [String] = []
        for byte in Array("a\r\n\r\nb\r\n".utf8) {
            lines.append(contentsOf: splitter.feed([byte]))
        }
        XCTAssertEqual(lines, ["a", "", "b"])
    }

    func testSplitAcrossUnevenChunks() {
        var splitter = LineSplitter()
        var lines: [String] = []
        let bytes = Array("data: hello\n\ndata: world\n\n".utf8)
        // Feed in chunks of 3, 1, 5, 1, 2 bytes — never aligned with a
        // line boundary.
        let chunkSizes = [3, 1, 5, 1, 2]
        var index = 0
        while index < bytes.count {
            let end = min(index + chunkSizes[index % chunkSizes.count], bytes.count)
            lines.append(contentsOf: splitter.feed(Array(bytes[index..<end])))
            index = end
        }
        XCTAssertEqual(lines, ["data: hello", "", "data: world", ""])
        XCTAssertNil(splitter.finish())
    }

    func testMultibyteUTF8AcrossFeeds() {
        var splitter = LineSplitter()
        // "مرحبا" is 2 bytes per character; split the stream inside a
        // character to prove the byte buffer reassembles it exactly.
        let bytes = Array("مرحبا\n".utf8)
        var lines: [String] = []
        for byte in bytes {
            lines.append(contentsOf: splitter.feed([byte]))
        }
        XCTAssertEqual(lines, ["مرحبا"])
    }

    // MARK: Trailing partial lines

    func testFinishReturnsTrailingPartialLine() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\nbc".utf8)), ["a"])
        XCTAssertEqual(splitter.finish(), "bc")
        XCTAssertNil(splitter.finish())
    }

    func testFinishIsNilAfterCompleteLine() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("a\n".utf8)), ["a"])
        XCTAssertNil(splitter.finish())
    }

    func testTrailingCRWithoutLFSurvivesAsData() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Array("abc\r".utf8)), [])
        // A CR with no following LF is data, not a terminator; the SSE
        // parser strips it itself once the line is later terminated.
        XCTAssertEqual(splitter.finish(), "abc\r")
    }

    func testSplitterReusableAfterFinish() {
        var splitter = LineSplitter()
        _ = splitter.feed(Array("partial".utf8))
        _ = splitter.finish()
        XCTAssertEqual(splitter.feed(Array("next\n".utf8)), ["next"])
    }
}
