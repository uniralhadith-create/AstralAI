import Foundation

// MARK: - Video delivery bridge

/// Bridge between the `send_video` tool (and `ffmpeg`/`yt-dlp` in `exec`)
/// and the chat timeline. Stores delivered `MessageVideo` references keyed
/// by tool-call id so the session attaches them to the tool `ChatMessage`.
@MainActor
enum VideoDelivery {
    private static var pending: [String: [MessageVideo]] = [:]
    private static var latestUnkeyed: [MessageVideo] = []

    static func store(callID: String?, video: MessageVideo) {
        if let callID, !callID.isEmpty {
            pending[callID, default: []].append(video)
        } else {
            latestUnkeyed.append(video)
        }
    }

    static func take(callID: String?) -> [MessageVideo]? {
        var collected: [MessageVideo] = []
        if let callID, let items = pending.removeValue(forKey: callID) {
            collected.append(contentsOf: items)
        }
        if !latestUnkeyed.isEmpty {
            collected.append(contentsOf: latestUnkeyed)
            latestUnkeyed.removeAll()
        }
        return collected.isEmpty ? nil : collected
    }
}

// MARK: - SendVideoTool

/// Allows the AI agent to send a video directly into the chat timeline AND
/// save it into the Workspace (`Videos/...`). Supports:
/// 1. Sending an existing video file from the workspace (`path`).
/// 2. Downloading a video from a direct URL (`url`), saving it into the
///    workspace, and delivering it to the chat.
/// 3. Generating a real H.264 `.mp4` video on-device (`title`, `subtitle`,
///    `slides`, or `image_paths`), saving it into the workspace, and
///    delivering it to the chat.
@MainActor
final class SendVideoTool: AgentTool {

