import SwiftUI
import UIKit

// MARK: - Message row (V5 Liquid Glass Chat)

/// Dispatches a single conversation message to the right presentation
/// (user bubble, assistant text, tool chip) by its role. System messages
/// stay hidden.
struct MessageRow: View {
    let message: ChatMessage

    init(_ message: ChatMessage) {
        self.message = message
    }

    var body: some View {
        switch message.role {
        case .user:
            UserBubble(
                text: message.content,
                images: message.images ?? [],
                attachments: message.attachments ?? [])
        case .assistant:
            AssistantCard(message: message)
        case .tool:
            if message.name == BrowserScreenshotTool.toolName,
               let capture = message.images?.first {
                ScreenshotCard(image: capture)
            } else {
                EmptyView()
            }
        case .system:
            EmptyView()
        }
    }
}

// MARK: - Screenshot card (V5 Liquid Glass)

/// A screenshot the agent captured for the user — the page it is on,
/// delivered as an image card. Glass frame, camera caption bar, and a
/// tap that opens the full-screen viewer with pinch zoom.
struct ScreenshotCard: View {
    let image: MessageImage

    @State private var ui: UIImage?
    @State private var zoomed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                AIcon(
                    AstralIcons.image,
                    size: 14,
                    strokeWidth: 2.1,
                    color: AstralTheme.orbGreen)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AstralTheme.surfaceSecondary))

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("chat.screenshot.title", "Chat"))
                        .font(AstralTheme.headline(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text(L("chat.screenshot.subtitle", "Chat"))
                        .font(AstralTheme.body(11))
                        .foregroundStyle(AstralTheme.textSecondary)
                }

                Spacer(minLength: 6)

                AIcon(
                    AstralIcons.externalLink,
                    size: 13,
                    strokeWidth: 2.2,
                    color: AstralTheme.textSecondary)
            }

            Button {
                zoomed = true
            } label: {
                Group {
                    if let ui {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(AstralTheme.separator)
                            .shimmer(cornerRadius: 16)
                    }
                }
                .frame(height: 232)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AstralTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        .accessibilityLabel(Text(L("chat.screenshot.a11y", "Chat")))
        .task {
            ui = MediaStore.uiImage(image, thumbnailMax: 1000)
        }
        .fullScreenCover(isPresented: $zoomed) {
            ScreenshotViewer(image: ui)
        }
    }
}

/// Full-screen viewer for a delivered screenshot: dark stage, aspect-fit
/// image with pinch zoom, a glass close control and share.
struct ScreenshotViewer: View {
    let image: UIImage?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LocalizationManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                MagnificationImage(image: image)
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    GlassCloseButton { dismiss() }
                    Spacer()
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(
                                L("chat.screenshot.title", "Chat"),
                                image: Image(uiImage: image))) {
                            AIcon(
                                AstralIcons.share,
                                size: 16,
                                strokeWidth: 2.2,
                                color: .white)
                                .frame(width: 40, height: 40)
                                .liquidGlass(in: Circle(), interactive: true)
                                .contentShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                Spacer()
            }
        }
        .environment(\.layoutDirection, language.layoutDirection)
    }
}

/// Aspect-fit image with pinch-to-zoom and drag-when-zoomed.
private struct MagnificationImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(6, max(1, lastScale * value))
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.01 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        })
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.01 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        })
        }
    }
}

// MARK: - User bubble (V5 iOS 27 Liquid Glass Bubble)

/// Trailing-aligned iOS 27 Liquid Glass bubble for user messages:
/// refractive glass surface with specular top rim, subtle elevation,
/// image thumbnails and file chips stacked cleanly above the text.
struct UserBubble: View {
    let text: String
    let images: [MessageImage]
    var attachments: [MessageAttachment] = []

    init(text: String, images: [MessageImage], attachments: [MessageAttachment] = []) {
        self.text = text
        self.images = images
        self.attachments = attachments
    }

    var body: some View {
        HStack {
            Spacer(minLength: 44)

            VStack(alignment: .trailing, spacing: 8) {
                if !attachments.isEmpty {
                    attachmentChips
                }
                if !images.isEmpty {
                    imageGrid
                }
                if !text.isEmpty {
                    Text(text)
                        .font(AstralTheme.body(16))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: 324, alignment: .trailing)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                tint: AstralTheme.userBubbleFill.opacity(0.65),
                interactive: false)
        }
        .textSelection(.enabled)
    }

