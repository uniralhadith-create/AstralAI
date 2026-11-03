import Foundation
import Combine
import UIKit
import WebKit

// MARK: - Errors

/// Browser-level failures surfaced to the agent as tool errors.
enum BrowserError: LocalizedError {
    case invalidAddress(String)
    case timeout
    case superseded
    case scriptError(String)
    case webViewUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "Invalid web address: \(address)"
        case .timeout:
            return "The page took too long to load."
        case .superseded:
            return "The navigation was interrupted by user action."
        case .scriptError(let detail):
            return "Page interaction failed: \(detail)"
        case .webViewUnavailable:
            return "The web view is no longer available."
        }
    }
}

// MARK: - BrowserGate

/// Serializes agent-issued browser commands. Swift actors are reentrant, so a
/// node chain inside the actor guarantees each command fully completes before
/// the next one starts, even when parallel sub-agents race to browse.
private actor BrowserGate {

    private final class Node {
        let task: Task<Void, Error>
        init(task: Task<Void, Error>) {
            self.task = task
        }
    }

    /// Thread-safe result holder so the chain task (typed `Void`) can still
    /// carry the generic operation result back to the caller.
    private final class ResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<T, Error>?

        func store(_ value: Result<T, Error>) {
            lock.lock()
            result = value
            lock.unlock()
        }

        func get() throws -> T {
            lock.lock()
            defer { lock.unlock() }
            guard let result else { throw CancellationError() }
            return try result.get()
        }
    }

    private var tail: Node?

    func run<T>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let box = ResultBox<T>()
        let task = Task<Void, Error> { @MainActor [previous] in
            if let previous {
                _ = try? await previous.task.value
            }
            do {
                box.store(.success(try await body()))
            } catch {
                box.store(.failure(error))
            }
        }
        let node = Node(task: task)
        tail = node
        defer {
            if tail === node {
                tail = nil
            }
        }
        try await task.value
        return try box.get()
    }
}

// MARK: - BrowserController

/// The shared in-app browser: a single WKWebView driven both by the user and
/// by the agent, with strict command serialization for agent operations.
@MainActor
final class BrowserController: NSObject, ObservableObject, BrowserControlling {

    let webView: WKWebView

    @Published private(set) var urlText: String = ""
    @Published private(set) var title: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    /// True while the agent drives the browser; user actions take it back.
    @Published var agentMode: Bool = false
    @Published private(set) var lastAgentAction: String = ""

