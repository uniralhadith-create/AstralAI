import Foundation
import Combine

// MARK: - Computer mode (V4.5.2)

/// Which machine the whole app runs on:
/// - `.local`  — astra-os, the on-device sandbox (always available).
/// - `.cloud`  — a REAL Ubuntu Linux cloud computer (E2B). When selected,
///   the agent's `exec`, `run_python` and the user's Shell tab all run on
///   the cloud machine; workspace files sync up/down automatically.
@MainActor
enum ComputerMode: String {
    case local
    case cloud
}

@MainActor
final class ComputerModeController: ObservableObject {
    static let shared = ComputerModeController()

    @Published var mode: ComputerMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "astral.computerMode")
            if mode == .cloud, oldValue == .local {
                // Switching to the cloud machine warms it up right away so
                // the first command does not pay the boot cost.
                Task { try? await E2BComputer.shared.ensureRunning() }
            }
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "astral.computerMode")
        self.mode = ComputerMode(rawValue: raw ?? "") ?? .local
    }

    /// True when the whole app should route execution to the cloud
    /// machine (requires a configured E2B key).
    var prefersCloud: Bool {
        mode == .cloud && E2BComputer.shared.isConfigured
    }
}

// MARK: - E2B cloud computer

/// A REAL full Ubuntu Linux machine for the agent, in the cloud, via the
/// E2B API - the same infrastructure Manus uses for its virtual computers.
///
/// iOS cannot run a real Linux VM locally, so Astral ships a two-tier
/// computer:
/// - **astra-os** (local): the on-device shell + workspace, always
///   available, with real Python (Pyodide) and real JavaScript.
/// - **Cloud Linux** (this file): a genuine Ubuntu microVM. The agent
///   gets full bash, apt, real Python with pip, a real file system.
///
/// REST endpoints (all verified against the official E2B API reference):
/// - POST   https://api.e2b.app/v2/sandboxes        (X-API-Key)  create
///         body: {"templateID": "base", "timeout": 1800}
/// - POST   https://api.e2b.app/sandboxes/{id}/timeout           extend
/// - DELETE https://api.e2b.app/sandboxes/{id}                    kill
/// - POST   https://sandbox.e2b.app/process.Process/Start         run cmd
/// - POST   https://sandbox.e2b.app/files?path=...   (multipart)  upload
/// - GET    https://sandbox.e2b.app/files?path=...                download
///
/// The process API speaks the Connect protocol: every message is framed
/// as 1 flag byte + 4-byte big-endian length + JSON. The response is a
/// stream of frames carrying stdout/stderr data events and a final exit
/// event.
@MainActor
final class E2BComputer: ObservableObject {

    static let shared = E2BComputer()

    // MARK: State

    enum Status: Equatable {
        case off
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var lastCommand: String?
    @Published private(set) var liveOutput: String = ""
    /// True while the machine is shutting down after a finished job.
    @Published private(set) var shuttingDown = false

    /// Clears the live output feed (terminal "clear").
    func clearLog() {
        liveOutput = ""
    }

    /// Appends an error line to the live feed.
    func appendLog(_ line: String) {
        liveOutput += line + "\n"
    }

    private var sandboxID: String?
    private var envdToken: String?
    private var lastActivity = Date.distantPast
    /// The last time the USER personally ran a command in the cloud tab.
    private var lastUserCommand = Date.distantPast
    private var keepAliveTask: Task<Void, Never>?

    /// The user's E2B API key, stored in the Keychain under this account.
    static let keychainAccount = "astral.e2b.apikey"

    /// The key that ships with this build (set by the developer). The
    /// user's Keychain entry always wins when present — Settings lets
    /// them replace it at any time.
    static let bundledKey = "e2b_4882440dedeeeb5fc539c4682573a512dfb2342d"

    var apiKey: String? {
        get {
            if let stored = try? KeychainStore.get(account: Self.keychainAccount),
               !stored.isEmpty {
                return stored
            }
            return Self.bundledKey
        }
        set {
            if let newValue, !newValue.isEmpty {
                try? KeychainStore.save(newValue, account: Self.keychainAccount)
            } else {
                try? KeychainStore.delete(account: Self.keychainAccount)
                Task { await kill(reason: "key removed") }
            }
        }
    }

