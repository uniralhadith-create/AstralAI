import SwiftUI

// MARK: - Syntax highlighter (V5.0.0)

/// Lightweight regex-based syntax highlighting tuned for the dark terminal
/// code card in both light and dark app appearances.
enum SyntaxHighlighter {

    // MARK: Theme (high-contrast terminal palette)

    private static let keywordColor = Color(hex: 0xC4B5FD)
    private static let stringColor = Color(hex: 0x34D399)
    private static let commentColor = Color(hex: 0x8E8EA0)
    private static let numberColor = Color(hex: 0x67E8F9)
    private static let typeColor = Color(hex: 0xF472B6)
    private static let plainColor = Color(hex: 0xF5F5F7)

    // MARK: Token model

    private enum Kind: Equatable {
        case keyword
        case string
        case comment
        case number
        case type
        case key
    }

    private struct Token {
        let range: NSRange
        let kind: Kind
    }

    private enum CodeLanguage {
        case swift
        case python
        case javascript
        case json
        case bash
        case html
        case css
        case sql
        case generic
    }

    // MARK: Keyword sets

    private static let swiftKeywords: [String] = [
        "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "import", "init", "return", "if", "else", "guard", "switch", "case",
        "default", "for", "while", "break", "continue", "defer", "do", "try",
        "catch", "throw", "throws", "async", "await", "self", "super", "nil",
        "true", "false", "where", "in", "as", "is", "some", "any", "actor",
    ]

    private static let pythonKeywords: [String] = [
        "def", "class", "return", "if", "elif", "else", "for", "while", "break",
        "continue", "pass", "import", "from", "as", "with", "try", "except",
        "finally", "raise", "lambda", "yield", "in", "is", "not", "and", "or",
        "None", "True", "False", "self", "async", "await", "global", "nonlocal",
    ]

    private static let javascriptKeywords: [String] = [
        "function", "return", "if", "else", "for", "while", "do", "switch",
        "case", "default", "break", "continue", "const", "let", "var", "class",
        "extends", "new", "this", "typeof", "instanceof", "import", "export",
        "from", "async", "await", "try", "catch", "throw", "null", "undefined",
        "true", "false", "interface", "type", "void",
    ]

    private static let jsonKeywords: [String] = ["true", "false", "null"]

