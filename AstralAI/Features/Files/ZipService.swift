import Foundation
import ZIPFoundation

// MARK: - ZipService

/// Zip archive creation built on ZIPFoundation.
enum ZipService {

    /// Zips one or more items into `directory`. Single items keep their
    /// parent directory; multiple items are staged in a temporary folder so
    /// every file lands in the archive. Archive names are made unique.
    static func zip(items: [URL], archiveName: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        guard !items.isEmpty else {
            throw WorkspaceError.nothingToArchive
        }

        var name = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "Archive"
        }
        name = name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".zip") {
            name += ".zip"
        }

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = (name as NSString).deletingPathExtension
        var target = directory.appendingPathComponent(name)
        var counter = 1
        while fileManager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(baseName)-\(counter).zip")
            counter += 1
        }

        if items.count == 1 {
            try fileManager.zipItem(at: items[0], to: target, shouldKeepParent: true)
            return target
        }

        // Stage all items in a temporary folder, preserving file names.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for item in items {
            let destination = staging.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                // Name collision: prefix with the parent folder name.
                let alternative = staging.appendingPathComponent(
                    item.deletingLastPathComponent().lastPathComponent
                        + "-" + item.lastPathComponent)
                try fileManager.copyItem(at: item, to: alternative)
            } else {
                try fileManager.copyItem(at: item, to: destination)
            }
        }

        try fileManager.zipItem(at: staging, to: target, shouldKeepParent: false)
        return target
    }
}
