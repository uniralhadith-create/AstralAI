import SwiftUI
import UIKit

// MARK: - Markdown document view (V5.0.0 — iOS 27 Liquid Glass Editorial Markdown)

/// Renders a full markdown document as native SwiftUI views inside the
/// V5 Liquid Glass design language.
///
/// V5.0.0 Upgrades:
/// - **Natural AttributedString paragraphs**: Inline links, bold, italic,
///   strikethrough, inline code chips, and math now flow inside a single
///   native `Text(AttributedString)` whenever no block image is present —
///   fixing word-splitting, RTL Arabic shaping, and baseline alignment.
/// - **Adaptive Light & Dark Mode surfaces**: Tables, blockquotes, callouts,
///   and inline code chips adapt cleanly in both light and dark mode.
/// - **Rich Table Cell Inlines & Copy**: Table cells parse inline markdown
///   (`**bold**`, `` `code` ``, `[links](url)`) and tables include a one-tap
///   copy button.
/// - **Task List Checkboxes & Callout Admonitions**: `- [x]` and `- [ ]`
///   render with crisp vector checkboxes, and `> [!NOTE]` / `> [!WARNING]`
///   render as semantic callout cards.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    init(_ text: String) {
        blocks = MarkdownParser.parse(text)
    }

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Block view

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var baseFont: Font = AstralTheme.body(15.5)
    var baseColor: Color = AstralTheme.textPrimary

    var body: some View {
        switch block {
        case .heading(let level, let inlines):
            heading(level: level, inlines: inlines)

        case .paragraph(let inlines):
            InlineFlowView(inlines: inlines, font: baseFont, color: baseColor)

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .quote(let inner):
            quoteView(inner)

        case .list(let ordered, let items):
            listView(ordered: ordered, items: items)

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .divider:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AstralTheme.separator.opacity(0.2),
                            AstralTheme.separator,
                            AstralTheme.separator.opacity(0.2),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing))
                .frame(height: 1)
                .padding(.vertical, 2)

        case .mathBlock(let latex):
            Text(MathRenderer.rendered(latex, size: 16))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Headings

    @ViewBuilder
    private func heading(level: Int, inlines: [MarkdownInline]) -> some View {
        switch level {
        case 1:
            VStack(alignment: .leading, spacing: 6) {
                InlineFlowView(inlines: inlines, font: AstralTheme.title(22), color: AstralTheme.textPrimary)
                Rectangle()
                    .fill(AstralTheme.separator.opacity(0.8))
                    .frame(height: 1)
            }
            .padding(.top, 4)
        case 2:
            InlineFlowView(inlines: inlines, font: AstralTheme.title(19), color: baseColor)
                .padding(.top, 3)
        case 3:
            InlineFlowView(inlines: inlines, font: AstralTheme.headline(16.5), color: baseColor)
                .padding(.top, 2)
        default:
            InlineFlowView(inlines: inlines, font: AstralTheme.headline(15.5), color: AstralTheme.textSecondary)
        }
    }

    // MARK: Quotes & Callouts

    @ViewBuilder
    private func quoteView(_ inner: [MarkdownBlock]) -> some View {
        let callout = Self.detectCallout(in: inner)
        let accent = callout?.color ?? AstralTheme.accent

        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3.5)

            VStack(alignment: .leading, spacing: 8) {
                if let callout {
                    HStack(spacing: 6) {
                        AIcon(callout.icon, size: 13, strokeWidth: 2.3, color: accent)
                        Text(callout.label)
                            .font(AstralTheme.headline(12.5))
                            .foregroundStyle(accent)
                    }
                }

                ForEach(Array(inner.enumerated()), id: \.offset) { _, innerBlock in
                    MarkdownBlockView(
                        block: innerBlock,
                        baseFont: AstralTheme.body(14.5),
                        baseColor: AstralTheme.textPrimary.opacity(0.88))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AstralTheme.surfaceSecondary.opacity(0.65)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AstralTheme.separator.opacity(0.8), lineWidth: 0.9))
    }

    private struct CalloutSpec {
        let label: String
        let icon: String
        let color: Color
    }

    private static func detectCallout(in blocks: [MarkdownBlock]) -> CalloutSpec? {
        guard case .paragraph(let inlines) = blocks.first,
              case .text(let firstText) = inlines.first else { return nil }
        let upper = firstText.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.hasPrefix("[!NOTE]") || upper.hasPrefix("NOTE:") {
            return CalloutSpec(label: "Note", icon: AstralIcons.sparkles, color: AstralTheme.accent)
        }
        if upper.hasPrefix("[!TIP]") || upper.hasPrefix("TIP:") {
            return CalloutSpec(label: "Tip", icon: AstralIcons.zap, color: AstralTheme.orbGreen)
        }
        if upper.hasPrefix("[!WARNING]") || upper.hasPrefix("[!IMPORTANT]") || upper.hasPrefix("WARNING:") {
            return CalloutSpec(label: "Important", icon: AstralIcons.shield, color: AstralTheme.warning)
        }
        return nil
    }

    // MARK: Lists & Task Checkboxes

    @ViewBuilder
    private func listView(ordered: Bool, items: [[MarkdownInline]]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, inlines in
                let taskState = Self.extractTaskCheckbox(from: inlines)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let checked = taskState.checked {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .fill(checked ? AstralTheme.orbGreen : AstralTheme.surfaceSecondary)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        .stroke(
                                            checked ? AstralTheme.orbGreen : AstralTheme.separator,
                                            lineWidth: 1.2))
                            if checked {
                                AIcon(AstralIcons.check, size: 10, strokeWidth: 3.0, color: .black)
                            }
                        }
                        .offset(y: 2)
                    } else if ordered {
                        Text("\(index + 1).")
                            .font(AstralTheme.mono(13).weight(.bold))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .frame(minWidth: 20, alignment: .trailing)
                    } else {
                        Circle()
                            .fill(AstralTheme.textPrimary.opacity(0.65))
                            .frame(width: 5.5, height: 5.5)
                            .offset(y: -2)
                            .padding(.leading, 4)
                    }

                    InlineFlowView(
                        inlines: taskState.cleanedInlines,
                        font: baseFont,
                        color: taskState.checked == true ? AstralTheme.textSecondary : baseColor)
                }
            }
        }
    }

    private static func extractTaskCheckbox(
        from inlines: [MarkdownInline]
    ) -> (checked: Bool?, cleanedInlines: [MarkdownInline]) {
        guard let first = inlines.first, case .text(let raw) = first else {
            return (nil, inlines)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            var updated = inlines
            updated[0] = .text(String(trimmed.dropFirst(4)))
            return (true, updated)
        }
        if trimmed.hasPrefix("[ ] ") {
            var updated = inlines
            updated[0] = .text(String(trimmed.dropFirst(4)))
            return (false, updated)
        }
        return (nil, inlines)
    }
}

