import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - View model

/// Observable state for the share sheet (mutated by the view controller
/// while attachments are extracted and saved).
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case saving
        case ready(itemCount: Int)
        case empty
        case failed
    }

    @Published var phase: Phase = .saving
}

// MARK: - SwiftUI sheet

/// Self-contained share UI: dark space gradient, aurora mark, save status
/// and the two exit buttons (open the app / just finish).
private struct ShareSheetView: View {
    @ObservedObject var model: ShareModel
    let onOpen: () -> Void
    let onDone: () -> Void

    private var isArabic: Bool {
        Locale.current.language.languageCode?.identifier == "ar"
    }

    private var auroraGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.486, green: 0.227, blue: 0.929),
                Color(red: 0.133, green: 0.827, blue: 0.933)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(auroraGradient)
                .padding(.top, 10)

            Text("Astral AI")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            statusView
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                // Aurora capsule — hand the shared content to the agent.
                Button(action: onOpen) {
                    Text(isArabic ? "افتح أسترال" : "Open Astral")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.486, green: 0.227, blue: 0.929),
                                        Color(red: 0.133, green: 0.827, blue: 0.933)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing)))
                }
                .disabled(model.phase == .saving)
                .opacity(model.phase == .saving ? 0.55 : 1)

                // Glass capsule — finish without opening the app; the
                // content is still saved and imported on next launch.
                Button(action: onDone) {
                    Text(isArabic ? "تم" : "Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.03, blue: 0.14),
                    Color(red: 0.12, green: 0.07, blue: 0.32)
                ],
                startPoint: .top,
                endPoint: .bottom)
            .ignoresSafeArea())
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color(red: 0.133, green: 0.827, blue: 0.933))
                Text(isArabic ? "جارٍ الحفظ…" : "Saving…")
            }
        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.204, green: 0.827, blue: 0.600))
                Text(isArabic ? "جاهز للإرسال إلى وكيلك" : "Ready to send to your agent")
            }
        case .empty:
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(isArabic ? "لا يوجد محتوى للمشاركة" : "Nothing to share")
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 0.984, green: 0.749, blue: 0.141))
                Text(isArabic ? "تعذّر حفظ المحتوى" : "Couldn't save the content")
            }
        }
    }
}

// MARK: - Principal class

/// Share extension principal class (matches NSExtensionPrincipalClass in
/// Info.plist). Extracts text / URL / images from any app, stores them in
/// the shared inbox and offers to open Astral.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.03, blue: 0.14, alpha: 1)

        let sheet = UIHostingController(
            rootView: ShareSheetView(
                model: model,
                onOpen: { [weak self] in self?.openAstralApp() },
                onDone: { [weak self] in self?.finishSharing() }))
        addChild(sheet)
        view.addSubview(sheet.view)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sheet.view.backgroundColor = .clear
        sheet.didMove(toParent: self)

        Task { @MainActor in
            await extractAndSave()
        }
    }

    // MARK: - Provider access

    /// All attachments across every input item.
    private var allProviders: [NSItemProvider] {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        return items.flatMap { $0.attachments ?? [] }
    }

    // MARK: - Extraction + persistence

    private func extractAndSave() async {
        let providers = allProviders

        // First non-empty text (plain text, broader text, utf8 text).
        var extractedText: String?
        for provider in providers {
            guard extractedText == nil,
                  provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) else {
                continue
            }
            if let loaded = await loadText(from: provider), !loaded.isEmpty {
                extractedText = loaded
            }
        }

        // First URL (Safari shares land here, often with the page title as
        // the text attachment — both are kept).
        var extractedURL: String?
        for provider in providers {
            guard extractedURL == nil,
                  provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
                continue
            }
            if let loaded = await loadURL(from: provider), !loaded.isEmpty {
                extractedURL = loaded
            }
        }

        // Up to five images.
        var savedImageCount = 0
        let imageProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        for provider in imageProviders.prefix(5) {
            guard let data = await loadImageData(from: provider) else { continue }
            do {
                _ = try ShareSupport.saveImage(data)
                savedImageCount += 1
            } catch {
                print("[ShareExtension] image save failed: \(error)")
            }
        }

        let hasTextOrURL = (extractedText?.isEmpty == false) || (extractedURL?.isEmpty == false)

        guard hasTextOrURL || savedImageCount > 0 else {
            model.phase = .empty
            return
        }

        // Text + URL go into ONE combined metadata file (missing parts omitted).
        if hasTextOrURL {
            var meta = "Shared from another app:"
            if let extractedText, !extractedText.isEmpty {
                meta += "\n\(extractedText)"
            }
            if let extractedURL, !extractedURL.isEmpty {
                meta += "\nURL: \(extractedURL)"
            }
            do {
                _ = try ShareSupport.saveMeta(meta)
            } catch {
                print("[ShareExtension] meta save failed: \(error)")
                model.phase = .failed
                return
            }
        }

        model.phase = .ready(itemCount: savedImageCount + (hasTextOrURL ? 1 : 0))
    }

    // MARK: - Item loading helpers (completion → continuation bridges)

    private func loadText(from provider: NSItemProvider) async -> String? {
        let identifiers = [
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.utf8PlainText.identifier
        ]
        for identifier in identifiers {
            guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
            let loaded: String? = await withCheckedContinuation { continuation in
                _ = provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                    switch item {
                    case let string as String:
                        continuation.resume(returning: string)
                    case let attrString as NSAttributedString:
                        continuation.resume(returning: attrString.string)
                    case let nsString as NSString:
                        continuation.resume(returning: nsString as String)
                    default:
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let loaded, !loaded.isEmpty {
                return loaded
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: url.absoluteString)
                case let url as NSURL:
                    continuation.resume(returning: url.absoluteString)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Exit actions

    /// Opens the app on the import deep link, then completes the request.
    private func openAstralApp() {
        if let url = URL(string: "astral://import") {
            _ = openURL(url)
        }
        finishSharing()
    }

    private func finishSharing() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// Walks the responder chain looking for a UIApplication instance —
    /// the standard technique for opening the containing app from an
    /// extension (UIApplication.shared is unavailable here). When it fails
    /// on a given OS version the shared content is still saved and will be
    /// imported the next time the app becomes active.
    private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self as UIResponder
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url)
                return true
            }
            responder = responder?.next
        }
        return false
    }
}
