import Foundation

// MARK: - Server-Sent Events parser

/// Incremental Server-Sent Events (SSE) parser.
///
/// Survives arbitrary chunk boundaries, CRLF line endings, comment lines
/// and multi-line data events. The OpenAI `[DONE]` sentinel is surfaced as
/// a plain payload so the service layer can interpret it.
struct SSEParser {

    /// Text received but not yet terminated by a newline.
    private(set) var buffer: String = ""

    /// Data lines of the event currently being assembled.
    private var dataLines: [String] = []

    /// Whether the pending event carries at least one data line.
    private var hasData = false

    /// Feeds raw text and returns the payload of every completed event.
    mutating func feed(_ text: String) -> [String] {
        buffer += text
        var payloads: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            var line = String(buffer[buffer.startIndex..<newline])
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            buffer.removeSubrange(buffer.startIndex...newline)
            consume(line, into: &payloads)
        }
        return payloads
    }

    /// Emits any event still buffered at end-of-stream and resets state so
    /// the parser can be reused afterwards.
    mutating func flush() -> [String] {
        var payloads: [String] = []
        if !buffer.isEmpty {
            var line = buffer
            buffer = ""
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            consume(line, into: &payloads)
        }
        if hasData {
            payloads.append(dataLines.joined(separator: "\n"))
            dataLines = []
            hasData = false
        }
        return payloads
    }

    /// Applies a single SSE line, dispatching the assembled event when a
    /// blank line (event boundary) is reached.
    private mutating func consume(_ line: String, into payloads: inout [String]) {
        if line.isEmpty {
            if hasData {
                payloads.append(dataLines.joined(separator: "\n"))
                dataLines = []
                hasData = false
            }
            return
        }
        if line.hasPrefix(":") {
            // Comment / keep-alive line.
            return
        }
        guard let colon = line.firstIndex(of: ":") else {
            // A bare field name with no value; only "data" is meaningful.
            if line == "data" {
                dataLines.append("")
                hasData = true
            }
            return
        }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        // Per the SSE spec a single leading space after the colon is stripped.
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        if field == "data" {
            dataLines.append(value)
            hasData = true
        }
        // Other fields (event, id, retry) are intentionally ignored.
    }
}
