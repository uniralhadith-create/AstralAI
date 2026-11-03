import SwiftUI

// MARK: - Math renderer

/// Converts the LaTeX notation agents typically emit into Unicode-rich,
/// serif-italic attributed text. A pragmatic pipeline (fractions, roots,
/// greek letters, operators, super/subscripts) — not a full TeX engine.
enum MathRenderer {

    // MARK: Command tables

    /// LaTeX commands mapped to Unicode glyphs.
    private static let commandMap: [String: String] = [
        // Greek lowercase
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "pi": "π", "rho": "ρ", "sigma": "σ", "varsigma": "ς", "tau": "τ",
        "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ",
        "omega": "ω",
        // Greek capitals
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators and relations
        "times": "×", "div": "÷", "pm": "±", "mp": "∓", "cdot": "·",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "infty": "∞", "sum": "∑", "prod": "∏",
        "int": "∫", "partial": "∂", "rightarrow": "→", "to": "→",
        "Rightarrow": "⇒", "leftarrow": "←", "Leftarrow": "⇐",
        "leftrightarrow": "↔", "Leftrightarrow": "⇔", "in": "∈",
        "forall": "∀", "exists": "∃", "land": "∧", "lor": "∨", "neg": "¬",
        "circ": "∘", "prime": "′", "degree": "°", "emptyset": "∅",
        "subset": "⊂", "supset": "⊃", "cup": "∪", "cap": "∩",
    ]

    private static let superscriptTable: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ",
    ]

    private static let subscriptTable: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "(": "₍", ")": "₎",
        "n": "ₙ", "p": "ₚ", "a": "ₐ", "e": "ₑ", "o": "ₒ",
        "x": "ₓ", "k": "ₖ", "m": "ₘ", "i": "ᵢ", "j": "ⱼ",
        "r": "ᵣ", "u": "ᵤ", "v": "ᵥ", "t": "ₜ",
    ]

    // MARK: Public API

    /// Renders a LaTeX fragment as serif-italic attributed text.
    static func rendered(_ latex: String, size: CGFloat = 15) -> AttributedString {
        var text = latex.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fractions: \frac{a}{b} -> (a)/(b). Flat braces, best-effort nesting
        // by iterating a few passes.
        for _ in 0..<4 {
            let next = replacing(text, pattern: "\\\\(?:d|t)?frac\\{([^{}]*)\\}\\{([^{}]*)\\}") { groups in
                let numerator = groups.count > 0 ? groups[0] : ""
                let denominator = groups.count > 1 ? groups[1] : ""
                return "(\(numerator))/(\(denominator))"
            }
            if next == text { break }
            text = next
        }

        // Roots: \sqrt{x} and \sqrt[n]{x} -> √(x)
        text = replacing(text, pattern: "\\\\sqrt(?:\\[[^\\]]*\\])?\\{([^{}]*)\\}") { groups in
            let content = groups.first ?? ""
            return "√(\(content))"
        }

        // Known commands -> Unicode symbols; unknown \commands lose the
        // backslash so "\begin" reads as "begin".
        text = replacingCommands(text, map: commandMap)

        // Superscripts: ^{d} or ^d
        text = replacing(text, pattern: "\\^\\{([^{}]*)\\}") { groups in
            mapped(groups.first ?? "", table: superscriptTable, prefix: "^")
        }
        text = replacing(text, pattern: "\\^([A-Za-z0-9+\\-()])") { groups in
            mapped(groups.first ?? "", table: superscriptTable, prefix: "^")
        }

        // Subscripts: _{d} or _d
        text = replacing(text, pattern: "_\\{([^{}]*)\\}") { groups in
            mapped(groups.first ?? "", table: subscriptTable, prefix: "_")
        }
        text = replacing(text, pattern: "_([A-Za-z0-9+\\-()])") { groups in
            mapped(groups.first ?? "", table: subscriptTable, prefix: "_")
        }

        // Leftover braces and LaTeX line breaks.
        text = text.replacingOccurrences(of: "{", with: "")
        text = text.replacingOccurrences(of: "}", with: "")
        text = text.replacingOccurrences(of: "\\\\", with: " ")
        text = text.replacingOccurrences(of: "\\", with: "")
        text = text.replacingOccurrences(of: "\n", with: " ")

        var attributed = AttributedString(text)
        attributed.font = Font.system(size: size, design: .serif).italic()
        attributed.foregroundColor = AstralTheme.textPrimary
        return attributed
    }

    // MARK: Helpers

    /// Regex replacement that never re-scans its own output. `transform`
    /// receives the capture groups (first group first).
    private static func replacing(
        _ input: String,
        pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var result = ""
        var cursor = 0
        for match in matches {
            guard match.range.location >= cursor else { continue }
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor))
            }
            var groups: [String] = []
            for index in 1..<max(match.numberOfRanges, 1) {
                let groupRange = match.range(at: index)
                if groupRange.location != NSNotFound {
                    groups.append(ns.substring(with: groupRange))
                }
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    /// Replaces every `\command` occurrence using `map`; unknown commands
    /// keep their bare name. Matches are replaced back-to-front so earlier
    /// ranges stay valid.
    private static func replacingCommands(_ input: String, map: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\\\([a-zA-Z]+)") else {
            return input
        }
        let ns = NSMutableString(string: input)
        let matches = regex.matches(
            in: input,
            range: NSRange(location: 0, length: (input as NSString).length))
        for match in matches.reversed() {
            guard match.range.location != NSNotFound,
                  let fullRange = Range(match.range, in: input) else { continue }
            let command = String(input[fullRange].dropFirst())
            let replacement = map[command] ?? command
            ns.replaceCharacters(in: match.range, with: replacement)
        }
        return ns as String
    }

    /// Maps content character-by-character through a glyph table. When any
    /// character has no glyph, the content is kept with the original prefix
    /// character (e.g. "^ab" stays "^ab").
    private static func mapped(_ content: String, table: [Character: String], prefix: String) -> String {
        guard !content.isEmpty else { return "" }
        var glyphs: [String] = []
        for character in content {
            guard let glyph = table[character] else { return "\(prefix)\(content)" }
            glyphs.append(glyph)
        }
        return glyphs.joined()
    }
}
