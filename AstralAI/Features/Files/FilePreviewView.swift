import SwiftUI
import QuickLook
import AVKit

// MARK: - File preview

/// Sheet preview for a workspace file: rendered markdown, syntax-highlighted
/// source, inline images, native AVPlayer for videos, or QuickLook for PDFs,
/// spreadsheets, archives and everything else.
struct FilePreviewView: View {
    let file: WorkspaceFile
    let url: URL

    @Environment(\.dismiss) private var dismiss

    @State private var text: String?
    @State private var videoPlayer: AVPlayer?

    /// Text preview is capped at 2 MB; larger text files go to QuickLook.
    private var textReadable: Bool {
        switch file.kind {
        case .markdown, .text, .code, .web:
            return file.size <= 2_000_000
        case .image, .video, .pdf, .spreadsheet, .archive, .other:
            return false
        }
    }

    var body: some View {
        ZStack {
            AstralTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .onAppear(perform: loadText)
        .onDisappear {
            videoPlayer?.pause()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: AstralTheme.Spacings.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(AstralTheme.headline(15))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)

                    Text(file.kind.rawValue.uppercased())
                        .font(AstralTheme.mono(9))
                        .tracking(1)
                        .foregroundStyle(FileKindStyle.tint(for: file.kind))
                }

                Spacer(minLength: 8)

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .frame(width: 30, height: 30)
                        .glassPill()
                }
                .accessibilityLabel(Text(L("common.share", "Shared")))

                Button {
                    videoPlayer?.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .frame(width: 30, height: 30)
                        .glassPill()
                }
                .accessibilityLabel(Text(L("common.close", "Shared")))
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.vertical, AstralTheme.Spacings.s)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch file.kind {
        case .markdown:
            textReadable ? AnyView(markdownContent) : AnyView(quickLookContent)
        case .text:
            textReadable ? AnyView(plainTextContent) : AnyView(quickLookContent)
        case .code, .web:
            textReadable ? AnyView(codeContent) : AnyView(quickLookContent)
        case .image:
            imageContent
        case .video:
            videoContent
        case .pdf, .spreadsheet, .archive, .other:
            quickLookContent
        }
    }

    private var videoContent: some View {
        Group {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(AstralTheme.Spacings.m)
            } else {
                quickLookContent
            }
        }
        .onAppear {
            if videoPlayer == nil && FileManager.default.fileExists(atPath: url.path) {
                let player = AVPlayer(url: url)
                videoPlayer = player
                player.play()
            }
        }
    }

    private var markdownContent: some View {
        ScrollView {
            Group {
                if let text {
                    MarkdownView(text)
                } else {
                    unavailableText
                }
            }
            .padding(AstralTheme.Spacings.m)
        }
    }

    private var plainTextContent: some View {
        ScrollView {
            Group {
                if let text {
                    Text(text)
                        .font(AstralTheme.mono(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    unavailableText
                }
            }
            .padding(AstralTheme.Spacings.m)
        }
    }

    private var codeContent: some View {
        ScrollView {
            Group {
                if let text {
                    Text(SyntaxHighlighter.highlight(
                        text,
                        language: file.kind == .web ? "html" : URL(fileURLWithPath: file.name).pathExtension))
                        .font(AstralTheme.mono(13))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    unavailableText
                }
            }
            .padding(AstralTheme.Spacings.m)
        }
    }

    private var imageContent: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                quickLookContent
            @unknown default:
                EmptyView()
            }
        }
        .padding(AstralTheme.Spacings.m)
    }

    private var quickLookContent: some View {
        Group {
            if FileManager.default.fileExists(atPath: url.path) {
                QuickLookView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                unavailableText
            }
        }
    }

    private var unavailableText: some View {
        VStack(spacing: AstralTheme.Spacings.s) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AstralTheme.moonDust)
            Text(L("files.preview.unreadable", "Files"))
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstralTheme.Spacings.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loading

    private func loadText() {
        guard textReadable else { return }
        text = try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - QuickLook bridge

fileprivate struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
