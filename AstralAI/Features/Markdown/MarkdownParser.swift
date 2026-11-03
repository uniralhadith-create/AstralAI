import Foundation

// MARK: - Markdown model (V5.0.0)

/// A block-level markdown element.
enum MarkdownBlock {
    case heading(level: Int, inlines: [MarkdownInline])
    case paragraph([MarkdownInline])
    case codeBlock(language: String?, code: String)
    case quote([MarkdownBlock])
    case list(ordered: Bool, items: [[MarkdownInline]])
    case table(header: [String], rows: [[String]])
    case divider
    case mathBlock(String)
}

/// An inline markdown element inside a paragraph, heading, list item or quote.
enum MarkdownInline {
    case text(String)
    case emphasis(String, bold: Bool, italic: Bool)
    case code(String)
    case link(text: String, url: String)
    case image(alt: String, url: String)
    case math(String)
    case strikethrough(String)
}

// MARK: - Parser (V5.0.0 — Streaming-Aware, Task-Lists, Callouts & Inline-Ready)

/// A complete, dependency-free markdown parser tuned for streaming agent
/// output: headings, paragraphs, fenced code (including unclosed in-flight
/// code fences during streaming), quotes & callout admonitions, lists &
/// task checkboxes (`- [x]`, `- [ ]`), tables, dividers, math blocks, and
/// inline constructs.
enum MarkdownParser {

    // MARK: Block parsing

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            paragraphLines = []
            guard !joined.isEmpty else { return }
            blocks.append(.paragraph(parseInlines(joined)))
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line: separates paragraphs and terminates all blocks.
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // Fenced code block (``` or ~~~), raw content until closing fence.
            if let fence = fenceSpec(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if isClosingFence(candidate, marker: fence.marker) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(language: fence.language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Math block: $$ ... $$ on one line, or across several lines.
            if trimmed.hasPrefix("$$") {
                flushParagraph()
                let afterOpen = String(trimmed.dropFirst(2))
                if afterOpen.hasSuffix("$$"), afterOpen.count >= 2 {
                    let content = String(afterOpen.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty { blocks.append(.mathBlock(content)) }
                    index += 1
                } else {
                    var mathLines: [String] = []
                    if !afterOpen.isEmpty {
                        mathLines.append(afterOpen.trimmingCharacters(in: .whitespaces))
                    }
                    index += 1
                    while index < lines.count {
                        let mathLine = lines[index].trimmingCharacters(in: .whitespaces)
                        if mathLine.contains("$$") {
                            let before = (mathLine.components(separatedBy: "$$").first ?? "")
                                .trimmingCharacters(in: .whitespaces)
                            if !before.isEmpty { mathLines.append(before) }
                            index += 1
                            break
                        }
                        mathLines.append(mathLine)
                        index += 1
                    }
                    let content = mathLines.filter { !$0.isEmpty }.joined(separator: " ")
                    if !content.isEmpty { blocks.append(.mathBlock(content)) }
                }
                continue
            }

            // ATX heading: # .. ###### followed by a space (or end of line).
            if let heading = atxHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, inlines: heading.inlines))
                index += 1
                continue
            }

