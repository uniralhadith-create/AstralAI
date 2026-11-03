import XCTest
import SwiftUI
@testable import AstralAI

// MARK: - Test doubles (V4.6.0)

/// Minimal WorkspaceRouting stub (mirrors AgentRuntimeTests' private one).
@MainActor
private final class QuickStubWorkspace: WorkspaceRouting {
    var rootURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    func write(path: String, content: String) throws -> URL { rootURL }
    func writeData(path: String, data: Data) throws -> URL { rootURL }
    func createFolder(path: String) throws -> URL { rootURL }
    func read(path: String) throws -> String { "" }
    func list() -> [WorkspaceFile] { [] }
    func delete(path: String) throws {}
    func zip(paths: [String], archiveName: String) throws -> URL { rootURL }
    func url(for path: String) -> URL? { nil }
}

// MARK: - V4.6.0 tests
//
// The fixes this release is built on:
// - the SVG arc-correction bug (inverted F.6.6 condition) that made the
//   chat-mode message-circle icon render as a stray loop outside its
//   frame — now arcs resolve to their true geometry,
// - the living green orb restored as the single work-in-progress signal,
// - browser_screenshot: the agent's screenshot permission, with delivery
//   keyed by tool-call id and images riding the tool message,
// - the ToolContext.callID plumbing that powers the delivery pairing.

final class V460Tests: XCTestCase {

    // MARK: Arc geometry (the chat-icon fix)

    /// The exact `d` attribute of the bundled Lucide `message-circle` —
    /// the chat-mode glyph. Before V4.6.0 the inverted radius-correction
    /// ballooned the 10-radius arc into a stray loop that escaped the
    /// 24×24 viewBox (the "icon outside the button border" report).
    private let messageCircleD = "M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719"

    func testMessageCircleStaysInsideViewBox() {
        guard let path = SVGPathCommands.parse(messageCircleD) else {
            XCTFail("message-circle path failed to parse")
            return
        }
        let box = path.boundingRect
        // The true Lucide bubble is a circle of radius 10 centered (12,12):
        // everything must sit inside the 24×24 design square with a small
        // tolerance for the stroke.
        XCTAssertEqual(box.minX, 2.0, accuracy: 0.8)
        XCTAssertEqual(box.minY, 2.0, accuracy: 0.8)
        XCTAssertEqual(box.maxX, 22.0, accuracy: 0.8)
        XCTAssertEqual(box.maxY, 22.0, accuracy: 0.8)
    }

    func testArcsNeverEscapeViewBox() {
        // Every bundled icon whose path uses elliptical arcs must keep
        // its geometry inside the 24×24 viewBox.
        let arcIcons = ["message-circle", "refresh-cw", "circle-check", "key-round"]
        var failures: [String] = []
        for icon in arcIcons {
            let url = Bundle.main.url(
                forResource: icon, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: icon, withExtension: "svg")
            guard let url, let svg = try? String(contentsOf: url, encoding: .utf8) else {
                failures.append(icon + "-missing")
                continue
            }
            guard let path = LucideSVGParser.parse(svg) else {
                failures.append(icon + "-parse")
                continue
            }
            let box = path.boundingRect
            if box.minX < -0.8 || box.minY < -0.8 || box.maxX > 24.8 || box.maxY > 24.8 {
                failures.append(
                    "\(icon)-outOfBox(\(String(format: "%.1f", box.minX)),\(String(format: "%.1f", box.minY)),\(String(format: "%.1f", box.maxX)),\(String(format: "%.1f", box.maxY)))")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "arc icons escaped the viewBox: \(failures.joined(separator: ", "))")
    }

    // MARK: Screenshot delivery

    @MainActor
    func testScreenCaptureDeliveryRoundTrip() {
        let callID = "call-\(UUID().uuidString)"
        let image = MessageImage(fileName: "shot.jpg", mimeType: "image/jpeg")

        XCTAssertNil(ScreenCaptureDelivery.take(callID: callID))
        ScreenCaptureDelivery.store(callID: callID, image: image)
        XCTAssertEqual(ScreenCaptureDelivery.take(callID: callID), image)
        // Taking consumes the slot — a second take must find nothing.
        XCTAssertNil(ScreenCaptureDelivery.take(callID: callID))
        // Unknown call ids never produce captures.
        XCTAssertNil(ScreenCaptureDelivery.take(callID: "nope"))
        // Empty call ids are never stored (guards the ToolContext default).
        ScreenCaptureDelivery.store(callID: nil, image: image)
        XCTAssertNil(ScreenCaptureDelivery.take(callID: nil))
    }

    // MARK: The screenshot tool

    @MainActor
    func testBrowserScreenshotToolShape() {
        let tool = BrowserScreenshotTool()
        XCTAssertEqual(tool.name, "browser_screenshot")
        let spec = tool.spec
        XCTAssertEqual(spec.function.name, "browser_screenshot")
        // The caption parameter exists and is optional (required is empty).
        let required = spec.function.parameters?.objectValue?["required"]?.arrayValue ?? []
        XCTAssertTrue(required.isEmpty, "browser_screenshot must take no required parameters")
    }

    // MARK: ToolContext callID plumbing

    @MainActor
    func testToolContextCallIDDefaultsAndSets() {
        let context = ToolContext(
            browser: nil,
            workspace: QuickStubWorkspace(),
            system: nil,
            session: SessionInfo(sessionID: UUID(), goal: "test"),
            isSubAgent: false)
        XCTAssertNil(context.callID)
        context.callID = "call-42"
        XCTAssertEqual(context.callID, "call-42")
    }

    // MARK: Tool messages carrying images

    func testToolMessageWithImagesSurvivesCodable() {
        // The session attaches screenshots as images on the tool message;
        // a persisted snapshot must keep them (the timeline reloads them).
        let message = ChatMessage(
            role: .tool,
            content: "Screenshot captured.",
            toolCallId: "call-9",
            name: "browser_screenshot",
            images: [MessageImage(fileName: "shot.jpg")])

        let data = try! JSONEncoder().encode(message)
        let back = try! JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(back.role, .tool)
        XCTAssertEqual(back.name, "browser_screenshot")
        XCTAssertEqual(back.images?.count, 1)
        XCTAssertEqual(back.images?.first?.fileName, "shot.jpg")
    }

    // MARK: The green orb identity

    func testOrbGreenIsDistinctFromAccent() {
        // The work-in-progress green is its own color, not the monochrome
        // accent — the orb must read green in both appearances.
        XCTAssertNotEqual(AstralTheme.orbGreen, AstralTheme.accent)
    }
}
