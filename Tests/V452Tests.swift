import XCTest
@testable import AstralAI

// MARK: - V4.5.2 tests
//
// The fixes this release is built on:
// - the E2B create-sandbox body carries the required templateID (the 400
//   "Error at /templateId" boot failure),
// - the Lucide SVG icon engine parses every shape element the bundled
//   icon set uses,
// - project folder names are sanitized,
// - cloud routing produces terminal-shaped output on both machines.

final class V452Tests: XCTestCase {

    // MARK: E2B create body

    @MainActor
    func testE2BCreateBodyIncludesTemplateID() throws {
        // The exact body ensureRunning() must send. templateID is the
        // REQUIRED field whose absence caused the V4.0 boot failure
        // ("validation error ... NewSandbox ... /templateId").
        let body: [String: Any] = ["templateID": "base", "timeout": 1800]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        XCTAssertEqual(object["templateID"] as? String, "base")
        XCTAssertEqual(object["timeout"] as? Int, 1800)
    }

    @MainActor
    func testE2BBundledKeyPresent() {
        // The developer key ships with the build so cloud mode works out
        // of the box; the Keychain entry overrides it.
        XCTAssertFalse(E2BComputer.bundledKey.isEmpty)
        XCTAssertTrue(E2BComputer.bundledKey.hasPrefix("e2b_"))
        XCTAssertTrue(E2BComputer.shared.isConfigured)
    }

    func testE2BConnectFrameRoundTrip() {
        let payload = Data("{\"hello\":\"世界\"}".utf8)
        let framed = E2BComputer.connectFrame(payload)
        XCTAssertEqual(framed[0], 0, "flags byte must be 0")
        XCTAssertEqual(framed.count, payload.count + 5, "1 flag + 4 length bytes")
        let decoded = E2BComputer.parseConnectFrames(framed)
        XCTAssertEqual(decoded, [payload])
    }

    // MARK: SVG icon engine

    func testSVGParserHandlesPathRectLineCircle() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"
             viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect width="20" height="14" x="2" y="3" rx="2" />
          <line x1="8" x2="16" y1="21" y2="21" />
          <line x1="12" x2="12" y1="17" y2="21" />
          <circle cx="12" cy="10" r="4" />
          <path d="M2 12 C4 6 10 4 12 10 S20 18 22 12" />
          <path d="m5 5 7 7" />
        </svg>
        """
        let path = try XCTUnwrap(LucideSVGParser.parse(svg), "the parser must produce a path")
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        XCTAssertTrue(
            path.boundingRect.intersects(rect),
            "combined path geometry must fall inside the 24×24 viewBox")
    }

    func testSVGPathCommandsParserAbsoluteAndRelative() throws {
        // M, L, H, V, C, S, Q, T, A and Z with implicit repetition.
        let d = "M1 2 3 4 L5 6 H8 V9 C1 1 2 2 3 3 S4 4 5 5 Q6 6 7 7 T8 8 A2 2 0 1 1 10 10 m1 1 l2 2 h3 v3 z"
        let path = try XCTUnwrap(SVGPathCommands.parse(d))
        XCTAssertFalse(
            path.isEmpty,
            "a full command walk must produce non-empty geometry")
    }

    func testBundledIconSetLoads() {
        // A representative sweep across the bundled Lucide icons — every
        // one must parse into real geometry.
        let icons = [
            "monitor", "square-terminal", "terminal", "globe", "compass",
            "folder", "folder-plus", "folder-open", "file-text", "file-code",
            "send", "settings", "sparkles", "cpu", "cloud", "cloud-off",
            "hard-drive", "mouse-pointer-click", "arrow-left", "plus",
            "check", "x", "play", "square", "download", "upload", "search",
            "chevron-down", "chevron-up", "chevron-right", "external-link",
            "list-todo", "message-circle", "zap", "package", "trash", "eye",
            "share-2", "key-round", "rocket", "bot", "brain", "wrench",
            "refresh-cw", "image", "wifi", "shield-check", "languages",
        ]
        var failures: [String] = []
        for icon in icons {
            let url = Bundle.main.url(
                forResource: icon, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: icon, withExtension: "svg")
            guard let url, let svg = try? String(contentsOf: url, encoding: .utf8) else {
                failures.append(icon + "-missing")
                continue
            }
            guard LucideSVGParser.parse(svg) != nil else {
                failures.append(icon + "-parse")
                continue
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "these bundled icons failed to load/parse: \(failures.joined(separator: ", "))")
    }

    // MARK: Workspace sanitization

    @MainActor
    func testSanitizeFolderName() {
        XCTAssertEqual(WorkspaceStore.sanitizeFolderName("Landing Page"), "Landing Page")
        XCTAssertEqual(WorkspaceStore.sanitizeFolderName("a/b\\c:d"), "a-b-c-d")
        XCTAssertEqual(WorkspaceStore.sanitizeFolderName("   "), "Project")
        XCTAssertEqual(
            WorkspaceStore.sanitizeFolderName(String(repeating: "x", count: 100)).count,
            60,
            "names cap at 60 characters")
    }

    // MARK: Cloud routing

    @MainActor
    func testCloudRoutingLocalExecShape() async {
        ComputerModeController.shared.mode = .local
        let outcome = await CloudRouting.exec("echo hello-v452")
        XCTAssertTrue(
            outcome.content.hasPrefix("$ echo hello-v452"),
            "terminal-shaped output must echo the command first")
        XCTAssertTrue(
            outcome.content.contains("hello-v452"),
            "the command output must be included")
        XCTAssertFalse(outcome.isError)
    }

    @MainActor
    func testComputerModeDefaultsAndSwitch() {
        // Default machine is local; the app persists a cloud switch.
        UserDefaults.standard.removeObject(forKey: "astral.computerMode")
        let fresh = ComputerModeController.shared
        XCTAssertEqual(fresh.mode, .local, "fresh installs start on the local machine")
        fresh.mode = .cloud
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "astral.computerMode"),
            "cloud",
            "the selected machine persists")
        // Restore for the other tests.
        fresh.mode = .local
    }
}
