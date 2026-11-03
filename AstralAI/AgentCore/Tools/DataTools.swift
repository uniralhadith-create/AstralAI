import Foundation
import JavaScriptCore

// MARK: - JavaScriptTool

/// Executes arbitrary JavaScript in a sandboxed JSC context.
@MainActor
final class JavaScriptTool: AgentTool {

    let name = "run_javascript"
    private static let maxOutput = 4000

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Run JavaScript code in a sandboxed context and return the value of the last expression. Useful for calculations, string processing and quick prototypes.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "code": .object([
                        "type": .string("string"),
                        "description": .string("The JavaScript code to execute"),
                    ]),
                ]),
                "required": .array([.string("code")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let code = arguments["code"]?.stringValue,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'code'.", isError: true)
        }

        guard let jsContext = JSContext() else {
            return ToolResult(content: "Error: could not create the JavaScript runtime.", isError: true)
        }

        var exceptionMessage: String?
        jsContext.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "Unknown JavaScript error"
        }

        let value = jsContext.evaluateScript(code)

        if let exceptionMessage {
            return ToolResult(content: "JavaScript error: \(exceptionMessage)", isError: true)
        }
        guard let value else {
            return ToolResult(content: "undefined")
        }
        if value.isUndefined {
            return ToolResult(content: "undefined")
        }
        if value.isNull {
            return ToolResult(content: "null")
        }

        let output = value.toString() ?? "undefined"
        if output.count > Self.maxOutput {
            return ToolResult(
                content: String(output.prefix(Self.maxOutput))
                    + "\n... [output truncated at \(Self.maxOutput) characters]")
        }
        return ToolResult(content: output)
    }
}

// MARK: - DataAnalysisTool

/// Analyzes CSV/JSON data and produces a plain-text statistical report.
@MainActor
final class DataAnalysisTool: AgentTool {

