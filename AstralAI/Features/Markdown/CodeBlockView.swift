import SwiftUI
import UIKit

// MARK: - Code block (V5.0.0 — System-Adaptive iOS 27 Liquid Glass Code Card)

/// Syntax-highlighted code block in a system-adaptive iOS 27 Liquid Glass
/// card, with a language badge, line count, and a Liquid Glass copy capsule.
/// Adapts automatically to Light and Dark mode.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    private var lineCount: Int {
        max(1, code.components(separatedBy: .newlines).count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AIcon(
                    AstralIcons.fileCode,
                    size: 12.5,
                    strokeWidth: 2.2,
                    color: AstralTheme.textSecondary)

                Text((language ?? "code").uppercased())
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(AstralTheme.textPrimary)

                Text("· \(lineCount)L")
                    .font(AstralTheme.mono(10))
                    .foregroundStyle(AstralTheme.textSecondary)

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 5) {
                        if copied {
                            AIcon(AstralIcons.check, size: 11, strokeWidth: 2.6, color: AstralTheme.success)
                            Text(L("common.copied", "Shared"))
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(AstralTheme.success)
                        } else {
                            AIcon(AstralIcons.file, size: 11, strokeWidth: 2.1, color: AstralTheme.textSecondary)
                            Text(L("common.copy", "Shared"))
                                .font(AstralTheme.mono(10.5).weight(.medium))
                                .foregroundStyle(AstralTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .liquidCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(copied
                    ? L("common.copied", "Shared")
                    : L("common.copy", "Shared")))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)

            Divider()
                .overlay(AstralTheme.separator)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(AstralTheme.mono(13))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .padding(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: AstralTheme.actionFill.opacity(0.04))
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.smooth(duration: 0.25)) {
                copied = false
            }
        }
    }
}
