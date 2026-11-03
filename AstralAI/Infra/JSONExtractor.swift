import Foundation

// MARK: - JSON extraction

/// Locates and decodes the first complete JSON value embedded in free-form
/// model output (plans, structured replies, fenced code blocks). Markdown
/// fences and surrounding prose are skipped while scanning; braces and
/// escapes inside string literals never terminate the value prematurely.
enum JSONExtractor {

    /// Returns the raw bytes of the first complete JSON object or array
    /// found in the text, or nil when there is none.
    static func firstJSON(in text: String) -> Data? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if escaped {
                // Previous character was a backslash inside a string:
                // this character is consumed verbatim.
                escaped = false
            } else if inString && character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" || character == "[" {
                    depth += 1
                } else if character == "}" || character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let substring = String(text[start...index])
                        return substring.data(using: .utf8)
                    }
                }
            }

            index = text.index(after: index)
        }
        return nil
    }

    /// Extracts the first JSON value from the text and decodes it as `T`.
    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = firstJSON(in: text) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
