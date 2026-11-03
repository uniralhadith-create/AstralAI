import Foundation

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
            // V4.5.2 cloud mode: mirror the file up to the Ubuntu machine
            // so both computers see the same documents.
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
            // V4.5.2 cloud mode: the file may live on the cloud machine —
            // pull it down into the workspace and read it.
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
