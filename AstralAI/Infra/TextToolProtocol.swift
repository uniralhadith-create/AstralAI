import Foundation

// MARK: - Universal text tool protocol (V4.0)

/// The universal tool-calling fallback that turns ANY model - including ones
/// with no native function calling and providers behind fully custom
/// protocols - into a working agent.
///
/// When the provider rejects the "tools" schema (or the protocol cannot
/// carry tool calls), LLMService flips into text-tool mode:
///
/// 1. The tool suite is described to the model as plain text in the system
///    prompt (name, description, JSON arguments schema) together with a
///    strict wire format.
/// 2. The model asks for a tool by emitting a single line starting with
///    ASTRAL_TOOL followed by one JSON object with "name" and "arguments".
///    The widely-used Hermes/Qwen inline format (a JSON object with name and
///    arguments inside special brackets) is ALSO accepted, so models trained
///    with that convention work out of the box.
/// 3. The app parses the line, executes the tool, and feeds the result back
///    as a user-role message: TOOL_RESULT[name] <output>. The model then
///    continues until it produces a tool-free reply.
/// 4. Tool-call lines are stripped from the user-visible text; they show up
///    in the live terminal instead.
///
/// This is the definitive fix for "the agent acts like a plain chatbot":
/// native tool calling when the provider supports it, text protocol when it
/// does not - the agent ALWAYS has hands.
enum TextToolProtocol {

    /// The primary marker the model is instructed to use.
    static let marker = "ASTRAL_TOOL"
    /// Secondary markers tolerated for compatibility (Hermes/Qwen style).
    private static let hermesOpen = "<|tool_call|>"
    private static let secondaryMarkers = ["ASTRAL_TOOL:", "TOOL_CALL", hermesOpen]

    // MARK: Prompt building

    /// Renders the tool suite + wire instructions as a system-prompt block.
    static func prompt(for tools: [ToolSpec]) -> String {
        guard !tools.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("## TOOL USE PROTOCOL (IMPORTANT)")
        lines.append("You are a real agent with actual tools running on the user's device. You MUST use tools to do real work - never claim you did something without calling a tool, and never fabricate tool output.")
        lines.append("To call a tool, output ONE line in exactly this format and nothing else on that line:")
        lines.append("ASTRAL_TOOL {\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}")
        lines.append("Rules:")
        lines.append("- Emit the marker line, then STOP writing. The system executes the tool and sends you the result as a TOOL_RESULT message; continue from there.")
        lines.append("- One tool call per line. You may emit several lines to run several tools.")
        lines.append("- \"arguments\" MUST be a valid JSON object matching the tool's parameters exactly.")
        lines.append("- When no more tools are needed, write your final answer to the user in plain language with NO marker lines.")
        lines.append("- Never write ASTRAL_TOOL inside code blocks or examples.")
        lines.append("")
        lines.append("Available tools:")
        for spec in tools {
            lines.append(render(spec: spec))
        }
        return lines.joined(separator: "\n")
    }

    /// Renders one tool spec as compact text the model can follow.
    static func render(spec: ToolSpec) -> String {
        var line = "- \(spec.function.name): \(spec.function.description.trimmingCharacters(in: .whitespacesAndNewlines))"
        if let parameters = spec.function.parameters,
           case .object(let root)? = Optional(parameters),
           case .object(let properties)? = root["properties"] {
            // Keep it compact: list each parameter with its type & description.
            var parts: [String] = []
            var requiredSet: Set<String> = []
            if case .array(let required)? = root["required"] {
                requiredSet = Set(required.compactMap { $0.stringValue })
            }
            for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
                let object = value.objectValue ?? [:]
                let type = object["type"]?.stringValue ?? "any"
                let description = (object["description"]?.stringValue ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                let flag = requiredSet.contains(key) ? "required" : "optional"
                var part = "\(key) (\(type), \(flag))"
                if !description.isEmpty {
                    part += " - \(String(description.prefix(110)))"
                }
                parts.append(part)
            }
            if !parts.isEmpty {
                line += " Arguments: " + parts.joined(separator: "; ")
            }
        }
        return line
    }

    /// Formats a tool result for the wire (user-role message).
    static func resultMessage(name: String, content: String) -> String {
        let trimmed = content.count > 6000
            ? String(content.prefix(6000)) + "\n... [output truncated]"
            : content
        return "TOOL_RESULT[\(name)]:\n\(trimmed)\n\nContinue the task. Call another tool with a marker line if needed, otherwise write your final answer to the user now."
    }