// MARK: - Table (V5 Liquid Glass Table with Inline Formatting & Copy)

private struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar with table label + copy action
            HStack {
                HStack(spacing: 6) {
                    AIcon(AstralIcons.table, size: 12, strokeWidth: 2.2, color: AstralTheme.textSecondary)
                    Text("\(rows.count) × \(header.count)")
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
                Spacer()
                Button(action: copyTableAsMarkdown) {
                    HStack(spacing: 4) {
                        if copied {
                            AIcon(AstralIcons.check, size: 11, strokeWidth: 2.5, color: AstralTheme.success)
                            Text(L("common.copied", "Shared"))
                                .font(AstralTheme.mono(10).weight(.semibold))
                                .foregroundStyle(AstralTheme.success)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AstralTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AstralTheme.surfaceSecondary.opacity(0.85))

            Divider().overlay(AstralTheme.separator)

            ScrollView(.horizontal, showsIndicators: false) {
                tableGrid
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AstralTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(AstralTheme.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var tableGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    headerCell(cell)
                }
            }
            .background(AstralTheme.surfaceSecondary.opacity(0.55))

            Divider().overlay(AstralTheme.separator)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(header.indices), id: \.self) { column in
                        bodyCell(
                            row.indices.contains(column) ? row[column] : "",
                            rowIndex: rowIndex)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Divider().overlay(AstralTheme.separator.opacity(0.5))
                }
            }
        }
    }

    private func headerCell(_ cell: String) -> some View {
        let inlines = MarkdownParser.parseInlines(cell)
        return InlineFlowView(
            inlines: inlines,
            font: AstralTheme.headline(12.5),
            color: AstralTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 108, maxWidth: 240, alignment: .leading)
    }

    private func bodyCell(_ cell: String, rowIndex: Int) -> some View {
        let inlines = MarkdownParser.parseInlines(cell)
        return InlineFlowView(
            inlines: inlines,
            font: AstralTheme.body(12.5),
            color: AstralTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8.5)
            .frame(minWidth: 108, maxWidth: 240, alignment: .leading)
            .background(
                rowIndex % 2 == 1
                    ? AstralTheme.surfaceSecondary.opacity(0.28)
                    : Color.clear)
    }

    private func copyTableAsMarkdown() {
        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}

// MARK: - Inline flow (V5 Unified AttributedString + Image Segments)

private enum InlineSegment {
    case text(AttributedString)
    case link(text: String, url: String)
    case image(alt: String, url: String)
}

/// Renders a sequence of markdown inlines.
///
/// V5 improvement: When a paragraph or list item contains no inline images,
/// the entire inline sequence (including clickable links, inline code,
/// bold/italic, and math) is rendered as a single unified `Text(AttributedString)`
/// with proper line spacing — ensuring flawless word wrapping and Arabic/English
/// bidirectional layout!
struct InlineFlowView: View {
    let inlines: [MarkdownInline]
    let font: Font
    let color: Color?

