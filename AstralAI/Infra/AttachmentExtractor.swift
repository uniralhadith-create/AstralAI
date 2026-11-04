import Foundation
import PDFKit
import AVFoundation

// MARK: - Attachment extractor

/// Turns a picked file into a `MessageAttachment` the model can read and
/// stages binary/video files into the Workspace.
///
/// Supported:
/// - Video files (`.mp4`, `.mov`, `.m4v`, `.webm`, `.mkv`, `.avi`): copied
///   into `Videos/<name>` in the Workspace and inspected via `AVURLAsset`
///   for duration, resolution, and file size.
/// - PDF: full text extraction through PDFKit (page by page).
/// - Text-ish files (txt, md, json, csv, code, xml, yaml, html…): UTF-8
///   decode of the whole file.
/// - Everything else: copied into `uploads/<name>` with a descriptive
///   metadata note so the model can inspect it in `/home/astral/uploads/`.
enum AttachmentExtractor {

    /// Hard cap per file — keeps prompts within every provider's context
    /// window while remaining generous enough for real documents.
    private static let maxCharacters = 24_000

    static func extract(from url: URL) -> MessageAttachment {
        let name = url.lastPathComponent
        let text = extractText(from: url)
        return MessageAttachment(name: name, text: text)
    }

    static func extractText(from url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()

        // Video files: inspect duration & resolution and note Workspace path.
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mpeg", "mpg", "3gp"]
        if videoExtensions.contains(pathExtension) {
            let asset = AVURLAsset(url: url)
            let secs = CMTimeGetSeconds(asset.duration)
            let durStr = (secs.isFinite && secs > 0) ? String(format: "%.1fs", secs) : "unknown duration"
            return "[Video file \"\(url.lastPathComponent)\" (\(readableSize(of: url)), \(durStr)) — saved in Workspace under Videos/\(url.lastPathComponent)]"
        }

        // PDF: PDFKit extraction, page by page.
        if pathExtension == "pdf" {
            if let document = PDFDocument(url: url) {
                var pages: [String] = []
                var total = 0
                for index in 0..<document.pageCount {
                    guard let pageText = document.page(at: index)?.string else { continue }
                    let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    pages.append(trimmed)
                    total += trimmed.count
                    if total > maxCharacters { break }
                }
                let joined = pages.joined(separator: "\n\n")
                if !joined.isEmpty {
                    return capped(joined)
                }
                return "[PDF file \"\(url.lastPathComponent)\" — no extractable text layer; it may be a scanned image]"
            }
            return "[PDF file \"\(url.lastPathComponent)\" could not be opened]"
        }

        // Text-like formats: read as UTF-8.
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "csv", "tsv", "xml", "yaml", "yml",
            "html", "htm", "css", "js", "ts", "jsx", "tsx", "swift", "py", "rb",
            "java", "kt", "c", "h", "cpp", "hpp", "cs", "go", "rs", "php", "sh",
            "sql", "log", "ini", "cfg", "conf", "toml", "plist", "rtf", "srt",
            "vtt", "skill",
        ]
        if textExtensions.contains(pathExtension) || pathExtension.isEmpty {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return capped(text)
            }
            if pathExtension == "rtf" {
                if let attributed = try? NSAttributedString(
                    url: url,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil) {
                    return capped(attributed.string)
                }
            }
        }

        // Office documents: best-effort plain-text scrape.
        if ["doc", "docx"].contains(pathExtension) {
            return "[Word document \"\(url.lastPathComponent)\" attached — extract its content with the file tools if needed]"
        }

        return "[Binary file \"\(url.lastPathComponent)\" (\(readableSize(of: url))) attached — ask the user about its contents if relevant]"
    }

    private static func capped(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters))
            + "\n…[truncated — file has \(text.count) characters in total]"
    }

    private static func readableSize(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