    // MARK: Parsing

    /// One tool call found inside model text.
    struct Call {
        let name: String
        let argumentsJSON: String
        let range: Range<String.Index>
    }

    /// Extracts every tool-call line from a finished model reply. Recognized
    /// shapes (JSON may span the rest of the line):
    /// - ASTRAL_TOOL {"name": "...", "arguments": {...}}
    /// - TOOL_CALL {"name": "...", "arguments": {...}}
    /// - the Hermes/Qwen inline special-bracket format
    static func parseCalls(in text: String) -> [Call] {
        var calls: [Call] = []
        var searchRange = text.startIndex..<text.endIndex

        while let hit = findNextMarker(in: text, range: searchRange) {
            let jsonStart = hit.jsonStart
            guard let (object, end) = extractJSONObject(in: text, from: jsonStart) else {
                // Not a tool call after all (e.g. prose mentioning the
                // marker). Continue searching after this occurrence.
                searchRange = jsonStart..<text.endIndex
                if searchRange.isEmpty { break }
                continue
            }

            if let object, let (name, arguments) = decodeCall(object) {
                calls.append(Call(
                    name: name,
                    argumentsJSON: arguments,
                    range: hit.markerStart..<end))
            }
            // Balanced JSON that did not decode as a call stays as plain
            // text - skip past it and keep scanning.
            searchRange = end..<text.endIndex
            if searchRange.isEmpty { break }
        }
        return calls
    }

    /// Removes tool-call lines from displayed text, collapsing the gaps.
    static func stripCalls(in text: String) -> String {
        let calls = parseCalls(in: text)
        var result = text
        for call in calls.reversed() where call.range.lowerBound < result.endIndex {
            result.removeSubrange(call.range)
        }
        // Tidy: collapse 3+ consecutive newlines left by removals.
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a marker begins at/inside this text and JSON is balanced -
    /// used to decide a streamed chunk still belongs to a tool call.
    static func containsIncompleteCall(_ text: String) -> Bool {
        guard let hit = findNextMarker(in: text, range: text.startIndex..<text.endIndex) else {
            return false
        }
        guard let (_, end) = extractJSONObject(in: text, from: hit.jsonStart) else {
            return true // marker seen, JSON not closed yet
        }
        // Marker + complete JSON: check there is nothing after it that
        // suggests more output is coming (still mid-call emission).
        _ = end
        return false
    }

    // MARK: Streaming filter

    /// Streaming-safe text filter. Model text arrives in small chunks; a
    /// marker like ASTRAL_TOOL may be split across chunks ("ASTRAL_TO" +
    /// "OL {.."). This filter holds back any trailing text that could still
    /// grow into a marker, swallows complete tool-call segments, and only
    /// releases text that is provably safe to display.
    ///
    /// The full raw text lives in the caller; the final `.toolCalls` event
    /// is derived from it. The filter exists purely so the user never sees
    /// protocol plumbing mid-stream.
    struct StreamFilter {
        private var pending = ""

        /// Feed one delta; returns the text that is now provably safe to
        /// display (may be empty while a tool call is streaming in).
        mutating func feed(_ delta: String) -> String {
            pending += delta
            var release = ""

            while true {
                // Complete calls are swallowed wholesale; the prose before
                // each one is released.
                let calls = TextToolProtocol.parseCalls(in: pending)
                guard let first = calls.first else {
                    // No complete call. If a marker is open but its JSON is
                    // still streaming, hold back from that marker on.
                    if let openIndex = TextToolProtocol.firstUnterminatedMarkerIndex(in: pending) {
                        release += String(pending[..<openIndex])
                        pending = String(pending[openIndex...])
                    } else {
                        let holdback = TextToolProtocol.markerSuffixLength(of: pending)
                        release += String(pending.dropLast(holdback))
                        pending = String(pending.suffix(holdback))
                    }
                    break
                }
                release += String(pending[..<first.range.lowerBound])
                pending = String(pending[first.range.upperBound...])
                // Loop: there may be more calls or trailing prose behind.
            }

            return release
        }

        /// Flushes everything still held (stream ended). Leftover text that
        /// begins with a marker is a broken/incomplete call - dropped rather
        /// than shown as protocol plumbing.
        mutating func flush() -> String {
            let leftover = pending
            pending = ""
            let trimmed = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
            let startsWithMarker = allMarkers.contains { marker in
                trimmed.hasPrefix(marker)
            }
            return startsWithMarker ? "" : leftover
        }
    }

    // MARK: Internals

    private struct MarkerHit {
        let markerStart: String.Index
        let jsonStart: String.Index
    }

    private static func findNextMarker(
        in text: String,
        range: Range<String.Index>
    ) -> MarkerHit? {
        var best: MarkerHit?
        for marker in allMarkers where !marker.isEmpty {
            var searchStart = range.lowerBound
            while let found = text.range(of: marker, range: searchStart..<text.endIndex) {
                // The marker must start a line (or follow whitespace) to
                // avoid matching inside words like "CASTRAL_TOOLX".
                if found.lowerBound == text.startIndex {
                    let hit = MarkerHit(markerStart: found.lowerBound, jsonStart: found.upperBound)
                    if best == nil || hit.markerStart < best!.markerStart {
                        best = hit
                    }
                    break
                }
                let previous = text.index(before: found.lowerBound)
                let boundary = text[previous] == "\n" || text[previous].isWhitespace
                if boundary {
                    let hit = MarkerHit(markerStart: found.lowerBound, jsonStart: found.upperBound)
                    if best == nil || hit.markerStart < best!.markerStart {
                        best = hit
                    }
                    break
                }
                searchStart = found.upperBound
            }
        }
        return best
    }

    private static var allMarkers: [String] {
        [marker] + secondaryMarkers
    }

    /// The longest suffix of `text` that is a strict prefix of any marker
    /// (so it might still grow into one on the next chunk).
    static func markerSuffixLength(of text: String) -> Int {
        var longest = 0
        for marker in allMarkers where marker.count > 1 {
            let maxCheck = min(text.count, marker.count - 1)
            guard maxCheck > 0 else { continue }
            for length in (1...maxCheck).reversed() where length > longest {
                let suffix = String(text.suffix(length))
                if marker.hasPrefix(suffix) {
                    longest = length
                    break
                }
            }
        }
        return longest
    }

    /// Index of the first line-boundary marker whose JSON object has NOT
    /// finished streaming yet (nil when no open marker). Scans past
    /// complete calls so long prose without markers stays releasable.
    static func firstUnterminatedMarkerIndex(in text: String) -> String.Index? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let hit = findNextMarker(in: text, range: searchStart..<text.endIndex) {
            if let (_, end) = extractJSONObject(in: text, from: hit.jsonStart) {
                // This call is complete - keep scanning after it.
                searchStart = end
                continue
            }
            // Marker open, JSON not closed.
            return hit.markerStart
        }
        return nil
    }

