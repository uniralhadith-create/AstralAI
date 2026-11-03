import XCTest
import SwiftUI
@testable import AstralAI

/// Unit tests for SyntaxHighlighter: token coloring for fenced code
/// blocks with graceful fallbacks. The critical property under test is
/// that highlighting never loses or mutates the source text; coloring is
/// asserted on top of that guarantee.
final class SyntaxHighlighterTests: XCTestCase {

    /// A run counts as colored when it carries a SwiftUI foreground color.
    /// (Uses the typed key-path subscript — the only Runs.Element API that
    /// type-checks reliably across SDK versions.)
    private func isColored(_ run: AttributedString.Runs.Element) -> Bool {
        run.attributes[keyPath: \.swiftUI.foregroundColor] != nil
    }

    /// The plain text content of a single attribute run.
    private func runText(
        _ run: AttributedString.Runs.Element,
        of source: AttributedString
    ) -> String {
        String(source[run.range].characters)
    }

    func testSwiftHighlightPreservesTextAndColorsKeywords() {
        let code = "let x = \"hi\" // note"
        let attributed = SyntaxHighlighter.highlight(code, language: "swift")

        // Critical assertion: the highlighted text is identical to the
        // source code, character for character.
        XCTAssertEqual(String(attributed.characters), code)

        // Highlighting splits the code into multiple attribute runs.
        XCTAssertGreaterThanOrEqual(
            attributed.runs.count, 2,
            "expected multiple attribute runs, got \(attributed.runs.count)"
        )

        // At least one run is colored.
        XCTAssertTrue(
            attributed.runs.contains(where: isColored),
            "expected at least one colored run"
        )

        // The "let" keyword has its own run and carries a color.
        let keywordRuns = attributed.runs.filter {
            runText($0, of: attributed) == "let"
        }
        XCTAssertFalse(keywordRuns.isEmpty, "expected a dedicated run for the keyword 'let'")
        XCTAssertTrue(
            keywordRuns.contains(where: isColored),
            "the keyword 'let' should carry a foreground color"
        )
    }

    func testSwiftMultiLinePreservesText() {
        let code = "func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}"
        let attributed = SyntaxHighlighter.highlight(code, language: "swift")
        XCTAssertEqual(String(attributed.characters), code)
    }

    func testJSONHighlightPreservesTextAndColors() {
        let code = "{\"key\": [1, true, null], \"other\": \"value\"}"
        let attributed = SyntaxHighlighter.highlight(code, language: "json")
        XCTAssertEqual(String(attributed.characters), code)
        XCTAssertGreaterThanOrEqual(attributed.runs.count, 2)
        XCTAssertTrue(attributed.runs.contains(where: isColored))
    }

    func testPythonHighlightPreservesText() {
        let code = "def greet(name):\n    return 'hi ' + name"
        let attributed = SyntaxHighlighter.highlight(code, language: "python")
        XCTAssertEqual(String(attributed.characters), code)
    }

    func testUnknownLanguageFallsBackToPlainPreservation() {
        let code = "mystery syntax :<> sample"
        let attributed = SyntaxHighlighter.highlight(code, language: "not-a-real-language")
        XCTAssertEqual(String(attributed.characters), code)
    }

    func testNilLanguageFallsBackToPlainPreservation() {
        let code = "plain snippet with no language"
        let attributed = SyntaxHighlighter.highlight(code, language: nil)
        XCTAssertEqual(String(attributed.characters), code)
    }
}
