import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Document picker bridge

/// A `UIDocumentPickerViewController` wrapper used instead of SwiftUI's
/// `.fileImporter`. The SwiftUI modifier has a long-standing reliability
/// problem when presented from inside sheets and menus: the picker opens,
/// the user taps a file, and the completion handler simply never fires
/// (or the file renders unselectable). The UIKit controller has none of
/// these issues and gives full control over the content types.
struct DocumentPicker: UIViewControllerRepresentable {
    /// Content types the user may pick. `[.item]` = every file selectable.
    var contentTypes: [UTType] = [.item]
    var allowsMultipleSelection = false
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .pageSheet
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls)
        }
    }
}

// MARK: - Presentation helper

/// Presents a UIKit document picker as a sheet from any SwiftUI hierarchy.
/// `asCopy: true` hands the app a copy in its own container, so no
/// security-scoped bookkeeping can silently fail on iCloud or
/// third-party-provider files.
struct DocumentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var contentTypes: [UTType] = [.item]
    var allowsMultipleSelection = false
    var onPick: ([URL]) -> Void

    var body: some View {
        DocumentPicker(
            contentTypes: contentTypes,
            allowsMultipleSelection: allowsMultipleSelection) { urls in
            dismiss()
            if !urls.isEmpty {
                onPick(urls)
            }
        }
        .ignoresSafeArea()
    }
}
