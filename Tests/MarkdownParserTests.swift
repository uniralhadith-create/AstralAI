import XCTest
@testable import AstralAI

/// Comprehensive unit tests for the Markdown block parser and the inline
/// parser that power the agent's rich output rendering. The pinned block
/// model covers headings, paragraphs, fenced code, quotes, lists, tables,
/// dividers and math blocks; the inline model covers text, emphasis,
/// code, links, images, math and strikethrough.
final class MarkdownParserTests: XCTestCase {

    // MARK: Helpers

    /// Joins the visible text of a run of inline nodes.
    private func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let s): return s
            case .emphasis(let s, _, _): return s
            case .code(let s): return s
            case .link(let text, _): return text
            case .image(let alt, _): return alt
            case .math(let s): return s
            case .strikethrough(let s): return s
            default: return ""
            }
        }.joined()
    }

    /// Plain .text runs only.
    private func textRuns(_ inlines: [MarkdownInline]) -> [String] {
        inlines.compactMap { inline -> String? in
            guard case .text(let s) = inline else { return nil }
            return s
        }
    }

    /// Emphasis contents matching the given bold/italic flags.
    private func emphasisTexts(_ inlines: [MarkdownInline], bold: Bool, italic: Bool) -> [String] {
        inlines.compactMap { inline -> String? in
            guard case .emphasis(let s, let isBold, let isItalic) = inline else { return nil }
            return (isBold == bold && isItalic == italic) ? s : nil
        }
    }

    /// Inline code contents.
    private func inlineCodes(_ inlines: [MarkdownInline]) -> [String] {
        inlines.compactMap { inline -> String? in
            guard case .code(let s) = inline else { return nil }
            return s
        }
    }

    // MARK: Headings

    func testHeadingLevelOne() {
        let blocks = MarkdownParser.parse("# Title")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let inlines) = blocks[0] else {
            return XCTFail("expected a heading block, got: \(blocks)")
        }
        XCTAssertEqual(level, 1)
        XCTAssertTrue(textRuns(inlines).contains { $0.contains("Title") })
    }

    func testHeadingLevelSix() {
        let blocks = MarkdownParser.parse("###### Six")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let inlines) = blocks[0] else {
            return XCTFail("expected a heading block, got: \(blocks)")
        }
        XCTAssertEqual(level, 6)
        XCTAssertTrue(textRuns(inlines).contains { $0.contains("Six") })
    }

    func testHeadingMiddleLevelWithInlineStyles() {
        let blocks = MarkdownParser.parse("## Sub **strong**")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let inlines) = blocks[0] else {
            return XCTFail("expected a heading block, got: \(blocks)")
        }
        XCTAssertEqual(level, 2)
        XCTAssertTrue(emphasisTexts(inlines, bold: true, italic: false).contains("strong"))
    }

    // MARK: Paragraph inlines

    func testParagraphWithAllInlineStyles() {
        let markdown = "This is **bold** and *italic* plus `code` with [link](https://x.com) and ![img](https://y.com/i.png) then ~~strike~~ plus $x^2$ done."
        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let inlines) = blocks[0] else {
            return XCTFail("expected a paragraph block, got: \(blocks)")
        }

        // Bold emphasis
        XCTAssertTrue(
            emphasisTexts(inlines, bold: true, italic: false).contains("bold"),
            "missing bold emphasis in: \(inlines)"
        )
        // Italic emphasis
        XCTAssertTrue(
            emphasisTexts(inlines, bold: false, italic: true).contains("italic"),
            "missing italic emphasis in: \(inlines)"
        )
        // Inline code
        XCTAssertTrue(inlineCodes(inlines).contains("code"), "missing inline code in: \(inlines)")
        // Link
        let hasLink = inlines.contains { inline in
            guard case .link(let text, let url) = inline else { return false }
            return text == "link" && url == "https://x.com"
        }
        XCTAssertTrue(hasLink, "missing link inline in: \(inlines)")
        // Image
        let hasImage = inlines.contains { inline in
            guard case .image(let alt, let url) = inline else { return false }
            return alt == "img" && url == "https://y.com/i.png"
        }
        XCTAssertTrue(hasImage, "missing image inline in: \(inlines)")
        // Strikethrough
        let hasStrike = inlines.contains { inline in
            guard case .strikethrough(let s) = inline else { return false }
            return s == "strike"
        }
        XCTAssertTrue(hasStrike, "missing strikethrough inline in: \(inlines)")
        // Inline math
        let hasMath = inlines.contains { inline in
            guard case .math(let s) = inline else { return false }
            return s == "x^2"
        }
        XCTAssertTrue(hasMath, "missing math inline in: \(inlines)")
        // Surrounding plain text survives
        let joined = plainText(inlines)
        XCTAssertTrue(joined.contains("This is"), "leading text lost: \(joined)")
        XCTAssertTrue(joined.contains("done."), "trailing text lost: \(joined)")
    }

    // MARK: Code blocks

    func testFencedCodeBlockWithSwiftLanguage() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("expected a code block, got: \(blocks)")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1")
    }

    func testFencedCodeBlockWithPython() {
        let blocks = MarkdownParser.parse("```python\nprint('hi')\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("expected a code block, got: \(blocks)")
        }
        XCTAssertEqual(language, "python")
        XCTAssertEqual(code, "print('hi')")
    }

    func testFencedCodeBlockWithoutLanguage() {
        let blocks = MarkdownParser.parse("```\nplain snippet\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("expected a code block, got: \(blocks)")
        }
        XCTAssertNil(language)
        XCTAssertEqual(code, "plain snippet")
    }

    func testMultiLineCodeBlockPreservesInnerLines() {
        let markdown = "```js\nconst a = 1;\nconst b = 2;\n```"
        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("expected a code block, got: \(blocks)")
        }
        XCTAssertEqual(language, "js")
        XCTAssertEqual(code, "const a = 1;\nconst b = 2;")
    }

    // MARK: Blockquote

    func testBlockquoteContainsFormattedParagraph() {
        let blocks = MarkdownParser.parse("> quoted **bold**")
        XCTAssertEqual(blocks.count, 1)
        guard case .quote(let inner) = blocks[0] else {
            return XCTFail("expected a quote block, got: \(blocks)")
        }
        XCTAssertEqual(inner.count, 1)
        guard case .paragraph(let inlines) = inner[0] else {
            return XCTFail("expected a paragraph inside the quote, got: \(inner)")
        }
        XCTAssertTrue(textRuns(inlines).contains { $0.contains("quoted") })
        XCTAssertTrue(emphasisTexts(inlines, bold: true, italic: false).contains("bold"))
    }

    // MARK: Lists

    func testUnorderedList() {
        let blocks = MarkdownParser.parse("- one\n- two")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("expected a list block, got: \(blocks)")
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(plainText(items[0]).trimmingCharacters(in: .whitespaces), "one")
        XCTAssertEqual(plainText(items[1]).trimmingCharacters(in: .whitespaces), "two")
    }

    func testOrderedList() {
        let blocks = MarkdownParser.parse("1. first\n2. second")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("expected a list block, got: \(blocks)")
        }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(plainText(items[0]).trimmingCharacters(in: .whitespaces), "first")
        XCTAssertEqual(plainText(items[1]).trimmingCharacters(in: .whitespaces), "second")
    }

    func testListItemsCarryInlineStyles() {
        let blocks = MarkdownParser.parse("- plain\n- **strong** item")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(_, let items) = blocks[0] else {
            return XCTFail("expected a list block, got: \(blocks)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(emphasisTexts(items[1], bold: true, italic: false).contains("strong"))
    }

    // MARK: Tables

    func testTableParsing() {
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let header, let rows) = blocks[0] else {
            return XCTFail("expected a table block, got: \(blocks)")
        }
        XCTAssertEqual(header, ["A", "B"])
        XCTAssertEqual(rows, [["1", "2"], ["3", "4"]])
    }

    // MARK: Dividers and math blocks

    func testStandaloneDivider() {
        let blocks = MarkdownParser.parse("---")
        XCTAssertEqual(blocks.count, 1)
        guard case .divider = blocks[0] else {
            return XCTFail("expected a divider block, got: \(blocks)")
        }
    }

    func testDividerBetweenParagraphs() {
        let blocks = MarkdownParser.parse("above\n\n---\n\nbelow")
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph = blocks[0], case .divider = blocks[1], case .paragraph = blocks[2] else {
            return XCTFail("expected [paragraph, divider, paragraph], got: \(blocks)")
        }
    }

    func testMathBlock() {
        let blocks = MarkdownParser.parse("$$E=mc^2$$")
        XCTAssertEqual(blocks.count, 1)
        guard case .mathBlock(let latex) = blocks[0] else {
            return XCTFail("expected a math block, got: \(blocks)")
        }
        XCTAssertEqual(latex, "E=mc^2")
    }

    // MARK: Paragraphs

    func testMultilineParagraphJoinsWithSpace() {
        let blocks = MarkdownParser.parse("first line\nsecond line")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let inlines) = blocks[0] else {
            return XCTFail("expected a single paragraph block, got: \(blocks)")
        }
        let joined = plainText(inlines)
        XCTAssertTrue(joined.contains("first line"), "first line lost: \(joined)")
        XCTAssertTrue(joined.contains("second line"), "second line lost: \(joined)")
        XCTAssertTrue(
            joined.contains("first line second line"),
            "soft-wrapped lines should be joined with a space, got: \(joined)"
        )
    }

    func testEmptyInputProducesNoBlocks() {
        XCTAssertTrue(MarkdownParser.parse("").isEmpty)
    }

    // MARK: parseInlines

    func testParseInlinesPlainTextIsSingleTextNode() {
        let inlines = MarkdownParser.parseInlines("hello world")
        XCTAssertEqual(inlines.count, 1)
        guard case .text(let s) = inlines[0] else {
            return XCTFail("expected a single text node, got: \(inlines)")
        }
        XCTAssertEqual(s, "hello world")
    }

    func testParseInlinesWithStyles() {
        let inlines = MarkdownParser.parseInlines("a *b* `c` [d](https://e.com)")
        XCTAssertTrue(emphasisTexts(inlines, bold: false, italic: true).contains("b"))
        XCTAssertTrue(inlineCodes(inlines).contains("c"))
        let hasLink = inlines.contains { inline in
            guard case .link(let text, let url) = inline else { return false }
            return text == "d" && url == "https://e.com"
        }
        XCTAssertTrue(hasLink, "missing link inline in: \(inlines)")
    }
}