    @Environment(\.openURL) private var openURL

    init(inlines: [MarkdownInline], font: Font, color: Color? = AstralTheme.textPrimary) {
        self.inlines = inlines
        self.font = font
        self.color = color
    }

    private var hasImages: Bool {
        inlines.contains {
            if case .image = $0 { return true }
            return false
        }
    }

    var body: some View {
        if !hasImages {
            Text(Self.unifiedAttributedString(from: inlines, font: font, color: color))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            let segments = Self.segments(from: inlines, font: font, color: color)
            MarkdownFlowLayout(spacing: 4, lineSpacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Combines all non-image inlines (including `.link`) into one rich
    /// `AttributedString` so SwiftUI renders the paragraph natively without
    /// breaking lines around links or inline code.
    private static func unifiedAttributedString(
        from inlines: [MarkdownInline],
        font: Font,
        color: Color?
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .link(let text, let url):
                var linkRun = styled(text, font: font.weight(.medium), color: AstralTheme.accent)
                linkRun.underlineStyle = .single
                if let target = URL(string: url) {
                    linkRun.link = target
                }
                result += linkRun
            default:
                result += run(for: inline, font: font, color: color)
            }
        }
        return result
    }

    // MARK: Segments

    private static func segments(
        from inlines: [MarkdownInline],
        font: Font,
        color: Color?
    ) -> [InlineSegment] {
        var accumulator = AttributedString()
        var segments: [InlineSegment] = []

        func flush() {
            if !accumulator.characters.isEmpty {
                segments.append(.text(accumulator))
                accumulator = AttributedString()
            }
        }

        for inline in inlines {
            switch inline {
            case .link(let text, let url):
                flush()
                segments.append(.link(text: text, url: url))
            case .image(let alt, let url):
                flush()
                segments.append(.image(alt: alt, url: url))
            default:
                accumulator += run(for: inline, font: font, color: color)
            }
        }
        flush()
        return segments
    }

    /// Builds the attributed text for a single non-tappable inline.
    static func run(
        for inline: MarkdownInline,
        font: Font,
        color: Color?
    ) -> AttributedString {
        switch inline {
        case .text(let string):
            return styled(string, font: font, color: color)
        case .emphasis(let string, let bold, let italic):
            return styled(string, font: font, color: color, bold: bold, italic: italic)
        case .code(let string):
            var attributed = styled(
                "\u{00A0}\(string)\u{00A0}",
                font: AstralTheme.mono(13).weight(.medium),
                color: AstralTheme.textPrimary)
            attributed.backgroundColor = AstralTheme.actionFill.opacity(0.11)
            return attributed
        case .strikethrough(let string):
            return styled(string, font: font, color: color, strike: true)
        case .math(let latex):
            return MathRenderer.rendered(latex, size: 14)
        case .link, .image:
            return AttributedString()
        }
    }

    private static func styled(
        _ string: String,
        font: Font,
        color: Color?,
        bold: Bool = false,
        italic: Bool = false,
        strike: Bool = false
    ) -> AttributedString {
        var attributed = AttributedString(string)
        var resolved = font
        if bold { resolved = resolved.bold() }
        if italic { resolved = resolved.italic() }
        attributed.font = resolved
        if let color {
            attributed.foregroundColor = color
        }
        if strike {
            attributed.strikethroughStyle = Text.LineStyle(pattern: .solid)
        }
        return attributed
    }

    // MARK: Segment views

    @ViewBuilder
    private func segmentView(_ segment: InlineSegment) -> some View {
        switch segment {
        case .text(let attributed):
            Text(attributed)
                .textSelection(.enabled)
        case .link(let text, let url):
            Button {
                if let target = URL(string: url) {
                    openURL(target)
                }
            } label: {
                Text(text)
                    .font(font)
                    .underline()
                    .foregroundStyle(AstralTheme.auroraCyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: url))
        case .image(let alt, let url):
            imageSegment(alt: alt, url: url)
        }
    }

    @ViewBuilder
    private func imageSegment(alt: String, url: String) -> some View {
        if let target = URL(string: url) {
            AsyncImage(url: target) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty:
                    ZStack {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                case .failure:
                    AIcon(AstralIcons.image, size: 26, strokeWidth: 1.8, color: AstralTheme.moonDust)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text(verbatim: alt))
        } else {
            Text(alt)
                .font(font)
                .foregroundStyle(AstralTheme.textSecondary)
        }
    }
}

// MARK: - Flow layout

private struct MarkdownFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated()
        where index < arrangement.positions.count {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + arrangement.positions[index].x,
                    y: bounds.minY + arrangement.positions[index].y),
                proposal: ProposedViewSize(
                    width: arrangement.sizes[index].width,
                    height: nil))
        }
    }

    private struct Arrangement {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        let width = maxWidth.isFinite ? maxWidth : usedWidth
        let height = lineHeight > 0 ? y + lineHeight : 0
        return Arrangement(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: width, height: height))
    }
}
