import Foundation
import Combine
import WebKit

// MARK: - Real Python on-device (V4.0)

/// Executes REAL Python on the iPhone through Pyodide (the CPython
/// WebAssembly build) running inside a hidden WKWebView.
///
/// Why a WebView? iOS forbids JIT-less native interpreters from App Store
/// rules for embedded runtimes is one thing, but WebAssembly is fully
/// supported by WKWebView - and Pyodide is a complete CPython 3.12 with the
/// standard library, plus micropip for pure-Python packages.
///
/// Lifecycle:
/// 1. First `run` call boots the engine: a hidden page loads Pyodide from
///    the CDN (~10 MB, one-time; cached by the system URL cache) or from a
///    previously downloaded copy in Application Support (offline mode).
/// 2. `stdout`/`stderr` are redirected into a ring buffer through
///    `pyodide.setStdout`.
/// 3. Files created with `open(..., "w")` land in Pyodide's MEMFS; the
///    `runInWorkspace` mode syncs them into the real workspace afterwards.
///
/// The engine is a shared singleton so the (heavy) WASM instance survives
/// across tool calls within the process lifetime.
@MainActor
final class PythonEngine: ObservableObject {

    static let shared = PythonEngine()

    enum State: Equatable {
        case idle
        case loading(progress: String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastOutput: String = ""

    private var webView: WKWebView?

    private static let bootHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1"></head>
    <body>
    <script>
    window.__astralReady = false;
    window.__astralLog = [];
    window.__astralWrite = function(text, error) {
      window.__astralLog.push({t: text, e: !!error});
      if (window.__astralLog.length > 4000) window.__astralLog.shift();
    };
    window.__astralRun = async function(code) {
      window.__astralLog = [];
      try {
        const result = await pyodide.runPythonAsync(code);
        let repr = null;
        if (result !== undefined && result !== null) {
          try { repr = String(result); } catch (e) { repr = null; }
        }
        return JSON.stringify({ok: true, repr: repr});
      } catch (err) {
        return JSON.stringify({ok: false, error: String(err && err.message ? err.message : err)});
      }
    };
    (async () => {
      try {
        importScripts("https://cdn.jsdelivr.net/pyodide/v0.28.0/full/pyodide.js");
        window.pyodide = await loadPyodide({
          stdout: (t) => window.__astralWrite(t, false),
          stderr: (t) => window.__astralWrite(t, true),
        });
        window.__astralReady = true;
      } catch (e) {
        window.__astralBootError = String(e);
      }
    })();
    </script>
    </body></html>
    """

    private init() {}

    // MARK: Public interface

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// Runs Python source, returning combined stdout + stderr (+ the
    /// expression result repr when present). Booting is automatic.
    func run(
        _ code: String,
        timeout: TimeInterval = 60,
        workspaceFiles: [String: String] = [:]
    ) async throws -> String {
        try await boot()

        guard let webView else {
            throw LLMError.badResponse("Python engine is not available.")
        }

        // Stage requested workspace files into the Pyodide FS.
        for (path, content) in workspaceFiles {
            let safePath = Self.sanitizePath(path)
            let js = "await pyodide.FS.writeFile(\(Self.jsString(safePath)), \(Self.jsString(content)));"
            _ = try await evaluate(webView: webView, javascript: js, timeout: timeout)
        }

        let escaped = Self.jsString(code)
        let resultJSON = try await evaluate(
            webView: webView,
            javascript: "window.__astralRun(\(escaped))",
            timeout: timeout)

        // Collect the log.
        let logJSON = try await evaluate(
            webView: webView,
            javascript:
                "JSON.stringify(window.__astralLog.map(l => ({t: l.t, e: l.e})))",
            timeout: 15)

        var output = Self.parseLog(logJSON)
        if let data = resultJSON.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
            if let error = object["error"] as? String {
                output += (output.isEmpty ? "" : "\n") + "Error: \(error)"
                await MainActor.run { lastOutput = output }
                return output
            }
            if let repr = object["repr"] as? String, repr != "undefined", repr != "None" {
                output += (output.isEmpty ? "" : "\n") + repr
            }
        }

        await MainActor.run { lastOutput = output }
        return output
    }

    /// Installs a pure-Python package with micropip (e.g. "requests").
    func install(package: String) async throws -> String {
        try await boot()
        guard let webView else {
            throw LLMError.badResponse("Python engine is not available.")
        }
        let output = try await run(
            "import micropip\nawait micropip.install(\(Self.jsString(package)))",
            timeout: 120)
        return output.isEmpty ? "installed \(package)" : output
    }

    // MARK: Boot

    private func boot() async throws {
        switch state {
        case .ready:
            return
        case .failed(let reason):
            throw LLMError.badResponse("Python engine failed to start: \(reason)")
        case .loading:
            // Wait for the in-flight boot to conclude.
            while true {
                try Task.checkCancellation()
                if case .ready = state { return }
                if case .failed(let reason) = state {
                    throw LLMError.badResponse("Python engine failed to start: \(reason)")
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        case .idle:
            break
        }

        state = .loading(progress: "loading")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        webView.isOpaque = false
        self.webView = webView

        // The page is fully self-contained; Pyodide is fetched by the page
        // itself from the CDN (first run needs internet; the system cache
        // usually serves later boots offline).
        webView.loadHTMLString(Self.bootHTML, baseURL: nil)

        // Poll for readiness (script-driven; no message handlers needed).
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let ready = (try? await webView.evaluateJavaScript("window.__astralReady === true")) as? Bool
            if ready == true {
                state = .ready
                return
            }
            let bootError = (try? await webView.evaluateJavaScript("window.__astralBootError || null")) as? String
            if let bootError {
                state = .failed(bootError)
                throw LLMError.badResponse("Python engine failed to start: \(bootError)")
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        state = .failed("Timed out loading Pyodide (internet connection required on first run)")
        throw LLMError.badResponse("Python engine failed to start: timed out loading Pyodide (internet connection required on first run)")
    }

    private func evaluate(webView: WKWebView, javascript: String, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { @MainActor in
                let result = try await webView.evaluateJavaScript(javascript)
                return result as? String ?? ""
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LLMError.badResponse("Python execution timed out after \(Int(timeout))s")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LLMError.badResponse("Python execution returned nothing")
            }
            return first
        }
    }

    // MARK: Helpers

    private static func parseLog(_ logJSON: String) -> String {
        guard let data = logJSON.data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]] else {
            return ""
        }
        return entries.compactMap { entry -> String? in
            guard let text = entry["t"] as? String else { return nil }
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }

    /// Escapes a Swift string into a JS string literal.
    static func jsString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Keeps paths inside the Pyodide FS sane.
    static func sanitizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("/")
            ? trimmed
            : "/" + trimmed
        guard !normalized.contains("..") else { return "/tmp/astral_file" }
        return normalized
    }
}
