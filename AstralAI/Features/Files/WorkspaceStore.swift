import Foundation
import Combine

// MARK: - Errors

enum WorkspaceError: LocalizedError {
    case invalidPath(String)
    case notFound(String)
    case notTextFile(String)
    case nothingToArchive

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid workspace path: \(path)"
        case .notFound(let path):
            return "File not found in workspace: \(path)"
        case .notTextFile(let path):
            return "The file is not readable as UTF-8 text: \(path)"
        case .nothingToArchive:
            return "No files were provided to archive."
        }
    }
}

// MARK: - WorkspaceStore

/// The agent's sandboxed file system rooted at Documents/AstralWorkspace.
@MainActor
final class WorkspaceStore: ObservableObject, WorkspaceRouting {

    /// The app-wide workspace instance. `AppEnvironment` wires every
    /// subsystem to this one store so agent writes, user imports and the
    /// Files tab always observe the same file system (V4.5.2).
    static let shared = WorkspaceStore()

    @Published private(set) var files: [WorkspaceFile] = []

    let rootURL: URL
    private let fileManager = FileManager.default

    init() {
        let base: URL
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            base = documents.appendingPathComponent("AstralWorkspace", isDirectory: true)
        } else {
            base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("AstralWorkspace", isDirectory: true)
        }
        self.rootURL = base
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        refresh()
    }

    /// Re-scans the workspace and publishes the file list.
    func refresh() {
        files = list()
    }

    // MARK: WorkspaceRouting

    @discardableResult
    func write(path: String, content: String) throws -> URL {
        let relative = try Self.sanitizedRelativePath(path)
        guard let data = content.data(using: .utf8) else {
            throw WorkspaceError.notTextFile(relative)
        }
        return try writeData(path: relative, data: data)
    }

    @discardableResult
    func writeData(path: String, data: Data) throws -> URL {
        let relative = try Self.sanitizedRelativePath(path)
        let target = rootURL.appendingPathComponent(relative)
        let directory = target.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: target, options: .atomic)
        refresh()
        return target
    }

    /// Creates a folder (with intermediate parents) inside the workspace.
    @discardableResult
    func createFolder(path: String) throws -> URL {
        let relative = try Self.sanitizedRelativePath(path)
        let target = rootURL.appendingPathComponent(relative)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        refresh()
        return target
    }

    /// A safe folder name from free-form input (project names): strips
    /// path separators and characters the file system rejects.
    nonisolated static func sanitizeFolderName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Project" }
        return String(cleaned.prefix(60))
    }

    /// Folders that live directly under Projects/ — the user's project
    /// workspace areas (V4.5.2).
    var projectFolders: [String] {
        let projectsRoot = rootURL.appendingPathComponent("Projects")
        guard let entries = try? fileManager.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]),
            !entries.isEmpty else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    func read(path: String) throws -> String {
        let relative = try Self.sanitizedRelativePath(path)
        let target = rootURL.appendingPathComponent(relative)
        guard fileManager.fileExists(atPath: target.path) else {
            throw WorkspaceError.notFound(relative)
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            throw WorkspaceError.notFound(relative)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WorkspaceError.notTextFile(relative)
        }
        return text
    }

    /// Recursive flat scan of the workspace (hidden files skipped).
    func list() -> [WorkspaceFile] {
        Self.scan(root: rootURL)
    }

    func delete(path: String) throws {
        let relative = try Self.sanitizedRelativePath(path)
        let target = rootURL.appendingPathComponent(relative)
        guard fileManager.fileExists(atPath: target.path) else {
            throw WorkspaceError.notFound(relative)
        }
        do {
            try fileManager.removeItem(at: target)
        } catch {
            throw WorkspaceError.invalidPath(relative)
        }
        refresh()
    }

    func zip(paths: [String], archiveName: String) throws -> URL {
        var itemURLs: [URL] = []
        for path in paths {
            let relative = try Self.sanitizedRelativePath(path)
            let target = rootURL.appendingPathComponent(relative)
            guard fileManager.fileExists(atPath: target.path) else {
                throw WorkspaceError.notFound(relative)
            }
            itemURLs.append(target)
        }
        guard !itemURLs.isEmpty else {
            throw WorkspaceError.nothingToArchive
        }
        let archiveURL = try ZipService.zip(items: itemURLs, archiveName: archiveName, in: rootURL)
        refresh()
        return archiveURL
    }

    func url(for path: String) -> URL? {
        guard let relative = try? Self.sanitizedRelativePath(path) else { return nil }
        let target = rootURL.appendingPathComponent(relative)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        return target
    }

    // MARK: Path sanitization

    /// Normalizes a user/model supplied path into a safe workspace-relative
    /// path: no parent traversal, no absolute prefixes, subfolders allowed.
    private static func sanitizedRelativePath(_ path: String) throws -> String {
        var candidate = path.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.replacingOccurrences(of: "\\", with: "/")
        while candidate.hasPrefix("/") {
            candidate = String(candidate.dropFirst())
        }
        let components = candidate
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            throw WorkspaceError.invalidPath(path)
        }
        for component in components {
            if component == ".." || component == "." {
                throw WorkspaceError.invalidPath(path)
            }
        }
        return components.joined(separator: "/")
    }

    // MARK: Scanning

    private static func scan(root: URL) -> [WorkspaceFile] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            return []
        }

        let rootPath = root.standardizedFileURL.path
        var results: [WorkspaceFile] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if let isDirectory = values?.isDirectory, isDirectory {
                continue
            }
            let name = url.lastPathComponent
            if name == ".DS_Store" { continue }

            let fullPath = url.standardizedFileURL.path
            let relative = fullPath.hasPrefix(rootPath + "/")
                ? String(fullPath.dropFirst(rootPath.count + 1))
                : name

            results.append(
                WorkspaceFile(
                    id: relative,
                    name: name,
                    relativePath: relative,
                    size: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? Date(),
                    kind: FileKind(fileName: name)))
        }
        return results.sorted { $0.relativePath < $1.relativePath }
    }
}