    /// Compact file chips (vector icon + name) shown above the bubble text.
    private var attachmentChips: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(attachments) { file in
                HStack(spacing: 6) {
                    AIcon(
                        AstralIcons.file,
                        size: 11,
                        strokeWidth: 2.3,
                        color: AstralTheme.textPrimary.opacity(0.8))
                    Text(file.name)
                        .font(AstralTheme.headline(12))
                        .lineLimit(1)
                }
                .foregroundStyle(AstralTheme.textPrimary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        let chunked = stride(from: 0, to: images.count, by: 2).map {
            Array(images[$0..<min($0 + 2, images.count)])
        }
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(chunked.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { image in
                        BubbleImage(image: image)
                    }
                }
            }
        }
    }
}

/// One image inside a user bubble.
private struct BubbleImage: View {
    let image: MessageImage
    @State private var ui: UIImage?

    var body: some View {
        Group {
            if let ui {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AstralTheme.separator)
                    .shimmer(cornerRadius: 16)
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        .task {
            ui = MediaStore.uiImage(image, thumbnailMax: 320)
        }
    }
}

// MARK: - Assistant message (V5 Liquid Glass Header + Copy Action)

/// Full-width assistant reply rendered in V5 Markdown with an author header
/// badge and one-tap copy button. Empty content renders nothing.
struct AssistantCard: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        if !message.content.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AstralTheme.actionFill.opacity(0.08))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.7))
                        Image("AstralMark")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 15, height: 15)
                    }
                    .accessibilityHidden(true)

                    Text("Astral")
                        .font(AstralTheme.headline(12.5))
                        .foregroundStyle(AstralTheme.textSecondary)

                    Spacer(minLength: 4)

                    Button {
                        UIPasteboard.general.string = message.content
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
                    } label: {
                        HStack(spacing: 4) {
                            if copied {
                                AIcon(AstralIcons.check, size: 11, strokeWidth: 2.5, color: AstralTheme.success)
                                Text(L("common.copied", "Shared"))
                                    .font(AstralTheme.mono(10).weight(.semibold))
                                    .foregroundStyle(AstralTheme.success)
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AstralTheme.textSecondary.opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.05))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L("common.copy", "Shared")))
                }

                MarkdownView(message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Tool chip

/// Compact expandable row showing a tool invocation and its output.
struct ToolChip: View {
    let message: ChatMessage

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    AIcon(
                        AstralIcons.terminal,
                        size: 12,
                        strokeWidth: 2.2,
                        color: AstralTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AstralTheme.surfaceSecondary))

                    Text(message.name ?? L("chat.tool", "Chat"))
                        .font(AstralTheme.mono(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    AIcon(
                        AstralIcons.chevronDown,
                        size: 11,
                        strokeWidth: 2.2,
                        color: AstralTheme.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            Group {
                if expanded {
                    Text(message.content)
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .textSelection(.disabled)
                }
            }
            .font(AstralTheme.mono(12))
            .foregroundStyle(AstralTheme.textSecondary)
            .lineLimit(expanded ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.25), value: expanded)
    }
}

// MARK: - Streaming view

/// Live view for the assistant's in-flight response: plain markdown with a
/// typing caret and a subtle glass thinking pill before the first token arrives.
struct StreamingCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if text.isEmpty {
                HStack(spacing: 7) {
                    ActivityOrb(color: AstralTheme.orbGreen, size: 14)
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            ThinkingDot(delay: Double(index) * 0.18)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.06))
                .padding(.vertical, 4)
            } else {
                MarkdownView(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TypingCaret()
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One pulsing "thinking" dot.
private struct ThinkingDot: View {
    let delay: Double
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AstralTheme.textSecondary.opacity(0.65))
            .frame(width: 6.5, height: 6.5)
            .offset(y: pulsing ? -2.5 : 2)
            .animation(
                .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(delay),
                value: pulsing)
            .onAppear { pulsing = true }
    }
}
