import Foundation
import UIKit

// MARK: - Media store

/// Stores, normalizes and serves user-attached images (vision input).
///
/// Images are normalized on import — EXIF orientation is baked in, the long
/// edge is capped at 1568 px (the vision-model sweet spot) and everything is
/// re-encoded as JPEG — so payloads stay small regardless of what the user
/// picked. Binary data lives under `Documents/AstralMedia`; `MessageImage`
/// values stored in session snapshots only reference the file name.
enum MediaStore {

    /// Maximum long edge after normalization.
    static let maxDimension: CGFloat = 1568
    /// JPEG compression quality for stored vision copies.
    static let jpegQuality: CGFloat = 0.65

    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return documents.appendingPathComponent("AstralMedia", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Saving

    /// Normalizes raw image data and stores it. Returns the reference, or
    /// nil when the data is not a decodable image.
    @discardableResult
    static func save(imageData: Data) -> MessageImage? {
        guard let source = UIImage(data: imageData) else { return nil }
        return save(image: source)
    }

    /// Normalizes a UIImage and stores it.
    @discardableResult
    static func save(image: UIImage) -> MessageImage? {
        let normalized = normalize(image)
        guard let data = normalized.jpegData(compressionQuality: jpegQuality), !data.isEmpty else {
            return nil
        }
        ensureDirectory()
        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return MessageImage(fileName: fileName, mimeType: "image/jpeg")
    }

    // MARK: Loading

    /// Raw stored bytes for an image reference (nil when the file vanished).
    static func load(_ image: MessageImage) -> Data? {
        let url = directory.appendingPathComponent(image.fileName)
        return try? Data(contentsOf: url)
    }

    /// Decoded UIImage, optionally downscaled for UI thumbnails.
    static func uiImage(_ image: MessageImage, thumbnailMax: CGFloat? = nil) -> UIImage? {
        guard let data = load(image) else { return nil }
        guard let source = UIImage(data: data) else { return nil }
        guard let thumbnailMax else { return source }
        return downscale(source, maxDimension: thumbnailMax)
    }

    /// Data-URI (`data:image/jpeg;base64,…`) for OpenAI-compatible vision
    /// payloads. Returns nil when the file is missing.
    static func dataURI(_ image: MessageImage) -> String? {
        guard let data = load(image) else { return nil }
        return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
    }

    /// Raw base64 (no prefix) for AWS Bedrock `source.bytes` blocks.
    static func base64(_ image: MessageImage) -> String? {
        load(image)?.base64EncodedString()
    }

    // MARK: Deletion

    static func delete(_ image: MessageImage) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(image.fileName))
    }

    // MARK: Normalization

    /// Bakes EXIF orientation, then caps the long edge at `maxDimension`.
    private static func normalize(_ image: UIImage) -> UIImage {
        let upright = image.fixOrientation()
        return downscale(upright, maxDimension: maxDimension)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - EXIF orientation

private extension UIImage {

    /// Redraws the image so `imageOrientation` is `.up` — vision APIs and
    /// thumbnails then agree on which way is up.
    func fixOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
