import XCTest
import Foundation
@testable import AstralAI

/// Unit tests for MathRenderer: LaTeX to AttributedString rendering based
/// on Unicode glyph substitution for the most common LaTeX commands used
/// in model output.
final class MathRendererTests: XCTestCase {

    /// Renders LaTeX and returns its plain text content.
    private func renderedText(_ latex: String) -> String {
        String(MathRenderer.rendered(latex).characters)
    }

    func testGreekLettersAreMappedToUnicode() {
        let text = renderedText("\\alpha + \\beta")
        XCTAssertTrue(text.contains("α"), "expected α in: \(text)")
        XCTAssertTrue(text.contains("β"), "expected β in: \(text)")
        XCTAssertTrue(text.contains("+"), "the plus sign should survive, got: \(text)")
    }

    func testTimesMapsToMultiplicationSign() {
        let text = renderedText("2 \\times 3")
        XCTAssertTrue(text.contains("×"), "expected × in: \(text)")
    }

    func testFracRendersParenthesizedNumeratorAndDenominator() {
        let text = renderedText("\\frac{a}{b}")
        XCTAssertTrue(text.contains("a)/(b"), "expected a)/(b in: \(text)")
    }

    func testSuperscriptUsesUnicodeExponent() {
        let text = renderedText("x^{2}")
        XCTAssertTrue(text.contains("²"), "expected ² in: \(text)")
    }

    func testSubscriptUsesUnicodeSubscript() {
        let text = renderedText("H_2O")
        XCTAssertTrue(text.contains("₂"), "expected ₂ in: \(text)")
    }

    func testPlainTextSurvives() {
        let text = renderedText("E=mc")
        XCTAssertTrue(text.contains("E"), "expected E in: \(text)")
        XCTAssertTrue(text.contains("mc"), "expected mc in: \(text)")
    }

    func testCombinedSymbols() {
        let text = renderedText("\\alpha \\times \\beta")
        XCTAssertTrue(text.contains("α"), "expected α in: \(text)")
        XCTAssertTrue(text.contains("×"), "expected × in: \(text)")
        XCTAssertTrue(text.contains("β"), "expected β in: \(text)")
    }

    func testRenderedOutputIsNonEmpty() {
        let attributed = MathRenderer.rendered("\\frac{a}{b}")
        XCTAssertFalse(attributed.characters.isEmpty)
    }
}