    /// Whether the user overrode the bundled key with their own.
    var usesCustomKey: Bool {
        guard let stored = try? KeychainStore.get(account: Self.keychainAccount) else {
            return false
        }
        return !stored.isEmpty && stored != Self.bundledKey
    }

    var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isRunning: Bool {
        sandboxID != nil && envdToken != nil && status == .running
    }

    private static let apiBase = URL(string: "https://api.e2b.app")!
    private static let sandboxBase = URL(string: "https://sandbox.e2b.app")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    private init() {
        // A previously started sandbox is long gone after relaunch - start
        // from a clean slate.
        sandboxID = nil
        envdToken = nil
    }

    // MARK: Public interface

    /// Runs a bash command on the real Linux machine, creating it first
    /// if needed. Returns stdout + stderr + exit code.
    ///
    /// V4.7.0 — full-power machine: when a command fails with a
    /// permission error it is automatically re-run with `sudo -n`
    /// (the E2B user has passwordless sudo), so the agent effectively
    /// holds root over the whole computer. Nothing it needs is ever
    /// blocked with "Permission denied".
    func run(
        _ command: String,
        timeout: TimeInterval = 60,
        byUser: Bool = false
    ) async throws -> (output: String, exitCode: Int) {
        let (output, exitCode) = try await runOnce(command, timeout: timeout, byUser: byUser)

        // Auto root escalation: one clean retry with sudo.
        if exitCode != 0,
           !command.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("sudo"),
           Self.looksLikePermissionFailure(output) {
            let escalated = "sudo -n bash -c " + Self.shellQuoted(command)
            let (retryOutput, retryExit) = try await runOnce(
                escalated, timeout: timeout, byUser: byUser)
            if retryExit != exitCode || retryOutput != output {
                return (retryOutput, retryExit)
            }
        }
        return (output, exitCode)
    }

    /// True when a command's output indicates it was blocked by file or
    /// system permissions. (Internal: the V4.7.0 test suite pins the
    /// exact Ubuntu strings that must trigger the sudo retry.)
    nonisolated static func looksLikePermissionFailure(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
            || lowered.contains("eacces")
            || lowered.contains("only root can")
            || lowered.contains("try re-running as root")
            || lowered.contains("are you root")
            || lowered.contains("requires root")
    }

    /// Wraps a command in single quotes for safe `bash -c` nesting.
    nonisolated private static func shellQuoted(_ command: String) -> String {
        "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// One raw command execution against the (already running) sandbox.
    private func runOnce(
        _ command: String,
        timeout: TimeInterval,
        byUser: Bool
    ) async throws -> (output: String, exitCode: Int) {
        guard isConfigured else {
            throw LLMError.badResponse(
                "E2B API key not configured. Add one in Settings > Cloud Computer.")
        }

        lastCommand = command
        if byUser { lastUserCommand = Date() }
        try await ensureRunning()

        let request = try startRequest(command: command, timeoutMS: Int(timeout * 1000))
        let (data, response) = try await Self.session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(1000), encoding: .utf8) ?? ""
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 502 {
                // Sandbox died - reset so the next call starts a fresh one.
                await reset()
                throw LLMError.badResponse("Cloud computer session expired. Try again.")
            }
            throw LLMError.badResponse("Cloud command failed (HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0 )): \(body)")
        }

        var stdout = ""
        var stderr = ""
        var exitCode = 0
        for payload in Self.parseConnectFrames(data) {
            guard let object = (try? JSONSerialization.jsonObject(with: payload, options: [])) as? [String: Any],
                  let event = object["event"] as? [String: Any] else { continue }
            if let dataEvent = (event["data"] as? [String: Any]) {
                stdout += dataEvent["stdout"] as? String ?? ""
                stderr += dataEvent["stderr"] as? String ?? ""
            }
            if let exitEvent = (event["exit"] as? [String: Any]) {
                exitCode = (exitEvent["exitCode"] as? NSNumber)?.intValue ?? 0
            }
        }

        let output = stdout + (stderr.isEmpty ? "" : "\n" + stderr)
        await MainActor.run {
            liveOutput += "$ \(command)\n\(output)\n"
            if liveOutput.count > 40_000 { liveOutput = String(liveOutput.suffix(40_000)) }
        }
        markActivity()
        return (output, exitCode)
    }

