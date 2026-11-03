import Foundation

// MARK: - Line splitter

/// Pure, testable byte-exact line splitter: splits ONLY on "\n"
/// (stripping a trailing "\r"), and ALWAYS preserves empty lines.
/// SSE framing depends on empty lines — AsyncLineSequence's behavior
/// around them is platform-subtle, so the streaming path must not
/// depend on it.
struct LineSplitter {
    private var buffer: [UInt8] = []
    private var pendingCR = false

    /// Feeds raw bytes and returns every completed line (terminator
    /// stripped). Empty lines are returned as "".
    mutating func feed(_ bytes: [UInt8]) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                if pendingCR { buffer.removeLast(); pendingCR = false }
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll(keepingCapacity: true)
            } else {
                if byte == UInt8(ascii: "\r") { pendingCR = true } else { pendingCR = false }
                buffer.append(byte)
            }
        }
        return lines
    }

    /// Returns any trailing partial line (nil when nothing buffered).
    mutating func finish() -> String? {
        pendingCR = false
        guard !buffer.isEmpty else { return nil }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}

// MARK: - Async line reader

/// Streams byte-exact lines from URLSession.AsyncBytes using
/// LineSplitter. Guarantees: "\n" is the only terminator, "\r\n" is
/// tolerated, empty lines ARE delivered, and the trailing partial line
/// is delivered at end-of-stream.
enum ByteLineReader {
    /// One line per yielded String; empty lines included.
    static func lines(_ bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var splitter = LineSplitter()
                do {
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        // Feed one byte at a time; AsyncBytes buffers
                        // internally so this is not a syscall per byte.
                        for line in splitter.feed([byte]) {
                            continuation.yield(line)
                        }
                    }
                    if let rest = splitter.finish() {
                        continuation.yield(rest)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Reads up to `limit` bytes of the stream as UTF-8 text (best
    /// effort) — used to capture error bodies.
    static func drain(_ bytes: URLSession.AsyncBytes, limit: Int = 2000) async -> String {
        var collected: [UInt8] = []
        collected.reserveCapacity(limit)
        do {
            for try await byte in bytes {
                collected.append(byte)
                if collected.count >= limit { break }
            }
        } catch {
            // Best effort: return whatever was collected.
        }
        return String(decoding: collected, as: UTF8.self)
    }
}
