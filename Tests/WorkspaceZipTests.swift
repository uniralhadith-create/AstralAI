import XCTest
import ZIPFoundation
@testable import AstralAI

/// Integration tests for WorkspaceStore: writing, reading, listing,
/// resolving URLs, deleting and zipping files inside the app workspace.
/// Every test uses a unique "uitest-<uuid>/" path prefix and cleans up
/// after itself so repeated runs stay deterministic.
final class WorkspaceZipTests: XCTestCase {

    // MARK: Helpers

    /// Removes workspace-relative files, an optional extra URL (such as a
    /// generated archive) and the test's unique prefix directory. Missing
    /// items are tolerated.
    @MainActor
    private func cleanupWorkspace(
        _ store: WorkspaceStore,
        paths: [String],
        prefix: String,
        extraURL: URL? = nil
    ) {
        for path in paths {
            try? store.delete(path: path)
        }
        if let extraURL = extraURL {
            try? FileManager.default.removeItem(at: extraURL)
        }
        try? FileManager.default.removeItem(at: store.rootURL.appendingPathComponent(prefix))
    }

    // MARK: Root

    @MainActor
    func testWorkspaceRootIsAstralWorkspaceInsideDocuments() async throws {
        let store = WorkspaceStore()
        XCTAssertEqual(store.rootURL.lastPathComponent, "AstralWorkspace")
        XCTAssertTrue(
            store.rootURL.path.contains("Documents"),
            "workspace should live inside Documents, got: \(store.rootURL.path)"
        )
    }

    // MARK: File lifecycle

    @MainActor
    func testWriteReadListURLAndDeleteLifecycle() async throws {
        let store = WorkspaceStore()
        let prefix = "uitest-\(UUID().uuidString)"
        let path = "\(prefix)/test-dir/hello.txt"
        let content = "Hello Astral workspace"

        defer { cleanupWorkspace(store, paths: [path], prefix: prefix) }

        // Write
        let writtenURL = try store.write(path: path, content: content)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: writtenURL.path),
            "written file should exist on disk at: \(writtenURL.path)"
        )

        // Read
        let readBack = try store.read(path: path)
        XCTAssertEqual(readBack, content)

        // List (both the routing method and the published property)
        store.refresh()
        XCTAssertTrue(
            store.list().contains { $0.name == "hello.txt" && $0.relativePath.contains(prefix) },
            "listing should contain the written file"
        )
        XCTAssertTrue(
            store.files.contains { $0.name == "hello.txt" && $0.relativePath.contains(prefix) },
            "published files should contain the written file"
        )

        // URL resolution
        let resolved = try XCTUnwrap(store.url(for: path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resolved.path),
            "resolved URL should point at an existing file: \(resolved.path)"
        )

        // Delete
        try store.delete(path: path)
        XCTAssertNil(store.url(for: path), "url(for:) should be nil after deletion")
        XCTAssertThrowsError(try store.read(path: path), "reading a deleted file should throw")
        store.refresh()
        XCTAssertFalse(
            store.list().contains { $0.relativePath.contains(prefix) && $0.name == "hello.txt" },
            "deleted file should disappear from the listing"
        )
    }

    @MainActor
    func testWriteOverwritesExistingFile() async throws {
        let store = WorkspaceStore()
        let prefix = "uitest-\(UUID().uuidString)"
        let path = "\(prefix)/overwrite.txt"

        defer { cleanupWorkspace(store, paths: [path], prefix: prefix) }

        try store.write(path: path, content: "first version")
        try store.write(path: path, content: "second version")
        XCTAssertEqual(try store.read(path: path), "second version")
    }

    @MainActor
    func testReadMissingFileThrows() async throws {
        let store = WorkspaceStore()
        XCTAssertThrowsError(
            try store.read(path: "uitest-\(UUID().uuidString)/definitely-missing.txt")
        )
    }

    @MainActor
    func testURLForMissingFileIsNil() async throws {
        let store = WorkspaceStore()
        XCTAssertNil(store.url(for: "uitest-\(UUID().uuidString)/missing.bin"))
    }

    // MARK: ZIP

    @MainActor
    func testZipCreatesValidArchiveThenDeletesBoth() async throws {
        let store = WorkspaceStore()
        let prefix = "uitest-\(UUID().uuidString)"
        let fileA = "\(prefix)/alpha.txt"
        let fileB = "\(prefix)/nested/beta.md"
        let archiveName = "test-archive-\(UUID().uuidString.prefix(8))"
        var archiveURL: URL?

        defer {
            cleanupWorkspace(
                store,
                paths: [fileA, fileB],
                prefix: prefix,
                extraURL: archiveURL
            )
        }

        // Fixtures
        try store.write(path: fileA, content: "Alpha content for the archive.")
        try store.write(path: fileB, content: "# Beta\n\nMarkdown body.")

        // Zip
        let zipURL = try store.zip(paths: [fileA, fileB], archiveName: archiveName)
        archiveURL = zipURL

        // The archive exists, is named .zip and is non-empty.
        XCTAssertTrue(
            zipURL.lastPathComponent.hasSuffix(".zip"),
            "expected a .zip file name, got: \(zipURL.lastPathComponent)"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: zipURL.path),
            "archive should exist at: \(zipURL.path)"
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(size, 0, "archive should not be empty")

        // The file starts with the ZIP magic bytes ("PK").
        let head = try Data(contentsOf: zipURL)
        XCTAssertGreaterThanOrEqual(head.count, 4)
        XCTAssertEqual(
            head.prefix(2),
            Data("PK".utf8),
            "archive should start with the ZIP magic bytes"
        )

        // ZIPFoundation can open the archive and finds both source files.
        // (Archive(url:accessMode:) is a failable initializer.)
        guard let archive = try Archive(url: zipURL, accessMode: .read) else {
            XCTFail("ZIPFoundation could not open the created archive")
            return
        }
        var entryCount = 0
        var entryPaths: [String] = []
        for entry in archive {
            entryCount += 1
            entryPaths.append(entry.path)
        }
        XCTAssertGreaterThanOrEqual(
            entryCount, 2,
            "archive should contain at least the two written files, got: \(entryPaths)"
        )
        XCTAssertTrue(
            entryPaths.contains { $0.hasSuffix("alpha.txt") },
            "archive should contain alpha.txt, got: \(entryPaths)"
        )
        XCTAssertTrue(
            entryPaths.contains { $0.hasSuffix("beta.md") },
            "archive should contain beta.md, got: \(entryPaths)"
        )

        // Delete both the archive and the source files.
        let rootPath = store.rootURL.path
        let archivePath = zipURL.path
        if archivePath.hasPrefix(rootPath + "/") {
            // The archive lives inside the workspace: remove it through
            // the store so the listing stays in sync.
            try? store.delete(path: String(archivePath.dropFirst(rootPath.count + 1)))
        }
        try? FileManager.default.removeItem(at: zipURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: zipURL.path),
            "archive should be removed after deletion"
        )
        store.refresh()
        XCTAssertFalse(
            store.list().contains { $0.relativePath.contains(prefix) && $0.relativePath.hasSuffix(".zip") },
            "archive should disappear from the listing"
        )
    }
}