    /// Downloads a file from the cloud machine into the local workspace
    /// so the user can keep it on their iPhone.
    func pullFile(path: String, into workspace: WorkspaceRouting) async throws -> String {
        guard let sandboxID, let envdToken else {
            throw LLMError.badResponse("Cloud computer is not running.")
        }
        var components = URLComponents(
            url: Self.sandboxBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(envdToken, forHTTPHeaderField: "X-Access-Token")
        request.setValue(sandboxID, forHTTPHeaderField: "E2b-Sandbox-Id")
        request.setValue("49983", forHTTPHeaderField: "E2b-Sandbox-Port")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse("Cloud file download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }

        let name = (path as NSString).lastPathComponent
        let url = try workspace.writeData(path: name, data: data)
        NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
        return url.lastPathComponent
    }

    /// Pulls a cloud file into the workspace under its relative path
    /// (creating folders as needed) — used by file reads in cloud mode.
    func pullFileRelative(path: String, into workspace: WorkspaceRouting) async throws -> String {
        guard let sandboxID, let envdToken else {
            throw LLMError.badResponse("Cloud computer is not running.")
        }
        var components = URLComponents(
            url: Self.sandboxBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(envdToken, forHTTPHeaderField: "X-Access-Token")
        request.setValue(sandboxID, forHTTPHeaderField: "E2b-Sandbox-Id")
        request.setValue("49983", forHTTPHeaderField: "E2b-Sandbox-Port")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse("Cloud file download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        let url = try workspace.writeData(path: path, data: data)
        NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
        return url.lastPathComponent
    }

    /// Uploads a local file (or folder-relative path) from the workspace
    /// to the cloud machine under the same relative path, so the same
    /// files exist on both machines.
    func pushFile(path: String, data: Data) async throws {
        try await ensureRunning()
        guard let sandboxID, let envdToken else {
            throw LLMError.badResponse("Cloud computer is not running.")
        }

        let boundary = "astral-\(UUID().uuidString)"
        var components = URLComponents(
            url: Self.sandboxBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(envdToken, forHTTPHeaderField: "X-Access-Token")
        request.setValue(sandboxID, forHTTPHeaderField: "E2b-Sandbox-Id")
        request.setValue("49983", forHTTPHeaderField: "E2b-Sandbox-Port")
        request.timeoutInterval = 120

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = (path as NSString).lastPathComponent
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (_, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMError.badResponse(
                "Cloud file upload failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        markActivity()
    }

    /// Kills the cloud machine (frees the user's credits).
    func kill(reason: String = "session ended") async {
        await reset()
    }

    /// Called when an agent turn finishes: the sandbox is shut down a few
    /// seconds later unless the user is personally driving the cloud
    /// shell tab — the machine never stays billed while idle.
    func shutdownAfterTurn() {
        guard isRunning || status == .starting else { return }
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // The user typed a cloud command within the last two minutes:
            // keep their session alive.
            if Date().timeIntervalSince(self.lastUserCommand) < 120 {
                self.startKeepAlive()
                return
            }
            self.shuttingDown = true
            await self.reset()
            self.shuttingDown = false
            self.appendLog("[cloud computer powered off — job finished]")
        }
    }

    private func reset() async {
        let id = sandboxID
        sandboxID = nil
        envdToken = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        status = .off
        guard let id else { return }
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("sandboxes/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue(apiKey ?? "", forHTTPHeaderField: "X-API-Key")
        _ = try? await Self.session.data(for: request)
    }

    // MARK: Lifecycle

    func ensureRunning() async throws {
        if sandboxID != nil, envdToken != nil, status == .running {
            refreshTimeout()
            return
        }
        status = .starting

        // The create body per the official E2B API reference:
        // templateID is REQUIRED (this was the V4.0 bug — a missing
        // templateID made every boot fail with the schema validation
        // error "Error at /templateID"). "base" is the official Ubuntu
        // template Sandbox.create() uses.
        let body: [String: Any] = [
            "templateID": "base",
            "timeout": 1800,
        ]

        // v2 first, deprecated v1 as fallback — identical responses.
        let endpoints = ["v2/sandboxes", "sandboxes"]
        var lastErrorBody = ""
        var lastStatusCode = 0
        var created: (sandboxID: String, envdToken: String)?

        for endpoint in endpoints {
            var request = URLRequest(
                url: Self.apiBase.appendingPathComponent(endpoint))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey ?? "", forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 90
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, response) = try await Self.session.data(for: request)
            let http = response as? HTTPURLResponse
            lastStatusCode = http?.statusCode ?? 0
            lastErrorBody = String(data: data.prefix(500), encoding: .utf8) ?? ""

            guard (200...299).contains(http?.statusCode ?? 0) else { continue }

            if let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
               let sandboxID = object["sandboxID"] as? String,
               let envdToken = object["envdAccessToken"] as? String {
                created = (sandboxID, envdToken)
                break
            }
        }

        guard let boot = created else {
            let message = lastErrorBody.isEmpty ? "HTTP \(lastStatusCode)" : lastErrorBody
            status = .failed(String(message.prefix(180)))
            throw LLMError.badResponse(
                "Could not start the cloud computer: \(String(message.prefix(200)))")
        }

        self.sandboxID = boot.sandboxID
        self.envdToken = boot.envdToken
        status = .running
        markActivity()
        startKeepAlive()
    }

    /// E2B sandboxes auto-destroy after their timeout. While the agent is
    /// actively working we push the lease forward every 10 minutes.
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                // Idle for over 5 minutes? Let the lease expire naturally.
                if Date().timeIntervalSince(self.lastActivity) > 300 {
                    await self.reset()
                    return
                }
                self.refreshTimeout()
            }
        }
    }

    private func refreshTimeout() {
        guard let sandboxID else { return }
        var request = URLRequest(
            url: Self.apiBase.appendingPathComponent("sandboxes/\(sandboxID)/timeout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey ?? "", forHTTPHeaderField: "X-API-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["timeout": 1800])
        request.timeoutInterval = 30
        _ = Task { try? await Self.session.data(for: request) }
    }

    private func markActivity() {
        lastActivity = Date()
    }

    // MARK: Connect protocol

    /// Builds the framed Connect request for process.Process/Start.
    private func startRequest(command: String, timeoutMS: Int) throws -> URLRequest {
        guard let sandboxID, let envdToken else {
            throw LLMError.badResponse("Cloud computer is not running.")
        }

        let body: [String: Any] = [
            "process": [
                "cmd": "/bin/bash",
                "args": ["-lc", command],
            ],
            "envs": [],
            "cwd": "/home/user",
            "user": "user",
            "onStdout": ["format": 2],
            "onStderr": ["format": 2],
            "onExit": [:],
        ]
        let json = try JSONSerialization.data(withJSONObject: body, options: [])

        var request = URLRequest(
            url: Self.sandboxBase.appendingPathComponent("process.Process/Start"))
        request.httpMethod = "POST"
        request.setValue("application/connect+json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(String(timeoutMS), forHTTPHeaderField: "Connect-Timeout-Ms")
        request.setValue(sandboxID, forHTTPHeaderField: "E2b-Sandbox-Id")
        request.setValue("49983", forHTTPHeaderField: "E2b-Sandbox-Port")
        request.setValue(envdToken, forHTTPHeaderField: "X-Access-Token")
        request.timeoutInterval = max(30, TimeInterval(timeoutMS) / 1000 + 15)
        request.httpBody = Self.connectFrame(json)
        return request
    }

    /// Encodes one Connect envelope: flags byte (0) + 4-byte big-endian
    /// length + payload.
    nonisolated static func connectFrame(_ payload: Data) -> Data {
        var frame = Data([0])
        var length = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &length, count: 4))
        frame.append(payload)
        return frame
    }

    /// Decodes every payload frame from a Connect response body.
    nonisolated static func parseConnectFrames(_ data: Data) -> [Data] {
        var payloads: [Data] = []
        var index = data.startIndex
        while data.distance(from: index, to: data.endIndex) >= 5 {
            let flags = data[index]
            let lengthBytes = data[data.index(after: index)...data.index(index, offsetBy: 4)]
            let length = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let payloadStart = data.index(index, offsetBy: 5)
            guard data.distance(from: payloadStart, to: data.endIndex) >= Int(length) else {
                break
            }
            let payloadEnd = data.index(payloadStart, offsetBy: Int(length))
            if flags & 0x02 == 0 {
                payloads.append(Data(data[payloadStart..<payloadEnd]))
            }
            index = payloadEnd
        }
        return payloads
    }
}