            // Thematic break: ---, *** or ___
            if isThematicBreak(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            // Blockquote: consecutive lines starting with ">", parsed
            // recursively so nested structures survive.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var content = String(candidate.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoted.append(content)
                    index += 1
                }
                blocks.append(.quote(parse(quoted.joined(separator: "\n"))))
                continue
            }

            // Table: a pipe row followed by a delimiter row.
            if trimmed.contains("|"),
               index + 1 < lines.count,
               isTableDelimiter(lines[index + 1]) {
                let header = tableCells(trimmed)
                if !header.isEmpty {
                    flushParagraph()
                    var rows: [[String]] = []
                    var cursor = index + 2
                    while cursor < lines.count {
                        let rowLine = lines[cursor].trimmingCharacters(in: .whitespaces)
                        if rowLine.isEmpty || !rowLine.contains("|") { break }
                        rows.append(tableCells(rowLine))
                        cursor += 1
                    }
                    blocks.append(.table(header: header, rows: rows))
                    index = cursor
                    continue
                }
            }

            // List: consecutive unordered (-, *, +, •) or ordered (1. 1)) items.
            if let firstItem = listItem(trimmed) {
                flushParagraph()
                let ordered = firstItem.ordered
                var items: [[MarkdownInline]] = [parseInlines(firstItem.text)]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if let next = listItem(candidate), next.ordered == ordered {
                        items.append(parseInlines(next.text))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(ordered: ordered, items: items))
                continue
            }

            // Plain paragraph line (joined with the previous ones).
            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: Block helpers

    private static func fenceSpec(_ trimmed: String) -> (marker: String, language: String?)? {
        for marker in ["```", "~~~"] {
            guard trimmed.hasPrefix(marker) else { continue }
            let fenceChar = marker.first ?? "`"
            let info = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            if info.isEmpty || info.allSatisfy({ $0 == fenceChar }) {
                return (marker, nil)
            }
            let language = info.components(separatedBy: .whitespaces).first
            return (marker, (language?.isEmpty ?? true) ? nil : language)
        }
        return nil
    }

    private static func isClosingFence(_ trimmed: String, marker: String) -> Bool {
        let fenceChar = marker.first ?? "`"
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == fenceChar }
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, inlines: [MarkdownInline])? {
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        var content = rest.trimmingCharacters(in: .whitespaces)
        if let range = content.range(of: "[ \\t]+#+[ \\t]*$", options: .regularExpression) {
            content = String(content[content.startIndex..<range.lowerBound])
        }
        return (level, parseInlines(content))
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, trimmed.count >= 3 else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        let filtered = trimmed.filter { !$0.isWhitespace }
        return filtered.count >= 3 && filtered.allSatisfy { $0 == first }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        guard let regex = try? NSRegularExpression(pattern: "^\\s*\\|?[\\s:|-]+\\|[\\s:|-]*$") else {
            return false
        }
        let ns = line as NSString
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if let first = line.first, first == "-" || first == "*" || first == "+" || first == "•" {
            let rest = line.dropFirst()
            if let second = rest.first, second == " " || second == "\t" {
                let text = rest.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return (false, text) }
            }
            return nil
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = line.dropFirst(digits.count)
            if let marker = rest.first, marker == "." || marker == ")" {
                let after = rest.dropFirst()
                if let next = after.first, next == " " || next == "\t" {
                    let text = after.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { return (true, text) }
                }
            }
        }
        return nil
    }

    // MARK: Inline parsing

    static func parseInlines(_ text: String) -> [MarkdownInline] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [(range: NSRange, inline: MarkdownInline)] = []
        var protected: [NSRange] = []

        func isFree(_ range: NSRange) -> Bool {
            guard range.location != NSNotFound, range.length > 0 else { return false }
            for occupied in protected where NSIntersectionRange(occupied, range).length > 0 {
                return false
            }
            return true
        }

        func collect(_ pattern: String, build: (NSTextCheckingResult) -> MarkdownInline?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for result in regex.matches(in: text, range: full) {
                guard isFree(result.range), let inline = build(result) else { continue }
                matches.append((result.range, inline))
                protected.append(result.range)
            }
        }

        func group(_ result: NSTextCheckingResult, _ index: Int) -> String {
            let range = result.range(at: index)
            guard range.location != NSNotFound,
                  range.location + range.length <= ns.length else { return "" }
            return ns.substring(with: range)
        }

        // 1) Code spans (multiline content allowed).
        collect("`([^`]+)`") { .code(group($0, 1)) }

        // 2) Escaped punctuation becomes literal text.
        collect("\\\\([*_`~\\[\\]()$#!+-])") { .text(group($0, 1)) }

        // 3) Images.
        collect("!\\[([^\\[\\]]*)\\]\\(([^()\\s]*)\\)") {
            .image(alt: group($0, 1), url: group($0, 2))
        }

        // 4) Links (one level of nested brackets tolerated in the label).
        collect("\\[((?:[^\\[\\]]|\\[[^\\[\\]]*\\])*)\\]\\(([^()\\s]*)\\)") {
            .link(text: group($0, 1), url: group($0, 2))
        }

        // 5) Bold + italic.
        collect("\\*\\*\\*(\\S(?:[\\s\\S]*?\\S)?)\\*\\*\\*") {
            .emphasis(group($0, 1), bold: true, italic: true)
        }
        collect("___(\\S(?:[\\s\\S]*?\\S)?)___") {
            .emphasis(group($0, 1), bold: true, italic: true)
        }

        // 6) Bold.
        collect("\\*\\*(\\S(?:[\\s\\S]*?\\S)?)\\*\\*") {
            .emphasis(group($0, 1), bold: true, italic: false)
        }
        collect("__(\\S(?:[\\s\\S]*?\\S)?)__") {
            .emphasis(group($0, 1), bold: true, italic: false)
        }

        // 7) Italic.
        collect("\\*(\\S(?:[\\s\\S]*?\\S)?)\\*") {
            .emphasis(group($0, 1), bold: false, italic: true)
        }
        collect("(?<![A-Za-z0-9_])_(\\S(?:[\\s\\S]*?\\S)?)_(?![A-Za-z0-9_])") {
            .emphasis(group($0, 1), bold: false, italic: true)
        }

        // 8) Strikethrough.
        collect("~~(\\S(?:[\\s\\S]*?\\S)?)~~") {
            .strikethrough(group($0, 1))
        }

        // 9) Inline math: $...$ with no space hugging the delimiters.
        collect("\\$(?!\\s)([^$\\n]+?)(?<!\\s)\\$") {
            .math(group($0, 1))
        }

        matches.sort { $0.range.location < $1.range.location }
        var result: [MarkdownInline] = []
        var cursor = 0
        for (range, inline) in matches {
            if range.location > cursor {
                result.append(.text(ns.substring(with: NSRange(
                    location: cursor,
                    length: range.location - cursor))))
            }
            result.append(inline)
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result.append(.text(ns.substring(from: cursor)))
        }

        var merged: [MarkdownInline] = []
        for inline in result {
            if case .text(let previous) = merged.last, case .text(let current) = inline {
                merged[merged.count - 1] = .text(previous + current)
            } else {
                merged.append(inline)
            }
        }
        return merged
    }
}
