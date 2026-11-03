import SwiftUI
import UIKit

// MARK: - Code block (V5.0.0 — Liquid Glass Terminal Code Card)

/// Syntax-highlighted code block in a sleek dark terminal glass card with a
/// language pill, line count badge, and tactile copy-to-clipboard button.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    private var lineCount: Int {
        max(1, code.components(separatedBy: .newlines).count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                AIcon(
                    AstralIcons.fileCode,
                    size: 12,
                    strokeWidth: 2.2,
                    color: AstralTheme.orbGreen)

                Text((language ?? "code").uppercased())
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.85))

                Text("· \(lineCount)L")
                    .font(AstralTheme.mono(10))
                    .foregroundStyle(Color.white.opacity(0.42))

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 5) {
                        if copied {
                            AIcon(AstralIcons.check, size: 11, strokeWidth: 2.6, color: AstralTheme.orbGreen)
                            Text(L("common.copied", "Shared"))
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(AstralTheme.orbGreen)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text(L("common.copy", "Shared"))
                                .font(AstralTheme.mono(10.5).weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(copied
                    ? L("common.copied", "Shared")
                    : L("common.copy", "Shared")))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.04))

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Code body
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(AstralTheme.mono(13))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .padding(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.085, blue: 0.105),
                            Color(red: 0.055, green: 0.06, blue: 0.075),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 4)
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