    static let toolName = "send_video"
    let name = SendVideoTool.toolName

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Send a video to the user in the chat and save it in the Workspace (under Videos/). "
                + "You can: (1) pass 'path' to an existing video in the workspace (e.g. 'Videos/clip.mp4'), "
                + "(2) pass 'url' to download a video from the web into the workspace and send it in chat, or "
                + "(3) pass 'title' (and optional 'subtitle', 'slides' array of bullet strings, or 'image_paths' array of workspace images) "
                + "to synthesize a real H.264 .mp4 video on-device, save it to the workspace, and deliver it in the chat.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace-relative path for the video, e.g. 'Videos/demo.mp4'"),
                    ]),
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("Optional direct http(s) URL of a video file to download, save to the workspace, and send in chat"),
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("Title shown on the video card or rendered into a synthesized .mp4 video"),
                    ]),
                    "subtitle": .object([
                        "type": .string("string"),
                        "description": .string("Optional subtitle rendered when synthesizing an .mp4 video"),
                    ]),
                    "slides": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional list of key points/lines to animate into a generated .mp4 video"),
                    ]),
                    "image_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional workspace image paths (e.g. ['Screenshots/1.png']) to stitch into an .mp4 video"),
                    ]),
                    "duration_seconds": .object([
                        "type": .string("number"),
                        "description": .string("Duration in seconds when generating a video (default 4, max 15)"),
                    ]),
                ]),
                "required": .array([]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let rawPath = arguments["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawURL = arguments["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitle = arguments["subtitle"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let slides = (arguments["slides"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !$0.isEmpty }
        let imagePaths = (arguments["image_paths"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !$0.isEmpty }
        let duration = arguments["duration_seconds"]?.doubleValue ?? 4.0

        // 1. Existing file in workspace
        if !rawPath.isEmpty,
           let existing = MediaStore.referenceExistingWorkspaceVideo(path: rawPath, in: context.workspace) {
            VideoDelivery.store(callID: context.callID, video: existing)
            return ToolResult(
                content: "Video delivered to the user in chat and saved in workspace at \(existing.workspacePath) (\(existing.fileName)).")
        }

        // 2. Download from URL -> Save to Workspace -> Deliver to Chat
        if !rawURL.isEmpty {
            var urlString = rawURL
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            guard let targetURL = URL(string: urlString) else {
                return ToolResult(content: "Error: invalid video URL '\(rawURL)'.", isError: true)
            }
            do {
                var req = URLRequest(url: targetURL)
                req.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                    forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 45
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    return ToolResult(content: "Error: HTTP \(http.statusCode) downloading video from \(rawURL).", isError: true)
                }
                let preferredName = !rawPath.isEmpty
                    ? (rawPath as NSString).lastPathComponent
                    : (targetURL.lastPathComponent.isEmpty ? "downloaded-video.mp4" : targetURL.lastPathComponent)
                let folder = (!rawPath.isEmpty && rawPath.contains("/"))
                    ? (rawPath as NSString).deletingLastPathComponent
                    : "Videos"
                guard let saved = MediaStore.saveVideo(
                    data: data,
                    preferredName: preferredName,
                    workspaceFolder: folder,
                    into: context.workspace) else {
                    return ToolResult(content: "Error: could not save downloaded video to workspace.", isError: true)
                }
                await CloudRouting.mirrorUpData(path: saved.workspacePath, data: data)
                VideoDelivery.store(callID: context.callID, video: saved)
                return ToolResult(
                    content: "Downloaded video (\(data.count) bytes), saved to workspace at \(saved.workspacePath), and delivered it to the user in chat.")
            } catch {
                return ToolResult(content: "Error downloading video: \(error.localizedDescription)", isError: true)
            }
        }

        // 3. Synthesize a real H.264 .mp4 video on-device -> Save to Workspace -> Deliver to Chat
        let outputPath = rawPath.isEmpty
            ? "Videos/astral-\(Int(Date().timeIntervalSince1970)).mp4"
            : rawPath
        let resolvedImageURLs = imagePaths.compactMap { context.workspace.url(for: $0) }
        let videoTitle = title.isEmpty ? (context.session.goal.isEmpty ? "Astral AI" : String(context.session.goal.prefix(48))) : title

        do {
            let generated = try await VideoSynthesizer.generateMP4(
                title: videoTitle,
                subtitle: subtitle,
                lines: slides,
                imageURLs: resolvedImageURLs,
                durationSeconds: duration,
                outputPath: outputPath,
                into: context.workspace)
            if let url = context.workspace.url(for: generated.workspacePath),
               let data = try? Data(contentsOf: url) {
                await CloudRouting.mirrorUpData(path: generated.workspacePath, data: data)
            }
            VideoDelivery.store(callID: context.callID, video: generated)
            return ToolResult(
                content: "Generated H.264 MP4 video '\(generated.fileName)', saved in workspace at \(generated.workspacePath), and delivered it to the user in the chat.")
        } catch {
            return ToolResult(content: "Error generating video: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - File tools

/// Writes a text file into the agent workspace.
@MainActor
final class FileWriteTool: AgentTool {

    let name = "file_write"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Write a text file into the agent workspace. Subdirectories are created automatically.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace-relative path, e.g. notes/summary.md"),
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("The full text content to write"),
                    ]),
                ]),
                "required": .array([.string("path"), .string("content")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        guard let content = arguments["content"]?.stringValue else {
            return ToolResult(content: "Error: missing required parameter 'content'.", isError: true)
        }
        do {
            let url = try context.workspace.write(path: path, content: content)
            await CloudRouting.mirrorUp(path: path, content: content)
            return ToolResult(
                content: "Wrote \(content.count) characters to \(path) (absolute: \(url.absoluteString))")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Reads a text file from the agent workspace.
@MainActor
final class FileReadTool: AgentTool {

    let name = "file_read"
    private static let maxCharacters = 8000

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Read a text file from the agent workspace.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace-relative path of the file to read"),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        do {
            let content = try context.workspace.read(path: path)
            if content.count > Self.maxCharacters {
                let truncated = String(content.prefix(Self.maxCharacters))
                return ToolResult(
                    content: truncated
                        + "\n... [truncated, the file has \(content.count) characters in total]")
            }
            return ToolResult(content: content)
        } catch {
            if CloudRouting.active, E2BComputer.shared.isRunning {
                if let pulled = try? await E2BComputer.shared.pullFileRelative(
                    path: path, into: context.workspace),
                    let content = try? context.workspace.read(path: path) {
                    _ = pulled
                    if content.count > Self.maxCharacters {
                        return ToolResult(
                            content: String(content.prefix(Self.maxCharacters))
                                + "\n... [truncated, the file has \(content.count) characters in total]")
                    }
                    return ToolResult(content: content)
                }
            }
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Lists the files in the agent workspace.
@MainActor
final class FileListTool: AgentTool {

    let name = "file_list"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "List every file in the agent workspace with its size and last modification date.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let files = context.workspace.list()
        guard !files.isEmpty else {
            return ToolResult(content: "Workspace is empty")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        var lines: [String] = ["Workspace files:"]
        for file in files {
            let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            lines.append(
                "\(file.relativePath) - \(size) - \(dateFormatter.string(from: file.modifiedAt))")
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }
}

/// Deletes a file from the agent workspace.
@MainActor
final class FileDeleteTool: AgentTool {

    let name = "file_delete"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Delete a file (or folder) from the agent workspace.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace-relative path of the file to delete"),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        do {
            try context.workspace.delete(path: path)
            return ToolResult(content: "Deleted \(path)")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Bundles workspace files into a zip archive.
@MainActor
final class FileZipTool: AgentTool {

    let name = "file_zip"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Bundle one or more workspace files into a zip archive stored in the workspace.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Workspace-relative paths of the files to include"),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Archive name (a .zip extension is added when missing)"),
                    ]),
                ]),
                "required": .array([.string("paths")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let paths: [String] = (arguments["paths"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return ToolResult(content: "Error: 'paths' must contain at least one file.", isError: true)
        }
        let archiveName = arguments["name"]?.stringValue ?? "Archive"
        do {
            let url = try context.workspace.zip(paths: paths, archiveName: archiveName)
            return ToolResult(
                content: "Created archive \(url.lastPathComponent) from \(paths.count) file(s) (absolute: \(url.absoluteString))")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Renders text content into a paginated PDF inside the workspace.
@MainActor
final class FilePDFTool: AgentTool {

    let name = "file_pdf"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Create a PDF document in the workspace from text content. Simple markdown formatting is flattened automatically.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Output workspace path ending in .pdf"),
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("Document title shown at the top of the PDF"),
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("The body text of the document"),
                    ]),
                ]),
                "required": .array([.string("path"), .string("content")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard var path = arguments["path"]?.stringValue, !path.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        guard let content = arguments["content"]?.stringValue, !content.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'content'.", isError: true)
        }
        if !path.lowercased().hasSuffix(".pdf") {
            path += ".pdf"
        }
        let title: String
        if let provided = arguments["title"]?.stringValue,
           !provided.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = provided
        } else {
            title = "Document"
        }
        let body = Self.strippedMarkdown(content)
        let data = PDFExporter.makePDF(title: title, body: body)
        do {
            let url = try context.workspace.writeData(path: path, data: data)
            return ToolResult(
                content: "PDF written to \(path) (\(data.count) bytes, absolute: \(url.absoluteString))")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Removes the most common markdown markers so the PDF reads cleanly.
    private static func strippedMarkdown(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: "__", with: "")
        out = out.replacingOccurrences(of: "`", with: "")
        var lines: [String] = []
        for rawLine in out.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            while line.hasPrefix("#") {
                line = String(line.dropFirst())
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
