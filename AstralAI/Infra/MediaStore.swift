import Foundation
import UIKit
import AVFoundation
import CoreVideo

// MARK: - Media store (Images & Workspace Videos)

/// Stores, normalizes and serves user-attached images (vision input) as well
/// as user/agent videos saved directly into the Workspace (`Videos/...`).
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

    // MARK: Saving Images

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

    // MARK: Saving & Resolving Videos in Workspace

    /// Saves raw video data directly into the Workspace (`Videos/<fileName>`)
    /// so it appears immediately in the Files tab and can be sent in chat.
    @MainActor
    @discardableResult
    static func saveVideo(
        data: Data,
        preferredName: String? = nil,
        workspaceFolder: String = "Videos",
        into workspace: WorkspaceRouting? = nil
    ) -> MessageVideo? {
        guard !data.isEmpty else { return nil }
        let store = workspace ?? WorkspaceStore.shared
        let fileName = sanitizedVideoFileName(preferredName)
        let folder = workspaceFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativePath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"

        do {
            if !folder.isEmpty {
                _ = try? store.createFolder(path: folder)
            }
            let fileURL = try store.writeData(path: relativePath, data: data)
            NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
            let asset = AVURLAsset(url: fileURL)
            let seconds = CMTimeGetSeconds(asset.duration)
            let validDuration = (seconds.isFinite && seconds > 0) ? seconds : nil
            return MessageVideo(
                fileName: (relativePath as NSString).lastPathComponent,
                workspacePath: relativePath,
                mimeType: mimeType(for: fileName),
                durationSeconds: validDuration,
                fileSize: Int64(data.count))
        } catch {
            return nil
        }
    }

    /// Copies a picked video file at `sourceURL` into the Workspace (`Videos/<fileName>`)
    /// and returns a `MessageVideo` reference.
    @MainActor
    @discardableResult
    static func saveVideo(
        at sourceURL: URL,
        preferredName: String? = nil,
        workspaceFolder: String = "Videos",
        into workspace: WorkspaceRouting? = nil
    ) -> MessageVideo? {
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer { if secured { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
            return nil
        }
        let name = preferredName ?? sourceURL.lastPathComponent
        return saveVideo(data: data, preferredName: name, workspaceFolder: workspaceFolder, into: workspace)
    }

    /// Creates a `MessageVideo` descriptor for a video file that ALREADY exists
    /// inside the Workspace at `relativePath`.
    @MainActor
    static func referenceExistingWorkspaceVideo(
        path relativePath: String,
        in workspace: WorkspaceRouting? = nil
    ) -> MessageVideo? {
        let store = workspace ?? WorkspaceStore.shared
        let cleaned = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = store.url(for: cleaned),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        let validDuration = (seconds.isFinite && seconds > 0) ? seconds : nil
        let fileName = url.lastPathComponent
        return MessageVideo(
            fileName: fileName,
            workspacePath: cleaned,
            mimeType: mimeType(for: fileName),
            durationSeconds: validDuration,
            fileSize: size)
    }

    /// Resolves the on-disk file URL in the Workspace for a `MessageVideo`.
    @MainActor
    static func videoURL(for video: MessageVideo) -> URL? {
        if let url = WorkspaceStore.shared.url(for: video.workspacePath) {
            return url
        }
        let candidate = WorkspaceStore.shared.rootURL.appendingPathComponent(video.workspacePath)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Generates a poster frame thumbnail for a workspace video.
    static func videoThumbnail(for url: URL, maxDimension: CGFloat = 480) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }

    static func isVideoFileName(_ name: String) -> Bool {
        FileKind(fileName: name) == .video
    }

    private static func sanitizedVideoFileName(_ preferred: String?) -> String {
        let stamp = Self.timestampString()
        guard let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferred.isEmpty else {
            return "video-\(stamp).mp4"
        }
        let rawName = (preferred as NSString).lastPathComponent
        let base = WorkspaceStore.sanitizeFolderName((rawName as NSString).deletingPathExtension)
        let ext = (rawName as NSString).pathExtension.lowercased()
        let validExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
        let finalExt = validExts.contains(ext) ? ext : "mp4"
        return "\(base.isEmpty ? "video-\(stamp)" : base).\(finalExt)"
    }

    private static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        default: return "video/mp4"
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    // MARK: Loading Images

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

// MARK: - On-Device MP4 Video Synthesizer (AVAssetWriter H.264)

/// Generates real, playable H.264 `.mp4` videos on-device using `AVAssetWriter`
/// and saves them straight into the Workspace (`Videos/...`). Used by the
/// `send_video` tool and the `ffmpeg` command in `astra-os`.
enum VideoSynthesizer {

    @MainActor
    static func generateMP4(
        title: String,
        subtitle: String = "",
        lines: [String] = [],
        imageURLs: [URL] = [],
        durationSeconds: Double = 4.0,
        width: Int = 1280,
        height: Int = 720,
        outputPath: String,
        into workspace: WorkspaceRouting? = nil
    ) async throws -> MessageVideo {
        let store = workspace ?? WorkspaceStore.shared
        var cleanPath = outputPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanPath.isEmpty {
            cleanPath = "Videos/astral-video-\(Int(Date().timeIntervalSince1970)).mp4"
        } else if !cleanPath.lowercased().hasSuffix(".mp4") && !cleanPath.lowercased().hasSuffix(".mov") {
            cleanPath += ".mp4"
        }
        if !cleanPath.contains("/") {
            cleanPath = "Videos/" + cleanPath
        }

        let parentFolder = (cleanPath as NSString).deletingLastPathComponent
        if !parentFolder.isEmpty {
            _ = try? store.createFolder(path: parentFolder)
        }

        let targetURL = store.rootURL.appendingPathComponent(cleanPath)
        try? FileManager.default.removeItem(at: targetURL)
        try? FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let fps: Int32 = 24
        let clampedDuration = min(max(durationSeconds, 2.0), 15.0)
        let totalFrames = max(Int(clampedDuration * Double(fps)), 24)
        let loadedImages = imageURLs.compactMap { UIImage(contentsOfFile: $0.path) }

        let writer = try AVAssetWriter(outputURL: targetURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes)

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "VideoSynthesizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add H.264 input to AVAssetWriter"])
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            let progress = Double(frameIndex) / Double(max(totalFrames - 1, 1))
            if let buffer = renderFrame(
                width: width,
                height: height,
                progress: progress,
                title: title,
                subtitle: subtitle,
                lines: lines,
                images: loadedImages,
                pool: adaptor.pixelBufferPool) {
                let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        store.list() // trigger refresh if needed
        WorkspaceStore.shared.refresh()
        NotificationCenter.default.post(name: .sandboxDidChange, object: nil)

        let fileSize = (try? targetURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return MessageVideo(
            fileName: targetURL.lastPathComponent,
            workspacePath: cleanPath,
            mimeType: "video/mp4",
            durationSeconds: clampedDuration,
            fileSize: fileSize)
    }

    private static func renderFrame(
        width: Int,
        height: Int,
        progress: Double,
        title: String,
        subtitle: String,
        lines: [String],
        images: [UIImage],
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        } else {
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32ARGB,
                attrs as CFDictionary,
                &pixelBufferOut)
        }
        guard let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        // Flip to UIKit top-left coordinates
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)

        // Deep space dark gradient background
        let bgColors = [
            UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                options: [])
        } else {
            UIColor.black.setFill()
            UIRectFill(canvasRect)
        }

        // If user provided images, draw current slide image
        if !images.isEmpty {
            let index = min(Int(progress * Double(images.count)), images.count - 1)
            let img = images[index]
            let inset = canvasRect.insetBy(dx: 80, dy: 80)
            img.draw(in: inset)
        } else {
            // Glass card frame in center
            let cardRect = CGRect(x: 72, y: 72, width: CGFloat(width - 144), height: CGFloat(height - 144))
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 32)
            UIColor(white: 1.0, alpha: 0.06).setFill()
            cardPath.fill()
            UIColor(white: 1.0, alpha: 0.18).setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            // Animated orb indicator
            let orbX = 128.0
            let orbY = 136.0
            let pulse = CGFloat(14.0 + 4.0 * sin(progress * .pi * 4.0))
            let orbRect = CGRect(x: orbX - pulse, y: orbY - pulse, width: pulse * 2, height: pulse * 2)
            UIColor(red: 0.20, green: 0.86, blue: 0.52, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: orbRect).fill()

            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor(white: 0.78, alpha: 1),
            ]
            ("Astral AI · astra-os" as NSString).draw(at: CGPoint(x: 158, y: 124), withAttributes: brandAttrs)

            // Main Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            (title as NSString).draw(
                in: CGRect(x: 120, y: 195, width: width - 240, height: 120),
                withAttributes: titleAttrs)

            // Subtitle
            if !subtitle.isEmpty {
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26, weight: .medium),
                    .foregroundColor: UIColor(red: 0.45, green: 0.85, blue: 0.98, alpha: 1),
                ]
                (subtitle as NSString).draw(
                    in: CGRect(x: 120, y: 315, width: width - 240, height: 80),
                    withAttributes: subAttrs)
            }

            // Lines / bullet points revealed progressively
            if !lines.isEmpty {
                let visibleCount = max(1, Int(ceil(progress * Double(lines.count))))
                let lineAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .regular),
                    .foregroundColor: UIColor(white: 0.90, alpha: 1),
                ]
                for (idx, line) in lines.prefix(visibleCount).enumerated() {
                    let y = CGFloat(395 + idx * 44)
                    if y < CGFloat(height - 150) {
                        ("• " + line as NSString).draw(
                            in: CGRect(x: 128, y: y, width: CGFloat(width - 256), height: 40),
                            withAttributes: lineAttrs)
                    }
                }
            }
        }

        // Animated progress bar at bottom of card
        let barBg = CGRect(x: 120, y: CGFloat(height - 116), width: CGFloat(width - 240), height: 8)
        UIColor(white: 1.0, alpha: 0.14).setFill()
        UIBezierPath(roundedRect: barBg, cornerRadius: 4).fill()

        let barFill = CGRect(
            x: 120,
            y: CGFloat(height - 116),
            width: max(12, CGFloat(width - 240) * CGFloat(progress)),
            height: 8)
        UIColor(red: 0.20, green: 0.86, blue: 0.52, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: barFill, cornerRadius: 4).fill()

        return pixelBuffer
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
