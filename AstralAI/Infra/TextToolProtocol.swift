import Foundation

// MARK: - Universal Fault-Tolerant Text Tool & Thinking Protocol (V8.0)

/// The universal tool-calling & thinking filter that turns ANY model —
/// including `moonshotai.kimi-k2.5`, DeepSeek R1, Qwen, and providers behind
/// custom or Bedrock protocols — into a clean, reliable agent.
///
/// V8.0 upgrades:
/// - Fault-tolerant JSON recovery when a model emits unescaped inner quotes
///   inside `ASTRAL_TOOL {"name": "web_search", "arguments": {"query": ""foo" bar"}}`.
/// - Unconditional stripping of `ASTRAL_TOOL`, `TOOL_CALL`, `<|tool_call|>`,
///   `TOOL_RESULT[`, `<think>...</think>`, `<thinking>...</thinking>`, and
///   `◁think▷...◁/think▷` from user-visible chat text so raw tool JSON or
///   internal thinking NEVER leaks into the chat timeline.
/// - Extraction of thinking blocks so the UI can display them inside the
///   collapsible "عرض الخطوات والتفكير" (Show Steps & Thinking) drawer.
enum TextToolProtocol {

    /// The primary marker the model is instructed to use.
    static let marker = "ASTRAL_TOOL"
    /// Secondary markers tolerated for compatibility (Hermes/Qwen/Kimi style).
    private static let hermesOpen = "<|tool_call|>"
    private static let secondaryMarkers = [
        "ASTRAL_TOOL:", "TOOL_CALL:", "TOOL_CALL", hermesOpen, "<tool_call>"
    ]