    let name = "analyze_data"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Analyze tabular data (CSV/TSV text or a JSON array of objects, or a workspace file path) and report row counts, columns and per-column statistics. Can also answer simple questions about the data.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("The data itself (CSV/TSV/JSON) or a workspace-relative file path"),
                    ]),
                    "question": .object([
                        "type": .string("string"),
                        "description": .string("Optional question about the data, e.g. 'what is the average price?'"),
                    ]),
                ]),
                "required": .array([.string("content")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard var content = arguments["content"]?.stringValue,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'content'.", isError: true)
        }
        let question = arguments["question"]?.stringValue

        // When the input looks like a path, read the file from the workspace.
        if !content.contains("\n"), content.count < 300 {
            let candidate = content.hasPrefix("/")
                ? String(content.dropFirst())
                : content
            if let text = try? context.workspace.read(path: candidate),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = text
            }
        }

        guard let (headers, rows, sourceKind) = Self.parse(content) else {
            return ToolResult(
                content: "Error: could not parse the data as JSON or CSV. Provide CSV text, TSV text, a JSON array of objects, or a workspace file path.",
                isError: true)
        }

        var report = Self.statisticsReport(headers: headers, rows: rows, sourceKind: sourceKind)

        if let question, !question.trimmingCharacters(in: .whitespaces).isEmpty {
            if let answer = Self.answer(question: question, headers: headers, rows: rows) {
                report += "\n\nAnswer to \"\(question)\": \(answer)"
            } else {
                report += "\n\nThe statistics above summarize the dataset for the question \"\(question)\"."
            }
        }

        return ToolResult(content: report)
    }

    // MARK: Parsing

    /// Returns (headers, rows, kind) or nil when nothing parses.
    private static func parse(_ content: String) -> ([String], [[String]], String)? {
        // JSON array of objects.
        if let data = content.data(using: .utf8),
           let jsonValue = JSONValue.from(data: data),
           let array = jsonValue.arrayValue,
           !array.isEmpty {
            var keys: [String] = []
            var rows: [[String]] = []
            var valid = true
            for item in array {
                guard let object = item.objectValue else {
                    valid = false
                    break
                }
                if keys.isEmpty {
                    keys = object.keys.sorted()
                }
                rows.append(keys.map { stringify(object[$0]) })
            }
            if valid, !keys.isEmpty {
                return (keys, rows, "JSON data")
            }
        }

        // Delimited text (CSV or TSV).
        let parsed = parseDelimited(content)
        if parsed.count >= 2, !parsed[0].isEmpty {
            return (parsed[0], Array(parsed.dropFirst()), "CSV data")
        }
        if parsed.count == 1, parsed[0].count > 1 {
            return (parsed[0], [], "CSV header row")
        }
        return nil
    }

    /// Proper CSV/TSV splitter handling quoted fields.
    private static func parseDelimited(_ text: String) -> [[String]] {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let delimiter: Character = firstLine.filter { $0 == "\t" }.count
            > firstLine.filter { $0 == "," }.count ? "\t" : ","

        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                if character == "\"" {
                    inQuotes = true
                } else if character == delimiter {
                    currentRow.append(field)
                    field = ""
                } else if character == "\n" {
                    currentRow.append(field)
                    field = ""
                    rows.append(currentRow)
                    currentRow = []
                } else if character != "\r" {
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !currentRow.isEmpty {
            currentRow.append(field)
            rows.append(currentRow)
        }
        return rows.filter { row in !row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private static func stringify(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let s):
            return s
        case .number(let n):
            if n == n.rounded() {
                return String(Int(n))
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return ""
        case .object, .array:
            return value.jsonData(pretty: false).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    // MARK: Statistics

    private static func statisticsReport(
        headers: [String],
        rows: [[String]],
        sourceKind: String
    ) -> String {
        var lines: [String] = []
        lines.append("Analyzed \(sourceKind): \(rows.count) rows, \(headers.count) columns.")
        lines.append("Columns: " + headers.joined(separator: ", "))

        var numericLines: [String] = []
        var textLines: [String] = []

        for (columnIndex, header) in headers.enumerated() {
            let values = rows.map { row in
                row.indices.contains(columnIndex)
                    ? row[columnIndex].trimmingCharacters(in: .whitespaces)
                    : ""
            }
            let nonEmpty = values.filter { !$0.isEmpty }
            if nonEmpty.isEmpty { continue }

            let numbers = nonEmpty.compactMap { Double($0) }
            if numbers.count == nonEmpty.count, !numbers.isEmpty {
                let minimum = numbers.min() ?? 0
                let maximum = numbers.max() ?? 0
                let sum = numbers.reduce(0, +)
                let mean = sum / Double(numbers.count)
                numericLines.append(
                    "- \(header): min \(formatted(minimum)), max \(formatted(maximum)), mean \(formatted(mean)), sum \(formatted(sum))")
            } else {
                var counts: [String: Int] = [:]
                for value in nonEmpty {
                    counts[value, default: 0] += 1
                }
                if let top = counts.max(by: { $0.value < $1.value }) {
                    textLines.append(
                        "- \(header): \(counts.count) distinct, most frequent: \(top.key) (\(top.value) times)")
                }
            }
        }

        if !numericLines.isEmpty {
            lines.append("")
            lines.append("Numeric columns:")
            lines.append(contentsOf: numericLines)
        }
        if !textLines.isEmpty {
            lines.append("")
            lines.append("Text columns:")
            lines.append(contentsOf: textLines)
        }
        return lines.joined(separator: "\n")
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: Question answering

    /// Answers simple, directly derivable questions (row counts, and
    /// min/max/mean/sum of a mentioned numeric column).
    private static func answer(
        question: String,
        headers: [String],
        rows: [[String]]
    ) -> String? {
        let q = question.lowercased()

        if q.contains("how many"), q.contains("row") {
            return "The dataset has \(rows.count) rows."
        }
        if q.contains("how many"), q.contains("column") {
            return "The dataset has \(headers.count) columns."
        }

        for (columnIndex, header) in headers.enumerated() where q.contains(header.lowercased()) {
            let values = rows.compactMap { row in
                row.indices.contains(columnIndex)
                    ? Double(row[columnIndex].trimmingCharacters(in: .whitespaces))
                    : nil
            }
            guard !values.isEmpty else { continue }
            let sum = values.reduce(0, +)
            let mean = sum / Double(values.count)

            if q.contains("average") || q.contains("mean") {
                return "The average of \(header) is \(formatted(mean))."
            }
            if q.contains("sum") || q.contains("total") {
                return "The sum of \(header) is \(formatted(sum))."
            }
            if q.contains("max") || q.contains("highest") || q.contains("largest") {
                return "The maximum of \(header) is \(formatted(values.max() ?? 0))."
            }
            if q.contains("min") || q.contains("lowest") || q.contains("smallest") {
                return "The minimum of \(header) is \(formatted(values.min() ?? 0))."
            }
        }
        return nil
    }
}