    private static let bashKeywords: [String] = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do",
        "done", "case", "esac", "in", "function", "return", "exit", "local",
        "export", "echo", "cd", "mkdir", "rm", "cp", "mv", "sudo", "apt",
        "pip", "npm", "git", "curl", "wget", "grep", "awk", "sed", "jq",
        "tar", "zip", "unzip", "chmod", "chown", "ps", "top", "kill",
    ]

    private static let cssKeywords: [String] = [
        "media", "import", "keyframes", "important", "from", "to", "and",
        "not", "only",
    ]

    private static let sqlKeywords: [String] = [
        "select", "from", "where", "insert", "into", "values", "update", "set",
        "delete", "create", "table", "drop", "alter", "join", "left", "right",
        "inner", "outer", "on", "group", "by", "order", "having", "limit",
        "offset", "as", "and", "or", "not", "null", "distinct", "primary",
        "key", "foreign", "references", "index", "unique", "between", "like",
        "exists", "union", "count", "avg", "sum", "min", "max",
    ]

    private static let genericKeywords: [String] = [
        "if", "else", "return", "function", "class", "let", "var", "const",
        "new", "import", "export", "from", "for", "while", "do", "switch",
        "case", "default", "break", "continue", "try", "catch", "throw",
        "def", "fn", "func", "struct", "enum", "interface", "public",
        "private", "static", "void", "null", "nil", "true", "false", "this",
        "self", "async", "await",
    ]

    // MARK: Public API

    static func highlight(_ code: String, language: String?) -> AttributedString {
        guard !code.isEmpty else { return AttributedString() }
        let lang = normalize(language)
        let tokens = tokenize(code, language: lang)
        return attributed(from: code, tokens: tokens)
    }

    // MARK: Language normalization

    private static func normalize(_ language: String?) -> CodeLanguage {
        let raw = (language ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch raw {
        case "swift":
            return .swift
        case "python", "py":
            return .python
        case "javascript", "js", "jsx", "mjs", "typescript", "ts", "tsx":
            return .javascript
        case "json":
            return .json
        case "bash", "sh", "shell", "zsh", "console", "terminal":
            return .bash
        case "html", "htm", "xml", "svg":
            return .html
        case "css", "scss", "less":
            return .css
        case "sql", "sqlite":
            return .sql
        default:
            return .generic
        }
    }

    private static func keywordSet(for language: CodeLanguage) -> [String] {
        switch language {
        case .swift: return swiftKeywords
        case .python: return pythonKeywords
        case .javascript: return javascriptKeywords
        case .json: return jsonKeywords
        case .bash: return bashKeywords
        case .css: return cssKeywords
        case .sql: return sqlKeywords
        case .html: return []
        case .generic: return genericKeywords
        }
    }

    // MARK: Tokenizer

    private static func tokenize(_ code: String, language: CodeLanguage) -> [Token] {
        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)
        var tokens: [Token] = []
        var occupied: [NSRange] = []

        func isFree(_ range: NSRange) -> Bool {
            guard range.length > 0 else { return false }
            for taken in occupied where NSIntersectionRange(taken, range).length > 0 {
                return false
            }
            return true
        }

        func constant(_ kind: Kind) -> (NSTextCheckingResult) -> Kind {
            { _ in kind }
        }

        func addMatches(of pattern: String, kind: @escaping (NSTextCheckingResult) -> Kind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: code, range: full) where isFree(match.range) {
                tokens.append(Token(range: match.range, kind: kind(match)))
                occupied.append(match.range)
            }
        }

        // --- Comments ---
        switch language {
        case .swift, .javascript, .css, .generic:
            addMatches(of: "//[^\\n]*", kind: constant(.comment))
            addMatches(of: "/\\*[\\s\\S]*?\\*/", kind: constant(.comment))
        case .python, .bash:
            addMatches(of: "#[^\\n]*", kind: constant(.comment))
        case .html:
            addMatches(of: "<!--[\\s\\S]*?-->", kind: constant(.comment))
        case .sql:
            addMatches(of: "--[^\\n]*", kind: constant(.comment))
            addMatches(of: "/\\*[\\s\\S]*?\\*/", kind: constant(.comment))
        case .json:
            break
        }

        // --- Strings ---
        switch language {
        case .python:
            addMatches(of: "\"\"\"[\\s\\S]*?\"\"\"", kind: constant(.string))
            addMatches(of: "'''[\\s\\S]*?'''", kind: constant(.string))
            addMatches(of: "\"(\\\\.|[^\"\\\\\\n])*\"", kind: constant(.string))
            addMatches(of: "'(\\\\.|[^'\\\\\\n])*'", kind: constant(.string))
        case .json:
            addMatches(of: "\"(\\\\.|[^\"\\\\\\n])*\"\\s*:", kind: constant(.key))
            addMatches(of: "\"(\\\\.|[^\"\\\\\\n])*\"", kind: constant(.string))
        case .html:
            addMatches(of: "\"(\\\\.|[^\"\\\\\\n])*\"", kind: constant(.string))
            addMatches(of: "'(\\\\.|[^'\\\\\\n])*'", kind: constant(.string))
        default:
            addMatches(of: "\"(\\\\.|[^\"\\\\\\n])*\"", kind: constant(.string))
            addMatches(of: "'(\\\\.|[^'\\\\\\n])*'", kind: constant(.string))
        }

        // --- Keywords ---
        let keywords = keywordSet(for: language)
        if !keywords.isEmpty {
            let alternation = keywords
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            let options: NSRegularExpression.Options = (language == .sql) ? [.caseInsensitive] : []
            if let regex = try? NSRegularExpression(pattern: "\\b(?:\(alternation))\\b", options: options) {
                for match in regex.matches(in: code, range: full) where isFree(match.range) {
                    tokens.append(Token(range: match.range, kind: .keyword))
                    occupied.append(match.range)
                }
            }
        }

        // --- Numbers ---
        addMatches(of: "\\b\\d+(?:\\.\\d+)?\\b", kind: constant(.number))

        // --- Language-specific structural tokens ---
        switch language {
        case .html:
            addMatches(of: "</?[A-Za-z][A-Za-z0-9-]*", kind: constant(.keyword))
            addMatches(of: "[A-Za-z_:][A-Za-z0-9_:-]*(?==)", kind: constant(.type))
        case .css:
            addMatches(of: "[-A-Za-z]+(?=\\s*:)", kind: constant(.type))
        case .swift, .python:
            addMatches(of: "\\b[A-Z][A-Za-z0-9_]*\\b", kind: constant(.type))
        default:
            break
        }

        return tokens
    }

    // MARK: Attribution

    private static func attributed(from code: String, tokens: [Token]) -> AttributedString {
        let ns = code as NSString
        let sorted = tokens.sorted { $0.range.location < $1.range.location }
        var result = AttributedString()
        var cursor = 0

        func append(_ substring: String, kind: Kind?) {
            guard !substring.isEmpty else { return }
            var piece = AttributedString(substring)
            var font = Font.system(size: 13, design: .monospaced)
            switch kind {
            case .keyword, .key:
                piece.foregroundColor = keywordColor
            case .string:
                piece.foregroundColor = stringColor
            case .comment:
                font = font.italic()
                piece.foregroundColor = commentColor
            case .number:
                piece.foregroundColor = numberColor
            case .type:
                piece.foregroundColor = typeColor
            case nil:
                piece.foregroundColor = plainColor
            }
            if kind == .keyword {
                font = font.bold()
            }
            piece.font = font
            result += piece
        }

        for token in sorted {
            guard token.range.location >= cursor else { continue }
            if token.range.location > cursor {
                append(
                    ns.substring(with: NSRange(
                        location: cursor,
                        length: token.range.location - cursor)),
                    kind: nil)
            }
            append(ns.substring(with: token.range), kind: token.kind)
            cursor = token.range.location + token.range.length
        }
        if cursor < ns.length {
            append(ns.substring(from: cursor), kind: nil)
        }
        return result
    }
}