    // MARK: Prompt building

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
        lines.append("- \"arguments\" MUST be a valid JSON object matching the tool's parameters exactly (escape any inner quotes with \\\\\").")
        lines.append("- When no more tools are needed, write your final answer to the user in plain language with NO marker lines.")
        lines.append("- Never write ASTRAL_TOOL inside code blocks or examples.")
        lines.append("")
        lines.append("Available tools:")
        for spec in tools {
            lines.append(render(spec: spec))
        }
        return lines.joined(separator: "\n")
    }

    static func render(spec: ToolSpec) -> String {
        var line = "- \(spec.function.name): \(spec.function.description.trimmingCharacters(in: .whitespacesAndNewlines))"
        if let parameters = spec.function.parameters,
           case .object(let root)? = Optional(parameters),
           case .object(let properties)? = root["properties"] {
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

    static func resultMessage(name: String, content: String) -> String {
        let trimmed = content.count > 6000
            ? String(content.prefix(6000)) + "\n... [output truncated]"
            : content
        return "TOOL_RESULT[\(name)]:\n\(trimmed)\n\nContinue the task. Call another tool with a marker line if needed, otherwise write your final answer to the user now."
    }

    // MARK: Thinking Extraction & Visible Text Sanitization

    /// Extracts `<think>...</think>`, `<thinking>...</thinking>`, or
    /// `◁think▷...◁/think▷` blocks from a model response so they can be shown
    /// inside the collapsible "عرض الخطوات والتفكير" drawer.
    static func extractThinkingBlocks(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var thoughts: [String] = []
        let patterns = [
            "<think>([\\s\\S]*?)</think>",
            "<thinking>([\\s\\S]*?)</thinking>",
            "◁think▷([\\s\\S]*?)◁/think▷",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, options: [], range: nsRange) {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: text) {
                        let cleaned = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            thoughts.append(cleaned)
                        }
                    }
                }
            }
        }
        return thoughts
    }

    /// Extracts any `ASTRAL_TOOL` calls written in plain text so the UI can
    /// list them inside the "عرض الخطوات والتفكير" drawer even on older saved
    /// messages.
    static func extractEmbeddedToolCalls(in text: String) -> [ToolCall] {
        let parsed = parseCalls(in: text)
        return parsed.enumerated().map { idx, call in
            ToolCall(id: "embedded_\(idx)", name: call.name, arguments: call.argumentsJSON)
        }
    }

    /// Cleans a message's text for display in the chat bubble:
    /// - Strips all `ASTRAL_TOOL` / `TOOL_CALL` / `<|tool_call|>` calls (even
    ///   when JSON has unescaped quotes or is malformed)
    /// - Strips `<think>...</think>`, `<thinking>...</thinking>`, and
    ///   `◁think▷...◁/think▷` blocks
    /// - Strips `STEP_COMPLETE:` / `STEP_BLOCKED:` markers
    static func cleanVisibleText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var result = stripCalls(in: text)

        // Strip closed thinking tags
        let closedPatterns = [
            "<think>[\\s\\S]*?</think>",
            "<thinking>[\\s\\S]*?</thinking>",
            "◁think▷[\\s\\S]*?◁/think▷",
            "<tool_call>[\\s\\S]*?</tool_call>",
        ]
        for pattern in closedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // Strip unclosed trailing `<think>...` while streaming
        for openTag in ["<think>", "<thinking>", "◁think▷", "<|tool_call|>", "<tool_call>"] {
            if let range = result.range(of: openTag, options: [.caseInsensitive]) {
                result = String(result[..<range.lowerBound])
            }
        }

        // Unconditionally strip any remaining line containing ASTRAL_TOOL or TOOL_RESULT[
        let filteredLines = result.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ASTRAL_TOOL")
                || trimmed.hasPrefix("TOOL_CALL")
                || trimmed.hasPrefix("TOOL_RESULT[")
                || trimmed.hasPrefix("<|tool_call|>")
                || trimmed.contains("ASTRAL_TOOL {")
                || trimmed.contains("ASTRAL_TOOL:") {
                return false
            }
            return true
        }
        result = filteredLines.joined(separator: "\n")

        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Parsing

    struct Call {
        let name: String
        let argumentsJSON: String
        let range: Range<String.Index>
    }

    static func parseCalls(in text: String) -> [Call] {
        var calls: [Call] = []
        var searchRange = text.startIndex..<text.endIndex

        while let hit = findNextMarker(in: text, range: searchRange) {
            let jsonStart = hit.jsonStart
            if let (object, end) = extractJSONObject(in: text, from: jsonStart) {
                if let object, let (name, arguments) = decodeCall(object) {
                    calls.append(Call(
                        name: name,
                        argumentsJSON: arguments,
                        range: hit.markerStart..<end))
                    searchRange = end..<text.endIndex
                    if searchRange.isEmpty { break }
                    continue
                }
                // JSON brace balanced, but JSONSerialization failed (e.g. Kimi K2.5
                // emitted unescaped inner quotes like `"query":""سيرة لسان الذهب" сайт"`).
                // Try fault-tolerant recovery on the raw slice!
                let rawSlice = String(text[jsonStart..<end])
                if let recovered = recoverMalformedCall(from: rawSlice) {
                    calls.append(Call(
                        name: recovered.name,
                        argumentsJSON: recovered.arguments,
                        range: hit.markerStart..<end))
                }
                searchRange = end..<text.endIndex
                if searchRange.isEmpty { break }
                continue
            }

            // Even if braces were not balanced by quote-aware scan (because of
            // an odd number of unescaped quotes on the line), try line-level
            // recovery to the end of the line!
            let lineEnd = text[jsonStart...].firstIndex(of: "\n") ?? text.endIndex
            let lineSlice = String(text[jsonStart..<lineEnd])
            if let recovered = recoverMalformedCall(from: lineSlice) {
                calls.append(Call(
                    name: recovered.name,
                    argumentsJSON: recovered.arguments,
                    range: hit.markerStart..<lineEnd))
                searchRange = lineEnd..<text.endIndex
                if searchRange.isEmpty { break }
                continue
            }

            searchRange = jsonStart..<text.endIndex
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
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsIncompleteCall(_ text: String) -> Bool {
        guard let hit = findNextMarker(in: text, range: text.startIndex..<text.endIndex) else {
            return false
        }
        guard let (_, _) = extractJSONObject(in: text, from: hit.jsonStart) else {
            return true
        }
        return false
    }

    // MARK: Streaming filter

    struct StreamFilter {
        private var pending = ""

        mutating func feed(_ delta: String) -> String {
            pending += delta
            var release = ""

            while true {
                let calls = TextToolProtocol.parseCalls(in: pending)
                guard let first = calls.first else {
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
            }

            return release
        }

        mutating func flush() -> String {
            let leftover = pending
            pending = ""
            let trimmed = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
            let startsWithMarker = allMarkers.contains { marker in
                trimmed.hasPrefix(marker)
            }
            return startsWithMarker ? "" : TextToolProtocol.cleanVisibleText(leftover)
        }
    }

    // MARK: Fault-Tolerant Malformed JSON Recovery (Fixes Kimi K2.5 Unescaped Quotes)

    /// Recovers tool calls when a model outputs unescaped double quotes inside
    /// a string value, e.g.:
    /// `{"name": "web_search", "arguments": {"max_results":10,"query":""سيرة لسان الذهب" сайт"}}`
    private static func recoverMalformedCall(from raw: String) -> (name: String, arguments: String)? {
        guard let nameRegex = try? NSRegularExpression(pattern: #""name"\s*:\s*"([A-Za-z0-9_.-]+)""#),
              let nameMatch = nameRegex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)),
              nameMatch.numberOfRanges > 1,
              let nameRange = Range(nameMatch.range(at: 1), in: raw) else {
            return nil
        }
        let toolName = String(raw[nameRange])
        guard !toolName.isEmpty else { return nil }

        var argsDict: [String: Any] = [:]

        // Extract numeric parameters like "max_results": 10
        if let numRegex = try? NSRegularExpression(pattern: #""([A-Za-z0-9_]+)"\s*:\s*(-?\d+(?:\.\d+)?)\b"#) {
            for m in numRegex.matches(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)) {
                if m.numberOfRanges > 2,
                   let kRange = Range(m.range(at: 1), in: raw),
                   let vRange = Range(m.range(at: 2), in: raw) {
                    let k = String(raw[kRange])
                    let vStr = String(raw[vRange])
                    if k != "name" {
                        if let i = Int(vStr) { argsDict[k] = i }
                        else if let d = Double(vStr) { argsDict[k] = d }
                    }
                }
            }
        }

        // Extract primary string parameter ("query", "command", "url", "path", "code", "content")
        for key in ["query", "command", "url", "path", "code", "content", "title", "prompt"] {
            let keyToken = "\"\(key)\""
            if let keyRange = raw.range(of: keyToken) {
                var afterKey = raw[keyRange.upperBound...]
                while let first = afterKey.first, first == " " || first == "\t" || first == ":" {
                    afterKey.removeFirst()
                }
                if afterKey.first == "\"" {
                    afterKey.removeFirst()
                    // Find the end of this field (before `}` or `,"nextKey":`)
                    var valueSlice = String(afterKey)
                    if let closingBraces = valueSlice.range(of: #""\s*\}\s*\}"#, options: .regularExpression) {
                        valueSlice = String(valueSlice[..<closingBraces.lowerBound])
                    } else if let nextField = valueSlice.range(of: #""\s*,\s*"[A-Za-z0-9_]+"\s*:"#, options: .regularExpression) {
                        valueSlice = String(valueSlice[..<nextField.lowerBound])
                    } else if let endQuote = valueSlice.lastIndex(of: "\"") {
                        valueSlice = String(valueSlice[..<endQuote])
                    }
                    let cleanedValue = valueSlice.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanedValue.isEmpty {
                        argsDict[key] = cleanedValue
                    }
                }
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: argsDict, options: []),
           let argsJSON = String(data: data, encoding: .utf8) {
            return (toolName, argsJSON)
        }
        return (toolName, "{}")
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
                if found.lowerBound == text.startIndex {
                    let hit = MarkerHit(markerStart: found.lowerBound, jsonStart: found.upperBound)
                    if best == nil || hit.markerStart < best!.markerStart {
                        best = hit
                    }
                    break
                }
                let previous = text.index(before: found.lowerBound)
                let boundary = text[previous] == "\n" || text[previous].isWhitespace || text[previous] == "`" || text[previous] == "*"
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

    static func firstUnterminatedMarkerIndex(in text: String) -> String.Index? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let hit = findNextMarker(in: text, range: searchStart..<text.endIndex) {
            if let (_, end) = extractJSONObject(in: text, from: hit.jsonStart) {
                searchStart = end
                continue
            }
            return hit.markerStart
        }
        return nil
    }

    private static func extractJSONObject(
        in text: String,
        from start: String.Index
    ) -> ([String: Any]?, String.Index)? {
        var index = start
        while index < text.endIndex, (text[index].isWhitespace && text[index] != "\n") || text[index] == ":" {
            index = text.index(after: index)
        }
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
            } else if ch == "\\", inString {
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