    /// Extracts the first balanced JSON object starting at or after `start`,
    /// skipping leading whitespace. Returns the decoded object and the index
    /// just past its closing brace.
    private static func extractJSONObject(
        in text: String,
        from start: String.Index
    ) -> ([String: Any]?, String.Index)? {
        var index = start
        // Skip whitespace between marker and JSON.
        while index < text.endIndex, text[index].isWhitespace, text[index] != "\n" {
            index = text.index(after: index)
        }
        // Allow one newline after the marker (multi-line style).
        if index < text.endIndex, text[index] == "\n" {
            index = text.index(after: index)
            while index < text.endIndex, text[index] == " " || text[index] == "\t" {
                index = text.index(after: index)
            }
        }
        guard index < text.endIndex, text[index] == "{" else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        var cursor = index
        while cursor < text.endIndex {
            let ch = text[cursor]
            if escaped {
                escaped = false
            } else if ch == "\\" , inString {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        end = cursor
                        break
                    }
                }
            }
            cursor = text.index(after: cursor)
        }

        guard let closing = end else { return nil }
        let jsonText = String(text[index...closing])
        guard let data = jsonText.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return (nil, text.index(after: closing))
        }
        return (object, text.index(after: closing))
    }

    /// Decodes a call object: {"name": ..., "arguments": {...}} with the
    /// usual tolerance (arguments as object or JSON string, "parameters"
    /// accepted as an alias).
    private static func decodeCall(_ object: [String: Any]) -> (name: String, arguments: String)? {
        let name = (object["name"] as? String)
            ?? ((object["function"] as? [String: Any])?["name"] as? String)
        guard let name, !name.isEmpty else { return nil }

        var arguments = "{}"
        if let raw = object["arguments"] ?? object["parameters"] {
            if let string = raw as? String, !string.isEmpty {
                arguments = string
            } else if JSONSerialization.isValidJSONObject(raw),
                      let data = try? JSONSerialization.data(withJSONObject: raw, options: []),
                      let text = String(data: data, encoding: .utf8) {
                arguments = text
            }
        }
        return (name, arguments)
    }
}