    private let gate = BrowserGate()
    private var pendingNavigation: CheckedContinuation<String, Error>?
    private var navigationEpoch: Int = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.allowsBackForwardNavigationGestures = true
        self.webView = view
        super.init()
        view.navigationDelegate = self
    }

    // MARK: User controls

    /// Loads what the user typed: a URL when it looks like one, otherwise a
    /// DuckDuckGo search.
    func loadUserURL(_ urlString: String) {
        agentMode = false
        failPendingNavigation(with: BrowserError.superseded)
        guard let target = Self.resolvedURL(urlString) else { return }
        _ = webView.load(URLRequest(url: target))
    }

    func userBack() {
        agentMode = false
        failPendingNavigation(with: BrowserError.superseded)
        if webView.canGoBack {
            _ = webView.goBack()
        }
    }

    func userForward() {
        agentMode = false
        failPendingNavigation(with: BrowserError.superseded)
        if webView.canGoForward {
            _ = webView.goForward()
        }
    }

    func userReload() {
        agentMode = false
        failPendingNavigation(with: BrowserError.superseded)
        _ = webView.reload()
    }

    // MARK: BrowserControlling (agent commands)

    func open(url urlString: String) async throws -> String {
        try await gate.run {
            guard let target = Self.resolvedURL(urlString) else {
                throw BrowserError.invalidAddress(urlString)
            }
            self.agentMode = true
            self.lastAgentAction = L("browser.action.open", "Browser")
                + " " + (target.host ?? target.absoluteString)

            let request = URLRequest(url: target)
            let pageTitle = try await self.awaitNavigation(timeout: 20) {
                _ = self.webView.load(request)
            }
            if !pageTitle.isEmpty {
                self.title = pageTitle
            }
            return pageTitle.isEmpty ? (target.host ?? target.absoluteString) : pageTitle
        }
    }

    func clickElement(index: Int) async throws -> String {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.click", "Browser")
            let raw = try await self.evaluateString(BrowserScripts.clickElement(index: index))
            if raw.hasPrefix("ERROR:") {
                let detail = String(raw.dropFirst("ERROR:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw BrowserError.scriptError(detail.isEmpty ? "element not found" : detail)
            }
            var label = raw
            if label.hasPrefix("CLICKED:") {
                label = String(label.dropFirst("CLICKED:".count))
            }
            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastAgentAction = L("browser.action.click", "Browser")
                + " " + (label.isEmpty ? "#\(index)" : label)
            // Give the page a moment to react to the click.
            try? await Task.sleep(for: .seconds(1.5))
            return "Clicked: \(label.isEmpty ? "element #\(index)" : label)"
        }
    }

    func typeText(index: Int, text: String, submit: Bool) async throws -> String {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.type", "Browser") + " #" + String(index)
            let raw = try await self.evaluateString(
                BrowserScripts.typeText(index: index, text: text, submit: submit))
            if raw.hasPrefix("ERROR:") {
                let detail = String(raw.dropFirst("ERROR:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw BrowserError.scriptError(detail.isEmpty ? "element not found" : detail)
            }
            let target = "element #\(index)"
            self.lastAgentAction = L("browser.action.type", "Browser") + " " + target
            return submit ? "Typed into \(target) and submitted" : "Typed into \(target)"
        }
    }

    func scroll(direction: String, amount: Int) async throws -> String {
        try await gate.run {
            self.agentMode = true
            let directionKey = direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.lastAgentAction = L("browser.action.scroll", "Browser") + " " + directionKey
            _ = try await self.evaluateString(
                BrowserScripts.scroll(direction: direction, amount: amount))
            return "Scrolled \(directionKey)"
        }
    }

    func extractText(maxChars: Int = 6000) async throws -> String {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.read", "Browser")
            let capped = max(100, min(maxChars, 50000))
            let text = try await self.evaluateString(BrowserScripts.extractText(maxChars: capped))
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "The current page has no readable text content."
            }
            return text
        }
    }

    func listElements() async throws -> [PageElement] {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.list", "Browser")
            let raw = try await self.evaluateString(BrowserScripts.listElements)
            guard let data = raw.data(using: .utf8) else { return [] }
            let elements = (try? JSONDecoder().decode([PageElement].self, from: data)) ?? []
            return elements
        }
    }

    func currentPageSummary() async throws -> String {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.summary", "Browser")
            let currentURL = self.webView.url?.absoluteString ?? "(no page loaded)"
            let currentTitle = self.webView.title ?? self.title
            let excerpt = try await self.evaluateString(BrowserScripts.extractText(maxChars: 400))
            let flat = excerpt.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "URL: \(currentURL)\nTitle: \(currentTitle)\nExcerpt: \(String(flat.prefix(400)))"
        }
    }

    func goBack() async throws -> String {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.back", "Browser")
            guard self.webView.canGoBack else {
                return "Already at the first page in history."
            }
            let pageTitle = try await self.awaitNavigation(timeout: 8) {
                _ = self.webView.goBack()
            }
            if !pageTitle.isEmpty {
                self.title = pageTitle
            }
            return pageTitle.isEmpty ? "Went back to the previous page." : pageTitle
        }
    }

    // MARK: Screenshot (V4.6.0)

    /// Captures the page the browser is currently on as PNG data.
    ///
    /// Two capture modes, one shared machine:
    /// - **Live capture** — the browser sheet is open: the web view is in
    ///   a window with a real size, so it snapshots exactly what the user
    ///   sees.
    /// - **Staged capture** — the sheet is closed: the web view is parked
    ///   offscreen inside the key window (x = -12000) on a 390×780 canvas,
    ///   given a moment to composite, snapshot, then removed. The page is
    ///   already loaded; WebKit only needs a few runloop ticks to present
    ///   it, so the capture is pixel-real without flashing anything on
    ///   screen.
    func captureScreenshot() async throws -> Data {
        try await gate.run {
            self.agentMode = true
            self.lastAgentAction = L("browser.action.screenshot", "Browser")

            guard self.webView.url != nil, !self.webView.isLoading else {
                throw BrowserError.webViewUnavailable
            }

            var staged = false
            let inWindow = self.webView.window != nil && self.webView.bounds.width >= 200

            if !inWindow {
                guard let host = Self.stagingWindow() else {
                    throw BrowserError.webViewUnavailable
                }
                self.webView.frame = CGRect(
                    x: -12000, y: 0,
                    width: Self.captureCanvas.width,
                    height: Self.captureCanvas.height)
                host.addSubview(self.webView)
                self.webView.setNeedsLayout()
                self.webView.layoutIfNeeded()
                staged = true
            }

            defer {
                if staged {
                    self.webView.removeFromSuperview()
                }
            }

            // Let WebKit composite the already-loaded page.
            try? await Task.sleep(for: .milliseconds(700))

            let bounds = self.webView.bounds
            guard bounds.width > 50, bounds.height > 50 else {
                throw BrowserError.webViewUnavailable
            }

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 2
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
                self.webView.drawHierarchy(in: bounds, afterScreenUpdates: true)
            }
            guard let png = image.pngData(), !png.isEmpty else {
                throw BrowserError.webViewUnavailable
            }
            return png
        }
    }

    /// The staged-capture canvas — a phone-shaped viewport.
    private static let captureCanvas = CGSize(width: 390, height: 780)

    /// The key window of the foreground scene, used as an invisible host
    /// while staging the web view offscreen.
    private static func stagingWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    // MARK: Navigation waiting

    /// Awaits the completion of a navigation triggered by `onStart`. Races the
    /// navigation continuation against a timeout using a task group; the epoch
    /// counter guarantees a continuation is only ever resumed once and never
    /// armed after it has been superseded.
    private func awaitNavigation(
        timeout: TimeInterval = 20,
        onStart: (@MainActor () -> Void)? = nil
    ) async throws -> String {
        navigationEpoch += 1
        let epoch = navigationEpoch

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<String, Error>) in
                        Task { @MainActor [weak self] in
                            guard let self else {
                                continuation.resume(throwing: BrowserError.webViewUnavailable)
                                return
                            }
                            guard self.navigationEpoch == epoch else {
                                continuation.resume(throwing: CancellationError())
                                return
                            }
                            self.pendingNavigation = continuation
                            onStart?()
                        }
                    }
                } onCancel: {
                    Task { @MainActor [weak self] in
                        guard let self, self.navigationEpoch == epoch else { return }
                        self.failPendingNavigation(with: CancellationError())
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw BrowserError.timeout
            }

            guard let winner = try await group.next() else {
                throw BrowserError.timeout
            }
            return winner
        }
    }

    @discardableResult
    private func resumePendingNavigation(with result: Result<String, Error>) -> Bool {
        guard let continuation = pendingNavigation else { return false }
        pendingNavigation = nil
        switch result {
        case .success(let pageTitle):
            continuation.resume(returning: pageTitle)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        return true
    }

    private func failPendingNavigation(with error: Error) {
        navigationEpoch += 1
        _ = resumePendingNavigation(with: .failure(error))
    }

    // MARK: JavaScript bridge

    /// Bridges WKWebView's completion-handler API into async/await.
    private func evaluateJS(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Evaluates a script and stringifies the result.
    private func evaluateString(_ js: String) async throws -> String {
        let result = try await evaluateJS(js)
        if let string = result as? String {
            return string
        }
        if let number = result as? NSNumber {
            return number.stringValue
        }
        guard let result else { return "" }
        return String(describing: result)
    }

    // MARK: URL resolution

    /// Turns raw input into a loadable URL: keeps http(s), prepends https://
    /// to bare domains, and falls back to a DuckDuckGo search for words.
    private static func resolvedURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        if !trimmed.contains(" "),
           trimmed.contains("."),
           let url = URL(string: "https://" + trimmed),
           url.host != nil {
            return url
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "duckduckgo.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }
}

// MARK: - WKNavigationDelegate

extension BrowserController: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        Task { @MainActor in
            self.syncState(isLoading: true)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            self.syncState(isLoading: true)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.syncState(isLoading: false)
            self.resumePendingNavigation(with: .success(webView.title ?? ""))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.syncState(isLoading: false)
            self.resumePendingNavigation(with: .failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.syncState(isLoading: false)
            self.resumePendingNavigation(with: .failure(error))
        }
    }

    private func syncState(isLoading: Bool) {
        self.isLoading = isLoading
        if let current = webView.url?.absoluteString {
            urlText = current
        }
        if let currentTitle = webView.title, !currentTitle.isEmpty {
            title = currentTitle
        }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}
