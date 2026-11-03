import Foundation

// MARK: - Browser tools

/// Opens a URL in the in-app browser.
@MainActor
final class BrowserOpenTool: AgentTool {

    let name = "browser_open"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Open a URL in the in-app browser and wait for it to load. Returns the page title.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("The URL to open (https:// is added when missing; plain words become a search)"),
                    ]),
                ]),
                "required": .array([.string("url")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let url = arguments["url"]?.stringValue,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'url'.", isError: true)
        }
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let pageTitle = try await browser.open(url: url)
            return ToolResult(content: "Opened page. Title: \(pageTitle)")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Lists the interactive elements on the current page with stable indexes.
@MainActor
final class BrowserElementsTool: AgentTool {

    let name = "browser_list_elements"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "List the interactive elements (links, buttons, inputs) on the current page, each with an index usable for clicking or typing.",
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
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let elements = try await browser.listElements()
            guard !elements.isEmpty else {
                return ToolResult(content: "No interactive elements found on the current page.")
            }
            var lines: [String] = ["Interactive elements on the current page:"]
            for element in elements {
                let label = element.text.isEmpty ? "(no text)" : element.text
                lines.append("[\(element.id)] <\(element.tag)> \(label)")
            }
            return ToolResult(content: lines.joined(separator: "\n"))
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Clicks an element by index.
@MainActor
final class BrowserClickTool: AgentTool {

    let name = "browser_click"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Click an interactive element on the current page by its index (from browser_list_elements).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "index": .object([
                        "type": .string("integer"),
                        "description": .string("Element index from browser_list_elements"),
                    ]),
                ]),
                "required": .array([.string("index")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let index = arguments["index"]?.intValue, index >= 0 else {
            return ToolResult(content: "Error: missing or invalid required parameter 'index'.", isError: true)
        }
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let outcome = try await browser.clickElement(index: index)
            return ToolResult(content: outcome)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Types text into an element by index.
@MainActor
final class BrowserTypeTool: AgentTool {

    let name = "browser_type"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Type text into an input element on the current page by its index, optionally submitting the form (presses Enter).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "index": .object([
                        "type": .string("integer"),
                        "description": .string("Element index from browser_list_elements"),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("The text to type"),
                    ]),
                    "submit": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether to submit the form after typing (default false)"),
                    ]),
                ]),
                "required": .array([.string("index"), .string("text")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let index = arguments["index"]?.intValue, index >= 0 else {
            return ToolResult(content: "Error: missing or invalid required parameter 'index'.", isError: true)
        }
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'text'.", isError: true)
        }
        let submit = arguments["submit"]?.boolValue ?? false
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let outcome = try await browser.typeText(index: index, text: text, submit: submit)
            return ToolResult(content: outcome)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Reads the visible text of the current page.
@MainActor
final class BrowserReadTool: AgentTool {

    let name = "browser_read_text"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Read the visible text content of the current page (up to max_chars characters).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "max_chars": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum characters to return, default 6000"),
                    ]),
                ]),
                "required": .array([]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let maxChars = arguments["max_chars"]?.intValue ?? 6000
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let text = try await browser.extractText(maxChars: maxChars)
            return ToolResult(content: text)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Scrolls the current page.
@MainActor
final class BrowserScrollTool: AgentTool {

    let name = "browser_scroll"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Scroll the current page up or down by a number of screens, or jump to the top or bottom.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "direction": .object([
                        "type": .string("string"),
                        "description": .string("One of: up, down, top, bottom"),
                    ]),
                    "amount": .object([
                        "type": .string("integer"),
                        "description": .string("How far to scroll in screens, default 2"),
                    ]),
                ]),
                "required": .array([.string("direction")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let direction = arguments["direction"]?.stringValue,
              !direction.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'direction'.", isError: true)
        }
        let amount = arguments["amount"]?.intValue ?? 2
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let outcome = try await browser.scroll(direction: direction, amount: amount)
            return ToolResult(content: outcome)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Navigates back in browser history.
@MainActor
final class BrowserBackTool: AgentTool {

    let name = "browser_back"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Go back to the previous page in the browser history.",
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
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let outcome = try await browser.goBack()
            return ToolResult(content: outcome)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Screenshot delivery (V4.6.0)

/// Bridge between the `browser_screenshot` tool and the chat timeline.
/// The tool runs inside `ToolRegistry.execute`; when it captures a page it
/// stores the resulting `MessageImage` here against the tool call's id.
/// When the session turns the tool result into a `ChatMessage` it looks
/// the capture up and attaches it, so the image rides the message into
/// the timeline (and into persisted snapshots) — the agent can now show
/// the user what it is looking at.
@MainActor
enum ScreenCaptureDelivery {
    /// Captures waiting to be attached, keyed by tool-call id.
    private static var pending: [String: MessageImage] = [:]

    static func store(callID: String?, image: MessageImage) {
        guard let callID, !callID.isEmpty else { return }
        pending[callID] = image
    }

    static func take(callID: String?) -> MessageImage? {
        guard let callID else { return nil }
        defer { pending[callID] = nil }
        return pending[callID]
    }
}

/// Takes a screenshot of the page the in-app browser is currently on and
/// delivers it into the chat. The image also lands in the workspace under
/// `Screenshots/` so it shows up in Files.
@MainActor
final class BrowserScreenshotTool: AgentTool {

    static let toolName = "browser_screenshot"

    let name = BrowserScreenshotTool.toolName

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Take a screenshot of the page the in-app browser is currently on and deliver it to the user in the chat. Use it whenever the user asks to see a site, a page, or what you are looking at right now.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "caption": .object([
                        "type": .string("string"),
                        "description": .string("Short one-line caption shown under the screenshot (optional)"),
                    ]),
                ]),
                "required": .array([]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let browser = context.browser else {
            return ToolResult(content: "Error: the browser is not available.", isError: true)
        }
        do {
            let png = try await browser.captureScreenshot()
            guard let reference = MediaStore.save(imageData: png) else {
                return ToolResult(
                    content: "Error: the capture could not be stored.", isError: true)
            }

            // Register the capture against this exact call so the session
            // can attach it to the tool message.
            ScreenCaptureDelivery.store(callID: context.callID, image: reference)

            // A copy for the workspace (Files > Screenshots).
            let stamp = Self.fileStamp()
            let workspacePath = "Screenshots/\(stamp).png"
            var mirrored = true
            do {
                _ = try context.workspace.createFolder(path: "Screenshots")
                _ = try context.workspace.writeData(path: workspacePath, data: png)
            } catch {
                mirrored = false
            }

            let caption = arguments["caption"]?.stringValue ?? ""
            var lines = [
                "Screenshot captured and delivered to the user in the chat.",
                mirrored ? "Also saved to the workspace at \(workspacePath)." :
                    "Workspace copy unavailable; the chat image is the only copy.",
            ]
            if !caption.isEmpty {
                lines.append("Caption: \(caption)")
            }
            lines.append("Briefly describe what the screenshot shows in your reply to the user; do not paste raw page dumps.")
            return ToolResult(content: lines.joined(separator: "\n"))
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
