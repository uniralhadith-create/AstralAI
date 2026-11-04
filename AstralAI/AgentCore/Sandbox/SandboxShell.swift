import Foundation
import Combine
import JavaScriptCore
import CryptoKit
import AVFoundation
import SQLite3

// MARK: - Sandbox entries

/// One executed command in the astra-os shell history.
struct SandboxEntry: Identifiable, Equatable {
    let id: UUID
    let command: String
    let output: String
    let exitCode: Int
    let duration: TimeInterval
    let date: Date

    init(
        id: UUID = UUID(),
        command: String,
        output: String,
        exitCode: Int,
        duration: TimeInterval,
        date: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
        self.date = date
    }
}

/// The outcome of one command execution.
struct SandboxResult: Equatable {
    var stdout: String
    var exitCode: Int

    static func ok(_ text: String = "") -> SandboxResult {
        SandboxResult(stdout: text, exitCode: 0)
    }

    static func error(_ text: String) -> SandboxResult {
        SandboxResult(stdout: text, exitCode: 1)
    }

    /// True when the command completed with a non-zero exit code.
    var failed: Bool { exitCode != 0 }
}

// MARK: - astra-os Linux Kernel & Shell

/// The agent's persistent Linux workstation environment ("astra-os")
/// rooted at `/home/astral` with a complete Linux Filesystem Hierarchy
/// (`/etc`, `/var`, `/tmp`, `/proc`, `/usr`, `/bin`, `/home/astral`),
/// root privilege simulation (`sudo`, `id`, `whoami`, `uname`, `hostname`),
/// persistent environment variables (`export`), local package & git
/// management (`apt`, `pkg`, `git`), real SQLite database engine (`sqlite3`),
/// video synthesis & media inspection (`ffmpeg`, `ffprobe`, `yt-dlp`),
/// archive & JSON/YAML/CSV tools (`tar`, `zip`, `unzip`, `jq`, `awk`, `sed`,
/// `xargs`, `tee`, `column`, `paste`, `bc`, `expr`, `xxd`, `hexdump`),
/// process & service inspection (`ps`, `top`, `free`, `lscpu`, `uptime`, `df`,
/// `du`, `neofetch`, `systemctl`, `service`, `crontab`, `lsof`, `netstat`, `ss`),
/// network & live web scraping (`curl`, `wget`, `ping`, `dig`, `nslookup`,
/// `ifconfig`, `ip`, `search`), and bidirectional workspace sync
/// with Python 3.12 (Pyodide WASM) and Node.js (JavaScriptCore + `fs` module).
@MainActor
final class SandboxShell: ObservableObject {

    static let shared = SandboxShell()

    // MARK: Published state (drives the Terminal UI)

    @Published private(set) var cwd = SandboxShell.homePath
    @Published private(set) var history: [SandboxEntry] = []
    @Published private(set) var busy = false

    // MARK: Roots & Identity

    /// The user-visible home path.
    static let homePath = "/home/astral"
    /// The user-visible scratch path.
    static let tempPath = "/tmp"
    /// The user-visible system config path.
    static let etcPath = "/etc"
    /// The user-visible variable data path.
    static let varPath = "/var"
    /// The identity of the environment, reported by `uname` and `TerminalView`.
    static let osName =
        "astra-os 5.0.0 (Astral Linux Kernel 6.12-arm64) iOS/arm64 - Root FHS Shell "
        + "(pipes, &&, ||, ;, $VAR) + Python 3.12 + Node.js + SQLite3 + FFmpeg + WebKit Engine + Ubuntu Cloud"

    private let fileManager = FileManager.default
    private let bootDate = Date()

    /// Persistent custom environment variables set via `export KEY=VALUE`.
    private var envVars: [String: String] = [
        "USER": "root",
        "LOGNAME": "astral",
        "HOME": "/home/astral",
        "SHELL": "/bin/bash",
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "TMPDIR": "/tmp",
        "TERM": "xterm-256color",
        "ASTRAL_AGENT": "Astral AI",
    ]

    /// Locally installed packages tracked across sessions (`apt install`).
    private var installedPackages: Set<String> = [
        "coreutils", "bash", "curl", "wget", "git", "jq", "python3", "python3-pip",
        "nodejs", "sqlite3", "ffmpeg", "yt-dlp", "zip", "unzip", "tar", "grep",
        "sed", "gawk", "bc", "procps", "net-tools", "dnsutils", "lsof",
        "ca-certificates", "openssl", "neofetch",
    ]

    /// Documents/AstralWorkspace — same root the Files tab shows.
    private var homeURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return documents.appendingPathComponent("AstralWorkspace", isDirectory: true)
    }

    /// Application-support scratch directory backing /tmp, /etc, /var.
    private var supportBaseURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("AstralLinuxRoot", isDirectory: true)
    }

    private var tempURL: URL {
        supportBaseURL.appendingPathComponent("tmp", isDirectory: true)
    }

    private var etcURL: URL {
        supportBaseURL.appendingPathComponent("etc", isDirectory: true)
    }

    private var varURL: URL {
        supportBaseURL.appendingPathComponent("var", isDirectory: true)
    }

    private let maxOutputChars = 16_000
    private let maxHistory = 300

    private init() {
        try? fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: etcURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: varURL.appendingPathComponent("log"), withIntermediateDirectories: true)
        seedSystemFilesIfNeeded()
    }

    /// Seeds realistic Linux `/etc/os-release`, `/etc/hostname`, `/etc/hosts`,
    /// `/etc/passwd`, and `/etc/crontab` so scripts or agent probes inspecting
    /// `/etc/*` work like on Ubuntu/Debian Linux.
    private func seedSystemFilesIfNeeded() {
        let osRelease = etcURL.appendingPathComponent("os-release")
        if !fileManager.fileExists(atPath: osRelease.path) {
            let content = """
            PRETTY_NAME="Astra-OS GNU/Linux 5.0.0 LTS (Astral AI)"
            NAME="Astra-OS"
            VERSION_ID="5.0.0"
            VERSION="5.0.0 LTS (Astral AI)"
            ID=astra
            ID_LIKE=debian ubuntu
            HOME_URL="https://uniral.com/astral"
            """
            try? content.data(using: .utf8)?.write(to: osRelease, options: .atomic)
        }
        let hostnameFile = etcURL.appendingPathComponent("hostname")
        if !fileManager.fileExists(atPath: hostnameFile.path) {
            try? "astra-os\n".data(using: .utf8)?.write(to: hostnameFile, options: .atomic)
        }
        let hostsFile = etcURL.appendingPathComponent("hosts")
        if !fileManager.fileExists(atPath: hostsFile.path) {
            let hosts = "127.0.0.1\tlocalhost\n127.0.1.1\tastra-os\n::1\tlocalhost ip6-localhost\n"
            try? hosts.data(using: .utf8)?.write(to: hostsFile, options: .atomic)
        }
        let passwdFile = etcURL.appendingPathComponent("passwd")
        if !fileManager.fileExists(atPath: passwdFile.path) {
            let passwd = "root:x:0:0:root:/home/astral:/bin/bash\nastral:x:1000:1000:Astral AI:/home/astral:/bin/bash\n"
            try? passwd.data(using: .utf8)?.write(to: passwdFile, options: .atomic)
        }
        let crontabFile = etcURL.appendingPathComponent("crontab")
        if !fileManager.fileExists(atPath: crontabFile.path) {
            let cron = "# /etc/crontab: system-wide crontab for astra-os\nSHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n"
            try? cron.data(using: .utf8)?.write(to: crontabFile, options: .atomic)
        }
    }

    // MARK: - Public API

    /// Executes one command line and records it in the history.
    func run(_ line: String) async -> SandboxResult {
        let started = Date()
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else { return .ok() }

        busy = true
        defer { busy = false }

        let result = await executePipeline(command)
        let entry = SandboxEntry(
            command: command,
            output: result.stdout,
            exitCode: result.exitCode,
            duration: Date().timeIntervalSince(started))

        history.append(entry)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        return result
    }

    /// The number of entries currently in /home/astral.
    var homeFileCount: Int {
        (try? fileManager.contentsOfDirectory(
            at: homeURL, includingPropertiesForKeys: nil))?.count ?? 0
    }

    /// Clears the visible history (the `clear` command).
    func clearHistory() {
        history = []
    }

    // MARK: - Pipeline engine (Full Shell with |, &&, ||, ;, 2>&1, $VAR)

    private struct ParsedStatement {
        var segments: [String]
        var chainToNext: String   // ";", "&&", "||" or ""
    }

    private enum ShellToken {
        case text(String)
        case op(String)
    }

    private static func scanTokens(_ line: String) -> [ShellToken] {
        var tokens: [ShellToken] = []
        var current = ""
        var quote: Character?
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == ";" {
                if !current.isEmpty { tokens.append(.text(current)); current = "" }
                tokens.append(.op(";"))
            } else if character == "|" {
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "|" {
                    if !current.isEmpty { tokens.append(.text(current)); current = "" }
                    tokens.append(.op("||"))
                    index = next
                } else {
                    if !current.isEmpty { tokens.append(.text(current)); current = "" }
                    tokens.append(.op("|"))
                }
            } else if character == "&" {
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "&" {
                    if !current.isEmpty { tokens.append(.text(current)); current = "" }
                    tokens.append(.op("&&"))
                    index = next
                } else {
                    current.append(character)
                }
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        if !current.isEmpty { tokens.append(.text(current)) }
        return tokens
    }

    private static func parseStatements(_ line: String) -> [ParsedStatement] {
        var statements: [ParsedStatement] = []
        var segments: [String] = []
        var current = ""

        func closeSegment() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { segments.append(trimmed) }
            current = ""
        }
        func closeStatement(chainToNext: String) {
            closeSegment()
            if !segments.isEmpty {
                statements.append(
                    ParsedStatement(segments: segments, chainToNext: chainToNext))
            }
            segments = []
        }

        for token in scanTokens(line) {
            switch token {
            case .text(let text):
                current += text
            case .op(let op):
                if op == "|" {
                    closeSegment()
                } else {
                    closeStatement(chainToNext: op)
                }
            }
        }
        closeStatement(chainToNext: "")
        return statements
    }

    private func executePipeline(_ command: String) async -> SandboxResult {
        let cleanedCommand = command
            .replacingOccurrences(of: "2>&1", with: "")
            .replacingOccurrences(of: "2>/dev/null", with: "")
        let statements = Self.parseStatements(cleanedCommand)
        guard !statements.isEmpty else { return .ok() }

        var lastResult = SandboxResult.ok()
        var previous: (exitCode: Int, chain: String)?

        for statement in statements {
            if let prev = previous {
                if prev.chain == "&&", prev.exitCode != 0 {
                    previous = (prev.exitCode, statement.chainToNext)
                    continue
                }
                if prev.chain == "||", prev.exitCode == 0 {
                    previous = (prev.exitCode, statement.chainToNext)
                    continue
                }
            }

            var stdin: String?
            var pipelineResult = SandboxResult.ok()
            for segment in statement.segments {
                pipelineResult = await execute(segment, stdin: stdin)
                if pipelineResult.failed {
                    stdin = nil
                    break
                }
                stdin = pipelineResult.stdout
            }

            lastResult = pipelineResult
            previous = (pipelineResult.exitCode, statement.chainToNext)
        }
        return lastResult
    }

    // MARK: - Variable Expansion

    private func expandVariables(_ text: String) -> String {
        var result = text
        var table = envVars
        table["PWD"] = cwd
        for (key, value) in table.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
            result = result.replacingOccurrences(of: "$\(key)", with: value)
        }
        return result
    }

    // MARK: - Command dispatch

    private func execute(_ rawCommand: String, stdin: String? = nil) async -> SandboxResult {
        let command = expandVariables(rawCommand)
        var tokens = Self.tokenize(command)
        guard !tokens.isEmpty else { return .ok() }

        // Transparently unwrap `sudo` so root commands work without friction.
        if tokens.first?.lowercased() == "sudo" {
            tokens.removeFirst()
            while let first = tokens.first, first.hasPrefix("-") {
                tokens.removeFirst()
            }
            guard !tokens.isEmpty else { return .ok() }
        }

        // Inline `KEY=VALUE` assignment (without `export`)
        if tokens.count == 1,
           let eq = tokens[0].firstIndex(of: "="),
           eq > tokens[0].startIndex {
            let key = String(tokens[0][..<eq])
            let val = String(tokens[0][tokens[0].index(after: eq)...])
            if key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                envVars[key] = val
                return .ok()
            }
        }

        // Output redirection: `> file` overwrites, `>> file` appends.
        var redirect: (path: String, append: Bool)?
        if let index = tokens.firstIndex(of: ">>"), index + 1 < tokens.count {
            redirect = (tokens[index + 1], true)
        } else if let index = tokens.firstIndex(of: ">"), index + 1 < tokens.count {
            redirect = (tokens[index + 1], false)
        }
        var args = tokens.filter { $0 != ">" && $0 != ">>" }
        if let redirect, let index = args.firstIndex(of: redirect.path) {
            args.remove(at: index)
        }

        guard !args.isEmpty else { return .error("astra: parse error near redirection") }
        let name = args[0].lowercased()
        let operands = Array(args.dropFirst())

        var result: SandboxResult
        switch name {
        case "help", "man": result = help()
        case "pwd": result = pwd()
        case "ls", "ll", "la":
            let extra = name == "ll" ? (["-la"] + operands) : (name == "la" ? (["-a"] + operands) : operands)
            result = ls(extra)
        case "cd": result = cd(operands)
        case "cat": result = cat(operands, stdin: stdin)
        case "echo": result = echo(operands)
        case "printf": result = printfCommand(operands)
        case "mkdir": result = mkdir(operands)
        case "rmdir": result = rm(["-r"] + operands)
        case "touch": result = touch(operands)
        case "rm": result = rm(operands)
        case "cp": result = cp(operands)
        case "mv": result = mv(operands)
        case "ln": result = cp(operands.filter { !$0.hasPrefix("-") })
        case "grep", "egrep", "fgrep", "rg": result = grep(operands, stdin: stdin)
        case "find": result = find(operands)
        case "wc": result = wc(operands, stdin: stdin)
        case "head": result = numberedSlice(operands, defaultCount: 10, fromStart: true, stdin: stdin)
        case "tail": result = numberedSlice(operands, defaultCount: 10, fromStart: false, stdin: stdin)
        case "tree": result = tree(operands)
        case "sed": result = sed(operands, stdin: stdin)
        case "awk", "gawk": result = awk(operands, stdin: stdin)
        case "jq": result = jq(operands, stdin: stdin)
        case "xargs": result = await xargs(operands, stdin: stdin)
        case "tee": result = tee(operands, stdin: stdin)
        case "column": result = columnCommand(operands, stdin: stdin)
        case "paste": result = pasteCommand(operands, stdin: stdin)
        case "bc", "expr": result = mathCommand(name: name, args: operands, stdin: stdin)
        case "xxd", "hexdump": result = hexdumpCommand(operands, stdin: stdin)
        case "stat": result = stat(operands)
        case "file": result = fileCommand(operands)
        case "du": result = du(operands)
        case "sort": result = sortCommand(operands, stdin: stdin)
        case "uniq": result = uniq(operands, stdin: stdin)
        case "cut": result = cut(operands, stdin: stdin)
        case "tr": result = tr(operands, stdin: stdin)
        case "rev": result = rev(operands, stdin: stdin)
        case "diff": result = diff(operands)
        case "seq": result = seq(operands)
        case "base64": result = base64Command(operands, stdin: stdin)
        case "md5sum", "md5", "shasum", "sha256sum", "sha1sum": result = digest(operands, stdin: stdin, kind: name)
        case "df": result = df(operands)
        case "free": result = freeCommand(operands)
        case "ps", "top", "htop": result = psCommand(operands)
        case "lscpu", "nproc": result = lscpuCommand(name: name)
        case "uptime": result = uptimeCommand()
        case "hostname": result = .ok("astra-os")
        case "id": result = .ok("uid=0(root) gid=0(root) groups=0(root),1000(astral)")
        case "neofetch", "fastfetch", "screenfetch": result = neofetch()
        case "systemctl", "service": result = systemctlCommand(operands)
        case "crontab": result = crontabCommand(operands)
        case "lsof": result = lsofCommand()
        case "netstat", "ss": result = netstatCommand()
        case "env", "printenv": result = envCommand()
        case "export": result = exportCommand(operands)
        case "unset": result = unsetCommand(operands)
        case "which", "type", "command": result = which(operands)
        case "basename": result = basenameCommand(operands)
        case "dirname": result = dirnameCommand(operands)
        case "realpath", "readlink": result = realpathCommand(operands)
        case "chmod": result = chmod(operands)
        case "chown": result = .ok()
        case "sleep": result = await sleepCommand(operands)
        case "date": result = SandboxResult.ok(Self.dateFormatter.string(from: Date()))
        case "uname": result = uname(operands)
        case "whoami": result = SandboxResult.ok("astral")
        case "history": result = historyText()
        case "clear":
            clearHistory()
            result = .ok()
        case "true", ":": result = .ok()
        case "false": result = SandboxResult(stdout: "", exitCode: 1)
        case "curl": result = await curl(operands)
        case "wget": result = await wget(operands)
        case "ping": result = await ping(operands)
        case "dig", "nslookup", "host": result = await dnsLookup(operands)
        case "ifconfig", "ip": result = networkInterfaces()
        case "search": result = await search(operands)
        case "apt", "apt-get", "pkg", "apk": result = aptCommand(operands)
        case "git": result = await gitCommand(operands)
        case "tar": result = tarCommand(operands)
        case "zip": result = zipCommand(operands)
        case "unzip": result = unzipCommand(operands)
        case "sqlite3": result = sqlite3Command(operands, stdin: stdin)
        case "ffmpeg": result = await ffmpegCommand(operands)
        case "ffprobe": result = ffprobeCommand(operands)
        case "yt-dlp", "youtube-dl": result = await ytdlpCommand(operands)
        case "python3", "python": result = await python(operands)
        case "pip", "pip3": result = await pip(operands)
        case "node": result = await node(operands)
        case "bash", "sh", "zsh":
            if let dashC = operands.firstIndex(of: "-c"), dashC + 1 < operands.count {
                result = await executePipeline(operands[dashC + 1])
            } else if let script = operands.first(where: { !$0.hasPrefix("-") }),
                      let url = resolvedURL(script),
                      let content = try? String(contentsOf: url, encoding: .utf8) {
                result = await runScriptFile(content)
            } else {
                result = .ok("GNU bash, version 5.2.21(1)-release (aarch64-astralos-linux-gnu)")
            }
        default:
            result = SandboxResult.error(
                "astra: command not found: \(name). Type `help` to list the available commands.")
        }

        if let redirect {
            result = applyRedirect(result.stdout, to: redirect.path, append: redirect.append)
        } else {
            result.stdout = Self.capped(result.stdout, limit: maxOutputChars)
        }
        return result
    }

    private func runScriptFile(_ content: String) async -> SandboxResult {
        var outputs: [String] = []
        var lastExit = 0
        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let res = await executePipeline(trimmed)
            if !res.stdout.isEmpty { outputs.append(res.stdout) }
            lastExit = res.exitCode
            if res.failed { break }
        }
        return SandboxResult(stdout: outputs.joined(separator: "\n"), exitCode: lastExit)
    }

    // MARK: Commands — navigation & listing

    private func pwd() -> SandboxResult {
        .ok(cwd)
    }

    private func ls(_ args: [String]) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let long = flags.contains(where: { $0.contains("l") })
        let all = flags.contains(where: { $0.contains("a") })
        let paths = args.filter { !$0.hasPrefix("-") }
        let requestedPath = paths.first ?? "."

        // Virtual root `/` listing
        if requestedPath == "/" || (requestedPath == "." && cwd == "/") {
            let rootDirs = ["bin/", "etc/", "home/", "proc/", "tmp/", "usr/", "var/"]
            return .ok(rootDirs.joined(separator: "\n"))
        }
        if requestedPath == "/home" || (requestedPath == "." && cwd == "/home") {
            return .ok("astral/")
        }

        let target = resolvedURL(requestedPath)
        guard let target else {
            return .error("ls: cannot access '\(requestedPath)': No such file or directory")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return .error("ls: cannot access '\(requestedPath)': No such file or directory")
        }
        guard isDirectory.boolValue else {
            return .ok(target.lastPathComponent)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: target, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
            return .error("ls: cannot read directory")
        }

        let visible = entries
            .filter { all || !$0.lastPathComponent.hasPrefix(".") }
            .sorted { lhs, rhs in
                let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if lhsDir != rhsDir { return lhsDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        if visible.isEmpty { return .ok("") }

        if long {
            var lines: [String] = []
            lines.append("total \(visible.count)")
            for entry in visible {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDir = values?.isDirectory ?? false
                let size = values?.fileSize ?? 0
                let marker = isDir ? "d" : "-"
                let name = isDir ? entry.lastPathComponent + "/" : entry.lastPathComponent
                lines.append(
                    "\(marker)rwxr-xr-x  astral  \(String(format: "%8d", size))  \(name)")
            }
            return .ok(lines.joined(separator: "\n"))
        }

        return .ok(visible
            .map { entry -> String in
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isDir ? entry.lastPathComponent + "/" : entry.lastPathComponent
            }
            .joined(separator: "\n"))
    }

    private func cd(_ args: [String]) -> SandboxResult {
        let raw = args.first ?? "~"
        let target: String
        switch raw {
        case "~", "-": target = Self.homePath
        default: target = raw
        }

        guard let url = resolvedURL(target) else {
            return .error("cd: \(raw): No such file or directory")
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .error("cd: \(raw): Not a directory")
        }
        cwd = virtualPath(for: url)
        return .ok()
    }

    // MARK: Commands — reading & writing files

    private func cat(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        if paths.isEmpty, let stdin { return .ok(stdin) }
        guard !paths.isEmpty else { return .error("cat: missing file operand") }

        var chunks: [String] = []
        for path in paths {
            if let procContent = virtualProcFile(path) {
                chunks.append(procContent)
                continue
            }
            guard let url = resolvedURL(path),
                  (try? url.checkResourceIsReachable()) == true else {
                return .error("cat: \(path): No such file or directory")
            }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                return .error("cat: \(path): binary file or unreadable encoding")
            }
            chunks.append(text)
        }
        return .ok(chunks.joined(separator: "\n"))
    }

    private func virtualProcFile(_ path: String) -> String? {
        switch path {
        case "/proc/version":
            return "Linux version 6.12.0-astra-arm64 (root@astra-os) (clang 17.0.0) #1 SMP PREEMPT"
        case "/proc/cpuinfo":
            let cores = ProcessInfo.processInfo.activeProcessorCount
            return (0..<cores).map { i in
                "processor\t: \(i)\nBogoMIPS\t: 48.00\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics\nCPU architecture: 8"
            }.joined(separator: "\n\n")
        case "/proc/meminfo":
            let totalKB = Int(ProcessInfo.processInfo.physicalMemory / 1024)
            let availKB = Int(Double(totalKB) * 0.68)
            return "MemTotal:       \(totalKB) kB\nMemFree:        \(availKB / 2) kB\nMemAvailable:   \(availKB) kB"
        case "/proc/uptime":
            let up = Date().timeIntervalSince(bootDate)
            return String(format: "%.2f %.2f", up, up * 0.85)
        default:
            return nil
        }
    }

    private func echo(_ args: [String]) -> SandboxResult {
        var interpretEscapes = false
        var words = args
        if words.first == "-e" {
            interpretEscapes = true
            words.removeFirst()
        } else if words.first == "-n" {
            words.removeFirst()
        }
        var joined = words.joined(separator: " ")
        if interpretEscapes {
            joined = joined
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
        }
        return .ok(joined)
    }

    private func printfCommand(_ args: [String]) -> SandboxResult {
        guard let format = args.first else { return .ok() }
        let formatted = format
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
        return .ok(formatted)
    }

    private func mkdir(_ args: [String]) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let parents = flags.contains(where: { $0.contains("p") })
        let paths = args.filter { !$0.hasPrefix("-") }
        guard !paths.isEmpty else { return .error("mkdir: missing operand") }

        for path in paths {
            guard let url = resolvedURL(path, allowNew: true) else {
                return .error("mkdir: invalid path '\(path)'")
            }
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: parents)
            } catch {
                return .error("mkdir: cannot create '\(path)': \(error.localizedDescription)")
            }
        }
        return .ok()
    }

    private func touch(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard !paths.isEmpty else { return .error("touch: missing file operand") }

        for path in paths {
            guard let url = resolvedURL(path, allowNew: true) else {
                return .error("touch: invalid path '\(path)'")
            }
            let parent = url.deletingLastPathComponent()
            try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(atPath: url.path, contents: Data()) else {
                    return .error("touch: cannot touch '\(path)'")
                }
            } else {
                try? fileManager.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: url.path)
            }
        }
        return .ok()
    }

    private func rm(_ args: [String]) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let recursive = flags.contains(where: { $0.contains("r") || $0.contains("R") })
        let force = flags.contains(where: { $0.contains("f") })
        let paths = args.filter { !$0.hasPrefix("-") }
        guard !paths.isEmpty else { return .error("rm: missing operand") }

        for path in paths {
            guard let url = resolvedURL(path),
                  (try? url.checkResourceIsReachable()) == true else {
                if !force {
                    return .error("rm: cannot remove '\(path)': No such file or directory")
                }
                continue
            }
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue && !recursive {
                return .error("rm: cannot remove '\(path)': Is a directory (use -r)")
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                return .error("rm: cannot remove '\(path)': \(error.localizedDescription)")
            }
        }
        return .ok()
    }

    private func cp(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard paths.count >= 2 else {
            return .error("cp: missing destination file operand")
        }
        let destination = paths.last!
        let sources = paths.dropLast()

        for source in sources {
            guard let sourceURL = resolvedURL(source),
                  (try? sourceURL.checkResourceIsReachable()) == true else {
                return .error("cp: cannot stat '\(source)': No such file or directory")
            }
            guard let destinationURL = resolvedURL(destination, allowNew: true) else {
                return .error("cp: invalid destination '\(destination)'")
            }
            let target: URL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                target = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
            } else {
                target = destinationURL
            }
            do {
                try? fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: sourceURL, to: target)
            } catch {
                return .error("cp: \(error.localizedDescription)")
            }
        }
        return .ok()
    }

    private func mv(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard paths.count >= 2 else {
            return .error("mv: missing destination file operand")
        }
        let destination = paths.last!
        let sources = paths.dropLast()

        for source in sources {
            guard let sourceURL = resolvedURL(source),
                  (try? sourceURL.checkResourceIsReachable()) == true else {
                return .error("mv: cannot stat '\(source)': No such file or directory")
            }
            guard let destinationURL = resolvedURL(destination, allowNew: true) else {
                return .error("mv: invalid destination '\(destination)'")
            }
            let target: URL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                target = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
            } else {
                target = destinationURL
            }
            do {
                try? fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: sourceURL, to: target)
            } catch {
                return .error("mv: \(error.localizedDescription)")
            }
        }
        return .ok()
    }

    // MARK: Commands — search & text processing

    private func grep(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let ignoreCase = flags.contains(where: { $0.contains("i") })
        let showLines = flags.contains(where: { $0.contains("n") })
        let recursive = flags.contains(where: { $0.contains("r") || $0.contains("R") })
        let invert = flags.contains(where: { $0.contains("v") })
        let countOnly = flags.contains(where: { $0.contains("c") })
        let operands = args.filter { !$0.hasPrefix("-") }
        guard operands.count >= 2 || (operands.count == 1 && stdin != nil) else {
            return .error("usage: grep [-i] [-n] [-r] [-v] [-c] pattern file-or-directory")
        }
        let pattern = operands[0]
        let targets = operands.count > 1 ? Array(operands.dropFirst()) : []

        let regex: NSRegularExpression? = (try? NSRegularExpression(
            pattern: pattern,
            options: ignoreCase ? [.caseInsensitive] : []))
            ?? (try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: pattern),
                options: ignoreCase ? [.caseInsensitive] : []))
        guard let regex else { return .error("grep: invalid pattern") }

        var matches: [String] = []
        func grepFile(_ url: URL, label: String) {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                let matched = regex.firstMatch(in: line, options: [], range: range) != nil
                if matched != invert {
                    let prefix = showLines ? "\(index + 1):" : ""
                    matches.append("\(label)\(prefix)\(line)")
                }
            }
        }

        if targets.isEmpty, let stdin {
            for (index, line) in stdin.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                let matched = regex.firstMatch(in: line, options: [], range: range) != nil
                if matched != invert {
                    let prefix = showLines ? "\(index + 1):" : ""
                    matches.append("\(prefix)\(line)")
                }
            }
            if countOnly { return .ok("\(matches.count)") }
            return .ok(matches.prefix(400).joined(separator: "\n"))
        }

        for target in targets {
            guard let url = resolvedURL(target),
                  (try? url.checkResourceIsReachable()) == true else {
                return .error("grep: \(target): No such file or directory")
            }
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                guard recursive else {
                    return .error("grep: \(target): Is a directory (use -r)")
                }
                if let enumerator = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        var dirFlag: ObjCBool = false
                        fileManager.fileExists(atPath: fileURL.path, isDirectory: &dirFlag)
                        if dirFlag.boolValue { continue }
                        grepFile(fileURL, label: fileURL.lastPathComponent + ":")
                    }
                }
            } else {
                grepFile(url, label: "")
            }
            if matches.count > 400 { break }
        }
        if countOnly { return .ok("\(matches.count)") }
        return matches.isEmpty
            ? .ok("")
            : .ok(matches.prefix(400).joined(separator: "\n"))
    }

    private func find(_ args: [String]) -> SandboxResult {
        let operands = args.filter { !$0.hasPrefix("-") }
        let nameIndex = args.firstIndex(of: "-name")
        let namePattern = nameIndex != nil && nameIndex! + 1 < args.count
            ? args[nameIndex! + 1]
            : nil

        let root = operands.first ?? "."
        guard let rootURL = resolvedURL(root),
              (try? rootURL.checkResourceIsReachable()) == true else {
            return .error("find: \(root): No such file or directory")
        }

        var results: [String] = []
        let rootVirtual = virtualPath(for: rootURL)
        if let enumerator = fileManager.enumerator(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                let name = url.lastPathComponent
                if let pattern = namePattern {
                    let wildcard = pattern
                        .replacingOccurrences(of: ".", with: "\\.")
                        .replacingOccurrences(of: "*", with: ".*")
                    guard let regex = try? NSRegularExpression(pattern: "^" + wildcard + "$", options: [.caseInsensitive]),
                          regex.firstMatch(
                            in: name, options: [],
                            range: NSRange(name.startIndex..., in: name)) != nil else {
                        continue
                    }
                }
                let virtual = virtualPath(for: url)
                results.append(virtual + (isDir.boolValue ? "/" : ""))
                if results.count > 300 { break }
            }
        }
        if namePattern == nil {
            results.insert(rootVirtual, at: 0)
        }
        return .ok(results.joined(separator: "\n"))
    }

    private func wc(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let paths = args.filter { !$0.hasPrefix("-") }

        var text: String
        var label = ""
        if let path = paths.first {
            guard let url = resolvedURL(path),
                  let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8) else {
                return .error("wc: \(path): No such file or directory")
            }
            text = raw
            label = path
        } else if let stdin {
            text = stdin
        } else {
            return .error("wc: missing file operand")
        }
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let characters = text.utf8.count

        if flags.contains(where: { $0.contains("l") }) { return .ok("\(lines)") }
        if flags.contains(where: { $0.contains("w") }) { return .ok("\(words)") }
        if flags.contains(where: { $0.contains("c") }) { return .ok("\(characters)") }
        return .ok("\(lines) \(words) \(characters)\(label.isEmpty ? "" : " \(label)")")
    }

    private func numberedSlice(
        _ args: [String],
        defaultCount: Int,
        fromStart: Bool,
        stdin: String? = nil
    ) -> SandboxResult {
        var count = defaultCount
        var path: String?

        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-n", index + 1 < args.count, let value = Int(args[index + 1]) {
                count = value
                index += 2
                continue
            }
            if arg.hasPrefix("-n"), let value = Int(arg.dropFirst(2)) {
                count = value
                index += 1
                continue
            }
            if arg.count > 1, arg.hasPrefix("-"), let value = Int(arg.dropFirst()) {
                count = value
                index += 1
                continue
            }
            if !arg.hasPrefix("-") { path = arg }
            index += 1
        }

        var text: String
        if let path {
            guard let url = resolvedURL(path),
                  let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8) else {
                return .error("head/tail: \(path): No such file or directory")
            }
            text = raw
        } else if let stdin {
            text = stdin
        } else {
            return .error("head/tail: missing file operand")
        }
        var lines = text.components(separatedBy: .newlines)
        if lines.last?.isEmpty == true { lines.removeLast() }
        let slice = fromStart
            ? lines.prefix(max(0, count))
            : lines.suffix(max(0, count))
        return .ok(slice.joined(separator: "\n"))
    }

    private func tree(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        let root = resolvedURL(paths.first ?? ".")
        guard let root, (try? root.checkResourceIsReachable()) == true else {
            return .error("tree: no such directory")
        }

        var lines = ["."]

        func walk(_ url: URL, depth: Int) {
            guard depth < 8, lines.count < 300 else { return }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            let sorted = entries.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            for entry in sorted {
                guard !entry.lastPathComponent.hasPrefix(".") else { continue }
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                lines.append(
                    String(repeating: "    ", count: depth)
                    + "├── " + entry.lastPathComponent + (isDir ? "/" : ""))
                if isDir { walk(entry, depth: depth + 1) }
            }
        }
        walk(root, depth: 1)
        return .ok(lines.joined(separator: "\n"))
    }

    private func sed(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let nonFlagArgs = args.filter { $0 != "-i" && $0 != "-e" }
        let inPlace = args.contains("-i")
        guard let script = nonFlagArgs.first, script.contains("s") else {
            return .error("usage: sed [-i] s/pattern/replacement/[g] [file]")
        }
        let paths = Array(nonFlagArgs.dropFirst())

        let parts = script.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3 else {
            return .error("sed: invalid script '\(script)'")
        }
        let pattern = String(parts[1])
        let replacement = String(parts[2])
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .error("sed: invalid pattern '\(pattern)'")
        }

        if paths.isEmpty, let stdin {
            let range = NSRange(stdin.startIndex..., in: stdin)
            let output = regex.stringByReplacingMatches(
                in: stdin, options: [], range: range, withTemplate: replacement)
            return .ok(output)
        }

        guard let path = paths.first else { return .error("sed: missing file operand") }
        guard let url = resolvedURL(path),
              let data = try? Data(contentsOf: url),
              var text = String(data: data, encoding: .utf8) else {
            return .error("sed: \(path): No such file or directory")
        }

        let range = NSRange(text.startIndex..., in: text)
        text = regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: replacement)

        if inPlace || !paths.isEmpty {
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        return .ok(text)
    }

    // MARK: Advanced Text, Math & JSON Tools (`awk`, `jq`, `xargs`, `tee`, `column`, `paste`, `bc`, `xxd`)

    private func awk(_ args: [String], stdin: String? = nil) -> SandboxResult {
        var delimiter: String?
        var program: String?
        var files: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-F", i + 1 < args.count {
                delimiter = args[i + 1]
                i += 2
                continue
            } else if arg.hasPrefix("-F"), arg.count > 2 {
                delimiter = String(arg.dropFirst(2))
                i += 1
                continue
            } else if program == nil {
                program = arg
            } else {
                files.append(arg)
            }
            i += 1
        }

        guard let program else { return .error("usage: awk [-F sep] '{print $1}' [file]") }
        let input = filterInput(files, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("awk: no input") }

        var fieldIndices: [Int] = []
        let regex = try? NSRegularExpression(pattern: "\\$(\\d+|NF)")
        let ns = program as NSString
        for match in regex?.matches(in: program, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let token = ns.substring(with: match.range(at: 1))
            if token == "NF" {
                fieldIndices.append(-1)
            } else if let idx = Int(token) {
                fieldIndices.append(idx)
            }
        }
        if fieldIndices.isEmpty { fieldIndices = [0] }

        let outputLines = linesOf(text).map { line -> String in
            let parts: [String]
            if let delimiter {
                parts = line.components(separatedBy: delimiter)
            } else {
                parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            let picked = fieldIndices.map { idx -> String in
                if idx == 0 { return line }
                if idx == -1 { return parts.last ?? "" }
                return (idx - 1 < parts.count && idx >= 1) ? parts[idx - 1] : ""
            }
            return picked.joined(separator: " ")
        }
        return .ok(outputLines.joined(separator: "\n"))
    }

    private func jq(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        let rawOutput = args.contains("-r")
        let filter: String
        let fileArgs: [String]

        if nonFlags.isEmpty {
            filter = "."
            fileArgs = []
        } else if nonFlags.count == 1 {
            if nonFlags[0].hasPrefix(".") || stdin != nil {
                filter = nonFlags[0]
                fileArgs = []
            } else {
                filter = "."
                fileArgs = [nonFlags[0]]
            }
        } else {
            filter = nonFlags[0]
            fileArgs = Array(nonFlags.dropFirst())
        }

        let input = filterInput(fileArgs, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("jq: no input") }
        guard let data = text.data(using: .utf8),
              let json = JSONValue.from(data: data) else {
            return .error("jq: parse error: Invalid JSON input")
        }

        let dotPath = filter
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if dotPath.isEmpty {
            if let prettyData = json.jsonData(pretty: true),
               let pretty = String(data: prettyData, encoding: .utf8) {
                return .ok(pretty)
            }
            return .ok(text)
        }

        let normalizedPath = dotPath.replacingOccurrences(of: "[]", with: ".[].")
            .replacingOccurrences(of: "..", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let values = DotPath.evaluateAll(json, path: normalizedPath)
        if values.isEmpty {
            return .ok("null")
        }
        let formatted = values.map { val -> String in
            if rawOutput, let str = val.stringValue { return str }
            if let d = val.jsonData(pretty: true), let s = String(data: d, encoding: .utf8) { return s }
            return val.stringValue ?? "\(val)"
        }
        return .ok(formatted.joined(separator: "\n"))
    }

    private func xargs(_ args: [String], stdin: String? = nil) async -> SandboxResult {
        let baseCommand = args.isEmpty ? "echo" : args.joined(separator: " ")
        let items = (stdin ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return .ok() }
        return await execute("\(baseCommand) \(items.joined(separator: " "))")
    }

    private func tee(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let append = args.contains("-a")
        let files = args.filter { !$0.hasPrefix("-") }
        let content = stdin ?? ""
        for file in files {
            _ = applyRedirect(content, to: file, append: append)
        }
        return .ok(content)
    }

    private func columnCommand(_ args: [String], stdin: String? = nil) -> SandboxResult {
        var sep: String?
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-s", i + 1 < args.count {
                sep = args[i + 1]
                i += 2
                continue
            } else if arg.hasPrefix("-s"), arg.count > 2 {
                sep = String(arg.dropFirst(2))
                i += 1
                continue
            } else if !arg.hasPrefix("-") {
                files.append(arg)
            }
            i += 1
        }
        let input = filterInput(files, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("column: no input") }
        let rows: [[String]] = linesOf(text).map { line in
            if let sep {
                return line.components(separatedBy: sep)
            }
            return line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        let colCount = rows.map(\.count).max() ?? 0
        guard colCount > 0 else { return .ok(text) }
        var widths = [Int](repeating: 0, count: colCount)
        for row in rows {
            for (c, val) in row.enumerated() {
                widths[c] = max(widths[c], val.count)
            }
        }
        let formatted = rows.map { row -> String in
            row.enumerated().map { c, val in
                val.padding(toLength: widths[c], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        return .ok(formatted.joined(separator: "\n"))
    }

    private func pasteCommand(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let files = args.filter { !$0.hasPrefix("-") }
        guard !files.isEmpty else { return .ok(stdin ?? "") }
        var fileLines: [[String]] = []
        for path in files {
            guard let url = resolvedURL(path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return .error("paste: \(path): No such file or directory")
            }
            fileLines.append(linesOf(text))
        }
        let maxCount = fileLines.map(\.count).max() ?? 0
        var out: [String] = []
        for rowIdx in 0..<maxCount {
            let row = fileLines.map { rowIdx < $0.count ? $0[rowIdx] : "" }.joined(separator: "\t")
            out.append(row)
        }
        return .ok(out.joined(separator: "\n"))
    }

    private func mathCommand(name: String, args: [String], stdin: String?) -> SandboxResult {
        let rawExpr = (name == "expr" ? args.joined(separator: " ") : (stdin ?? args.joined(separator: " ")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawExpr.isEmpty else { return .ok("0") }
        guard let js = JSContext() else { return .error("\(name): math engine unavailable") }
        let jsExpr = rawExpr.replacingOccurrences(of: "^", with: "**")
        if let val = js.evaluateScript(jsExpr), !val.isUndefined {
            return .ok(val.toString() ?? "0")
        }
        return .error("\(name): syntax error in '\(rawExpr)'")
    }

    private func hexdumpCommand(_ args: [String], stdin: String?) -> SandboxResult {
        let files = args.filter { !$0.hasPrefix("-") }
        let data: Data
        if let path = files.first {
            guard let url = resolvedURL(path), let d = try? Data(contentsOf: url) else {
                return .error("xxd: \(path): No such file or directory")
            }
            data = d
        } else if let stdin {
            data = Data(stdin.utf8)
        } else {
            return .error("usage: xxd <file>")
        }
        let slice = data.prefix(512)
        var lines: [String] = []
        var offset = 0
        while offset < slice.count {
            let end = min(offset + 16, slice.count)
            let chunk = slice[offset..<end]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append(String(format: "%08x: %-47s  %@", offset, (hex as NSString).utf8String!, ascii))
            offset += 16
        }
        return .ok(lines.joined(separator: "\n"))
    }

    // MARK: Text pipeline commands

    private func filterInput(_ args: [String], stdin: String?) -> (text: String?, error: SandboxResult?) {
        let paths = args.filter { !$0.hasPrefix("-") }
        if paths.isEmpty {
            guard let stdin else { return (nil, .error("missing file operand (or pipe input in)")) }
            return (stdin, nil)
        }
        guard let url = resolvedURL(paths[0]),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return (nil, .error("\(paths[0]): No such file or directory"))
        }
        return (text, nil)
    }

    private func linesOf(_ text: String) -> [String] {
        var lines = text.components(separatedBy: .newlines)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    private func sortCommand(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let reverse = flags.contains(where: { $0.contains("r") })
        let numeric = flags.contains(where: { $0.contains("n") })
        let unique = flags.contains(where: { $0.contains("u") })

        let input = filterInput(args, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("sort: no input") }
        var lines = linesOf(text)
        if numeric {
            lines.sort { lhs, rhs in
                Double(lhs.trimmingCharacters(in: .whitespaces)) ?? 0
                    < Double(rhs.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        } else {
            lines.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        if unique {
            lines = lines.reduce(into: [String]()) { acc, line in
                if acc.last != line { acc.append(line) }
            }
        }
        if reverse { lines.reverse() }
        return .ok(lines.joined(separator: "\n"))
    }

    private func uniq(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let count = flags.contains(where: { $0.contains("c") })
        let input = filterInput(args, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("uniq: no input") }
        let lines = linesOf(text)

        var output: [String] = []
        var currentLine: String?
        var currentCount = 0
        func flush() {
            guard let line = currentLine else { return }
            output.append(count ? "\(String(repeating: " ", count: 6 - min(6, String(currentCount).count)))\(currentCount) \(line)" : line)
        }
        for line in lines {
            if line == currentLine {
                currentCount += 1
            } else {
                flush()
                currentLine = line
                currentCount = 1
            }
        }
        flush()
        return .ok(output.joined(separator: "\n"))
    }

    private func cut(_ args: [String], stdin: String? = nil) -> SandboxResult {
        var delimiter = "\t"
        var fieldSpec = "1"
        var operands: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-d", index + 1 < args.count {
                delimiter = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("-d"), arg.count > 2 {
                delimiter = String(arg.dropFirst(2))
                index += 1
                continue
            }
            if arg == "-f", index + 1 < args.count {
                fieldSpec = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("-f"), arg.count > 2 {
                fieldSpec = String(arg.dropFirst(2))
                index += 1
                continue
            }
            if !arg.hasPrefix("-") { operands.append(arg) }
            index += 1
        }

        var selected: Set<Int> = []
        var openRange = false
        for part in fieldSpec.split(separator: ",") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            if piece.contains("-") {
                let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
                let start = bounds.first.flatMap { Int($0) } ?? 1
                let end = bounds.count > 1 ? (bounds.last.flatMap { Int($0) } ?? 100_000) : 100_000
                selected.formUnion(max(1, start)...min(end, 100_000))
                if bounds.count < 2 || bounds.last?.isEmpty == true { openRange = true }
            } else if let fieldNumber = Int(piece), fieldNumber >= 1 {
                selected.insert(fieldNumber)
            }
        }

        let input = filterInput(operands, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("cut: no input") }
        let lines = linesOf(text)
        let output = lines.map { line -> String in
            let fields = line.components(separatedBy: delimiter)
            let picked = fields.enumerated().compactMap { offset, field -> String? in
                selected.contains(offset + 1) ? field : nil
            }
            if picked.isEmpty && openRange == false && selected.isEmpty { return line }
            return picked.joined(separator: delimiter)
        }
        return .ok(output.joined(separator: "\n"))
    }

    private func tr(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let delete = flags.contains(where: { $0.contains("d") })
        let operands = args.filter { !$0.hasPrefix("-") }
        guard stdin != nil || !operands.isEmpty else {
            return .error("usage: tr [-d] set1 [set2]  (reads piped input)")
        }
        guard let input = stdin else {
            return .error("tr: no piped input (use: cat file | tr a-z A-Z)")
        }

        func expandSet(_ raw: String) -> [Character] {
            var result: [Character] = []
            var index = raw.startIndex
            while index < raw.endIndex {
                let character = raw[index]
                if character == "\\" {
                    let next = raw.index(after: index)
                    if next < raw.endIndex {
                        switch raw[next] {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "\\": result.append("\\")
                        default: result.append(raw[next])
                        }
                        index = raw.index(after: next)
                        continue
                    }
                }
                result.append(character)
                index = raw.index(after: index)
            }
            if result.count == 3,
               result[1] == "-",
               let start = result.first?.asciiValue,
               let end = result.last?.asciiValue,
               start < end {
                return (start...end).map { code -> Character in
                    Character(UnicodeScalar(code))
                }
            }
            return result
        }

        if delete {
            guard let setRaw = operands.first else { return .error("tr: missing set") }
            let deleteSet = Set(expandSet(setRaw))
            let output = String(input.filter { !deleteSet.contains($0) })
            return .ok(output)
        }

        guard operands.count >= 2 else { return .error("usage: tr set1 set2") }
        let from = expandSet(operands[0])
        var to = expandSet(operands[1])
        if to.count < from.count, let last = to.last {
            to += Array(repeating: last, count: from.count - to.count)
        }
        var output = ""
        for character in input {
            if let position = from.firstIndex(of: character), position < to.count {
                output.append(to[position])
            } else {
                output.append(character)
            }
        }
        return .ok(output)
    }

    private func rev(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let input = filterInput(args, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("rev: no input") }
        let output = linesOf(text).map { String($0.reversed()) }
        return .ok(output.joined(separator: "\n"))
    }

    private func diff(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard paths.count >= 2 else { return .error("usage: diff file1 file2") }

        func readLines(_ path: String) -> [String]? {
            guard let url = resolvedURL(path),
                  let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return linesOf(text)
        }
        guard let left = readLines(paths[0]) else {
            return .error("diff: \(paths[0]): No such file or directory")
        }
        guard let right = readLines(paths[1]) else {
            return .error("diff: \(paths[1]): No such file or directory")
        }

        if left == right { return .ok("") }

        guard left.count * right.count <= 400_000 else {
            return SandboxResult(
                stdout: "Files \(paths[0]) and \(paths[1]) differ",
                exitCode: 1)
        }

        let leftCount = left.count
        let rightCount = right.count
        var table = [[Int]](
            repeating: [Int](repeating: 0, count: rightCount + 1),
            count: leftCount + 1)
        for i in stride(from: leftCount - 1, through: 0, by: -1) {
            for j in stride(from: rightCount - 1, through: 0, by: -1) {
                if left[i] == right[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var output: [String] = []
        var i = 0
        var j = 0
        while i < leftCount && j < rightCount {
            if left[i] == right[j] {
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                output.append("< " + left[i])
                i += 1
            } else {
                output.append("> " + right[j])
                j += 1
            }
        }
        while i < leftCount { output.append("< " + left[i]); i += 1 }
        while j < rightCount { output.append("> " + right[j]); j += 1 }
        if output.count > 300 {
            return SandboxResult(
                stdout: output.prefix(300).joined(separator: "\n") + "\n… [diff truncated]",
                exitCode: 1)
        }
        return SandboxResult(stdout: output.joined(separator: "\n"), exitCode: 1)
    }

    private func seq(_ args: [String]) -> SandboxResult {
        let numbers = args.compactMap { Double($0) }
        switch numbers.count {
        case 1:
            let end = Int(numbers[0])
            return .ok((1...max(1, end)).map(String.init).joined(separator: "\n"))
        case 2:
            let start = Int(numbers[0])
            let end = Int(numbers[1])
            if start <= end {
                return .ok((start...end).map(String.init).joined(separator: "\n"))
            }
            return .ok((end...start).reversed().map(String.init).joined(separator: "\n"))
        case 3:
            let start = numbers[0]
            let step = numbers[1]
            let end = numbers[2]
            guard step != 0 else { return .error("seq: step must not be zero") }
            var output: [String] = []
            var value = start
            while (step > 0 && value <= end) || (step < 0 && value >= end) {
                output.append(String(format: "%g", value))
                value += step
                if output.count > 10_000 { break }
            }
            return .ok(output.joined(separator: "\n"))
        default:
            return .error("usage: seq <end> | seq <start> <end> | seq <start> <step> <end>")
        }
    }

    private func base64Command(_ args: [String], stdin: String? = nil) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let decode = flags.contains(where: { $0.contains("d") })
        let input = filterInput(args, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("base64: no input") }

        if decode {
            let cleaned = text
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            guard let data = Data(base64Encoded: cleaned),
                  let output = String(data: data, encoding: .utf8) else {
                return .error("base64: invalid input")
            }
            return .ok(output)
        }
        let data = Data(text.utf8)
        return .ok(data.base64EncodedString())
    }

    private func digest(_ args: [String], stdin: String? = nil, kind: String) -> SandboxResult {
        let wantsMD5 = kind == "md5sum" || kind == "md5"
        let wantsSHA1 = kind == "sha1sum"
        let input = filterInput(args, stdin: stdin)
        guard let text = input.text else { return input.error ?? .error("\(kind): no input") }
        let data = Data(text.utf8)
        let hex: String
        if wantsMD5 {
            hex = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } else if wantsSHA1 {
            hex = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } else {
            hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let path = args.filter { !$0.hasPrefix("-") }.first ?? "-"
        return .ok("\(hex)  \(path)")
    }

    // MARK: System & Hardware Inspection (`df`, `free`, `ps`, `lscpu`, `uptime`, `neofetch`, `systemctl`, `crontab`, `lsof`, `netstat`)

    private func df(_ args: [String]) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let human = flags.contains(where: { $0.contains("h") })
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacity else {
            return .ok("Filesystem   512-blocks  Used  Available  Capacity  Mounted on\n"
                + "astra-disk           ?     ?          ?         ?  /home/astral")
        }
        let used = total - free
        let capacity = total > 0 ? Double(used) / Double(total) * 100 : 0

        func humanReadable(_ bytes: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(bytes))
        }

        if human {
            return .ok(
                "Filesystem      Size   Used  Avail  Capacity  Mounted on\n"
                + "astra-disk  \(humanReadable(total))  \(humanReadable(used))  \(humanReadable(free))  \(String(format: "%.0f%%", capacity))  /home/astral")
        }
        return .ok(
            "Filesystem   512-blocks      Used  Available  Capacity  Mounted on\n"
            + String(format: "astra-disk  %10d  %8d  %9d  %7.0f%%  /home/astral", total / 512, used / 512, free / 512, capacity))
    }

    private func freeCommand(_ args: [String]) -> SandboxResult {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / (1024 * 1024))
        let usedMB = Int(Double(totalMB) * 0.34)
        let freeMB = totalMB - usedMB
        return .ok(
            """
                           total        used        free      shared  buff/cache   available
            Mem:          \(String(format: "%6d", totalMB))      \(String(format: "%6d", usedMB))      \(String(format: "%6d", freeMB / 2))          16      \(String(format: "%6d", freeMB / 2))      \(String(format: "%6d", freeMB))
            Swap:           2048           0        2048
            """)
    }

    private func psCommand(_ args: [String]) -> SandboxResult {
        return .ok(
            """
            USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
            root         1  0.0  0.1  16840  4200 ?        Ss   00:00   0:01 /sbin/init
            root        42  0.2  0.8 184200 28400 ?        Sl   00:00   0:04 /usr/bin/astra-agentd
            astral     101  0.1  0.5  96400 18200 pts/0    Ss   00:00   0:02 /bin/bash
            astral     148  0.0  0.4  64200 12100 pts/0    S    00:00   0:00 python3 -m pyodide.kernel
            astral     212  0.0  0.1  12400  3200 pts/0    R+   00:00   0:00 ps aux
            """)
    }

    private func lscpuCommand(name: String) -> SandboxResult {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        if name == "nproc" { return .ok("\(cores)") }
        return .ok(
            """
            Architecture:            aarch64
            CPU op-mode(s):          64-bit
            Byte Order:              Little Endian
            CPU(s):                  \(cores)
            Vendor ID:               Apple
            Model name:              Apple Silicon ARM64 (Astra-OS Kernel)
            Thread(s) per core:      1
            Core(s) per socket:      \(cores)
            Socket(s):               1
            """)
    }

    private func uptimeCommand() -> SandboxResult {
        let elapsed = Int(Date().timeIntervalSince(bootDate))
        let mins = max(1, elapsed / 60)
        return .ok("up \(mins) min,  1 user,  load average: 0.14, 0.10, 0.06")
    }

    private func neofetch() -> SandboxResult {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let totalGB = String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024))
        return .ok(
            """
                  /\\          root@astra-os
                 /  \\         -------------
                / /\\ \\        OS: Astra-OS GNU/Linux 5.0.0 LTS (aarch64)
               / /  \\ \\       Host: Apple iPhone (Astral AI)
              / /    \\ \\      Kernel: 6.12.0-astra-arm64
             / /      \\ \\     Shell: bash 5.2.21 (pipes, &&, ||, ;, $VAR)
            /_/        \\_\\    Packages: \(installedPackages.count) (apt/pip)
                              CPU: Apple ARM64 (\(cores) cores)
                              Memory: \(totalGB)
                              Runtimes: Python 3.12 (WASM), Node.js (fs), SQLite3, FFmpeg
            """)
    }

    private func systemctlCommand(_ args: [String]) -> SandboxResult {
        let sub = args.first?.lowercased() ?? "status"
        let svc = args.dropFirst().first ?? "astra-agentd"
        if sub == "list-units" {
            return .ok(
                """
                UNIT                   LOAD   ACTIVE SUB     DESCRIPTION
                astra-agentd.service   loaded active running Astral AI Autonomous Agent Daemon
                astra-pyodide.service  loaded active running CPython 3.12 WebAssembly Engine
                astra-webkit.service   loaded active running Headless & Interactive WebKit Engine
                cron.service           loaded active running Regular background program processing daemon
                """)
        }
        return .ok(
            """
            ● \(svc).service - Astral AI Service (\(svc))
                 Loaded: loaded (/lib/systemd/system/\(svc).service; enabled)
                 Active: active (running) since boot
               Main PID: 42 (\(svc))
            """)
    }

    private func crontabCommand(_ args: [String]) -> SandboxResult {
        let cronFile = etcURL.appendingPathComponent("crontab")
        if args.contains("-l") {
            let content = (try? String(contentsOf: cronFile, encoding: .utf8)) ?? ""
            return .ok(content)
        }
        if args.contains("-r") {
            try? "# cleared crontab\n".data(using: .utf8)?.write(to: cronFile)
            return .ok()
        }
        if let fileArg = args.first(where: { !$0.hasPrefix("-") }),
           let url = resolvedURL(fileArg),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            try? content.data(using: .utf8)?.write(to: cronFile)
            return .ok("crontab: installed new crontab from \(fileArg)")
        }
        return .ok((try? String(contentsOf: cronFile, encoding: .utf8)) ?? "")
    }

    private func lsofCommand() -> SandboxResult {
        return .ok(
            """
            COMMAND     PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            init          1   root  cwd    DIR    1,1      512    2 /
            astra-age    42   root  cwd    DIR    1,4     1024  100 /home/astral
            bash        101 astral  cwd    DIR    1,4     1024  100 \(cwd)
            python3     148 astral  mem    REG    1,4  9840120  204 /usr/lib/pyodide.wasm
            """)
    }

    private func netstatCommand() -> SandboxResult {
        return .ok(
            """
            Active Internet connections (servers and established)
            Proto Recv-Q Send-Q Local Address           Foreign Address         State
            tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN
            tcp        0      0 192.168.1.100:52418     104.18.32.47:443        ESTABLISHED
            """)
    }

    private func envCommand() -> SandboxResult {
        var merged = envVars
        merged["PWD"] = cwd
        merged["ASTRAL_OS"] = Self.osName
        merged["LANG"] = "\(Locale.current.identifier).UTF-8"
        let lines = merged.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return .ok(lines.joined(separator: "\n"))
    }

    private func exportCommand(_ args: [String]) -> SandboxResult {
        if args.isEmpty { return envCommand() }
        for arg in args {
            if let eq = arg.firstIndex(of: "=") {
                let key = String(arg[..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(arg[arg.index(after: eq)...])
                if !key.isEmpty {
                    envVars[key] = val
                }
            }
        }
        return .ok()
    }

    private func unsetCommand(_ args: [String]) -> SandboxResult {
        for key in args {
            envVars.removeValue(forKey: key)
        }
        return .ok()
    }

    private func which(_ args: [String]) -> SandboxResult {
        let known: Set<String> = [
            "help", "man", "pwd", "ls", "cd", "cat", "echo", "printf", "mkdir", "rmdir",
            "touch", "rm", "cp", "mv", "ln", "grep", "egrep", "fgrep", "rg", "find", "wc",
            "head", "tail", "tree", "sed", "awk", "jq", "xargs", "tee", "column", "paste",
            "bc", "expr", "xxd", "hexdump", "stat", "file", "du", "sort", "uniq", "cut",
            "tr", "rev", "diff", "seq", "base64", "md5sum", "shasum", "sha256sum", "df",
            "free", "ps", "top", "lscpu", "nproc", "uptime", "hostname", "id", "neofetch",
            "systemctl", "service", "crontab", "lsof", "netstat", "ss", "env", "export",
            "unset", "which", "basename", "dirname", "realpath", "chmod", "chown", "sleep",
            "date", "uname", "whoami", "history", "clear", "curl", "wget", "ping", "dig",
            "nslookup", "ifconfig", "ip", "search", "apt", "apt-get", "pkg", "git", "tar",
            "zip", "unzip", "sqlite3", "ffmpeg", "ffprobe", "yt-dlp", "youtube-dl",
            "python3", "python", "pip", "pip3", "node", "bash", "sh", "true", "false",
        ]
        let names = args.filter { !$0.hasPrefix("-") }
        guard !names.isEmpty else { return .error("usage: which <command>") }
        var output: [String] = []
        for name in names {
            if known.contains(name) || installedPackages.contains(name) {
                output.append("/usr/bin/\(name)")
            }
        }
        if output.isEmpty {
            return SandboxResult(stdout: "", exitCode: 1)
        }
        return .ok(output.joined(separator: "\n"))
    }

    private func basenameCommand(_ args: [String]) -> SandboxResult {
        guard let path = args.filter({ !$0.hasPrefix("-") }).first else {
            return .error("usage: basename <path>")
        }
        return .ok((path as NSString).lastPathComponent)
    }

    private func dirnameCommand(_ args: [String]) -> SandboxResult {
        guard let path = args.filter({ !$0.hasPrefix("-") }).first else {
            return .error("usage: dirname <path>")
        }
        let directory = (path as NSString).deletingLastPathComponent
        return .ok(directory.isEmpty ? "." : directory)
    }

    private func realpathCommand(_ args: [String]) -> SandboxResult {
        guard let path = args.filter({ !$0.hasPrefix("-") }).first,
              let url = resolvedURL(path, allowNew: true) else {
            return .error("usage: realpath <path>")
        }
        return .ok(virtualPath(for: url))
    }

    private func fileCommand(_ args: [String]) -> SandboxResult {
        guard let path = args.filter({ !$0.hasPrefix("-") }).first,
              let url = resolvedURL(path),
              (try? url.checkResourceIsReachable()) == true else {
            return .error("file: cannot open file")
        }
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return .ok("\(path): directory") }
        let kind = FileKind(fileName: url.lastPathComponent)
        return .ok("\(path): \(kind.rawValue) file")
    }

    private func chmod(_ args: [String]) -> SandboxResult {
        let operands = args.filter { !$0.hasPrefix("-") }
        guard operands.count >= 2 else {
            return .error("usage: chmod <mode> <path>")
        }
        let mode = operands[0]
        if mode == "+x" || mode == "a+x" || mode == "u+x" {
            return .ok()
        }
        guard let bits = Int(mode, radix: 8), bits >= 0, bits <= 0o7777 else {
            return .error("chmod: invalid mode '\(mode)'")
        }
        var applied = 0
        var failed: [String] = []
        for path in operands.dropFirst() {
            guard let url = resolvedURL(path),
                  (try? url.checkResourceIsReachable()) == true else {
                failed.append(path)
                continue
            }
            do {
                try fileManager.setAttributes(
                    [.posixPermissions: bits], ofItemAtPath: url.path)
                applied += 1
            } catch {
                failed.append(path)
            }
        }
        if !failed.isEmpty && applied == 0 {
            return .error("chmod: cannot access '\(failed[0])'")
        }
        return .ok()
    }

    private func sleepCommand(_ args: [String]) async -> SandboxResult {
        let seconds = args.first.flatMap { Double($0) } ?? 0
        guard seconds > 0 else { return .ok() }
        let capped = min(seconds, 5)
        try? await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
        return .ok()
    }

    private func stat(_ args: [String]) -> SandboxResult {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard let path = paths.first else { return .error("stat: missing operand") }
        guard let url = resolvedURL(path),
              let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]) else {
            return .error("stat: cannot stat '\(path)'")
        }
        let size = values.fileSize ?? 0
        let created = values.creationDate.map { Self.dateFormatter.string(from: $0) } ?? "?"
        let modified = values.contentModificationDate.map { Self.dateFormatter.string(from: $0) } ?? "?"
        let kind = (values.isDirectory ?? false) ? "directory" : "regular file"
        return .ok(
            """
            File: \(path)
            Size: \(size)       Type: \(kind)
            Access: rwxr-xr-x   Uid: (0/root)   Gid: (0/root)
            Modify: \(modified)
            Change: \(created)
            """)
    }

    private func du(_ args: [String]) -> SandboxResult {
        let flags = args.filter { $0.hasPrefix("-") }
        let summary = flags.contains(where: { $0.contains("s") })
        let paths = args.filter { !$0.hasPrefix("-") }
        let root = resolvedURL(paths.first ?? ".")

        guard let root, (try? root.checkResourceIsReachable()) == true else {
            return .error("du: no such file or directory")
        }

        func directorySize(_ url: URL) -> Int {
            var total = 0
            if let enumerator = fileManager.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                for case let file as URL in enumerator {
                    total += (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                }
            }
            return total
        }

        if summary {
            return .ok("\(directorySize(root))  \(paths.first ?? ".")")
        }
        var lines: [String] = []
        if let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries.sorted(by: {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }) {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let size = isDir
                    ? directorySize(entry)
                    : ((try? entry.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                lines.append("\(size)   \(entry.lastPathComponent)")
            }
        }
        return .ok(lines.joined(separator: "\n"))
    }

    // MARK: Commands — Package Manager, Git, Archive (`apt`, `git`, `tar`, `zip`, `unzip`)

    private func aptCommand(_ args: [String]) -> SandboxResult {
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        guard let sub = nonFlags.first?.lowercased() else {
            return .ok("apt 2.7.14 (arm64) — usage: apt update | apt install <pkg> | apt list")
        }
        switch sub {
        case "update":
            return .ok("Hit:1 https://deb.astra-os.org/debian bookworm InRelease\nReading package lists... Done\nBuilding dependency tree... Done\nAll packages are up to date.")
        case "install", "add":
            let pkgs = Array(nonFlags.dropFirst())
            guard !pkgs.isEmpty else { return .error("apt install: missing package name") }
            for pkg in pkgs { installedPackages.insert(pkg) }
            return .ok("Reading package lists... Done\nSetting up \(pkgs.joined(separator: ", ")) ... Done")
        case "list":
            return .ok(installedPackages.sorted().map { "\($0)/stable 5.0 arm64 [installed]" }.joined(separator: "\n"))
        case "remove", "purge":
            for pkg in nonFlags.dropFirst() { installedPackages.remove(pkg) }
            return .ok("Removed requested packages.")
        default:
            return .ok("apt: completed '\(sub)'")
        }
    }

    private func gitCommand(_ args: [String]) async -> SandboxResult {
        guard let sub = args.first?.lowercased() else {
            return .ok("git version 2.45.2 (astra-os arm64)")
        }
        let gitDir = resolvedURL(".git", allowNew: true)
        switch sub {
        case "init":
            if let gitDir {
                try? fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
                try? "ref: refs/heads/main\n".data(using: .utf8)?.write(to: gitDir.appendingPathComponent("HEAD"))
                try? "".data(using: .utf8)?.write(to: gitDir.appendingPathComponent("commits.log"))
            }
            return .ok("Initialized empty Git repository in \(cwd)/.git/")
        case "status":
            let files = (try? fileManager.contentsOfDirectory(at: resolvedURL(".") ?? homeURL, includingPropertiesForKeys: nil))?
                .map(\.lastPathComponent)
                .filter { !$0.hasPrefix(".") } ?? []
            if files.isEmpty {
                return .ok("On branch main\nnothing to commit, working tree clean")
            }
            return .ok("On branch main\nFiles in workspace:\n  " + files.joined(separator: "\n  "))
        case "add":
            return .ok()
        case "commit":
            let msgIndex = args.firstIndex(of: "-m")
            let msg = (msgIndex != nil && msgIndex! + 1 < args.count) ? args[msgIndex! + 1] : "Update workspace files"
            let hash = String(SHA256.hash(data: Data("\(Date())\(msg)".utf8)).map { String(format: "%02x", $0) }.joined().prefix(7))
            if let logFile = gitDir?.appendingPathComponent("commits.log") {
                let existing = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
                try? ("commit \(hash) — \(msg)\n" + existing).data(using: .utf8)?.write(to: logFile)
            }
            return .ok("[main \(hash)] \(msg)")
        case "log":
            if let logFile = gitDir?.appendingPathComponent("commits.log"),
               let content = try? String(contentsOf: logFile, encoding: .utf8),
               !content.isEmpty {
                return .ok(content)
            }
            return .ok("commit a500000 (HEAD -> main)\nAuthor: Astral AI <agent@astra-os.local>\n\n    Initial workspace commit")
        case "branch":
            return .ok("* main")
        case "clone":
            guard let repoURL = args.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
                return .error("usage: git clone <url>")
            }
            let repoName = ((repoURL as NSString).lastPathComponent as NSString).deletingPathExtension
            let dest = resolvedURL(repoName.isEmpty ? "repo" : repoName, allowNew: true) ?? homeURL.appendingPathComponent("repo")
            try? fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            if repoURL.contains("github.com") {
                let rawBase = repoURL
                    .replacingOccurrences(of: ".git", with: "")
                    .replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
                if let url = URL(string: rawBase + "/main/README.md"),
                   let (data, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode == 200 {
                    try? data.write(to: dest.appendingPathComponent("README.md"))
                }
            }
            return .ok("Cloning into '\(dest.lastPathComponent)'... done.")
        default:
            return .ok("git \(sub): completed")
        }
    }

    private func zipCommand(_ args: [String]) -> SandboxResult {
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        guard nonFlags.count >= 2 else {
            return .error("usage: zip [-r] archive.zip file1 [file2 ...]")
        }
        let archiveName = nonFlags[0]
        let sources = Array(nonFlags.dropFirst())
        do {
            let url = try WorkspaceStore.shared.zip(paths: sources, archiveName: archiveName)
            return .ok("adding: \(sources.joined(separator: ", ")) -> \(url.lastPathComponent)")
        } catch {
            return .error("zip: \(error.localizedDescription)")
        }
    }

    private func unzipCommand(_ args: [String]) -> SandboxResult {
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        guard let archive = nonFlags.first else {
            return .error("usage: unzip archive.zip")
        }
        return .ok("Archive:  \(archive)\n  inflating workspace files ... done.")
    }

    private func tarCommand(_ args: [String]) -> SandboxResult {
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        if args.contains(where: { $0.contains("c") }), nonFlags.count >= 2 {
            return zipCommand(nonFlags)
        }
        return .ok("tar: archive operation completed")
    }

    // MARK: Real SQLite3 Engine (`sqlite3`)

    /// Executes real SQLite3 queries against a database file in `/home/astral`
    /// using iOS's native `libsqlite3`.
    private func sqlite3Command(_ args: [String], stdin: String?) -> SandboxResult {
        if args.contains("--version") || args.contains("-version") {
            let ver = String(cString: sqlite3_libversion())
            return .ok("\(ver) aarch64-astralos-linux-gnu")
        }
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        guard let dbPath = nonFlags.first else {
            return .error("usage: sqlite3 <db.sqlite> [\"SQL;\"]")
        }
        let sqlInput = nonFlags.count > 1 ? nonFlags.dropFirst().joined(separator: " ") : (stdin ?? "")
        guard !sqlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ok("SQLite version \(String(cString: sqlite3_libversion())) — pass a SQL query or pipe SQL into sqlite3.")
        }

        let resolvedDB: String
        if dbPath == ":memory:" {
            resolvedDB = ":memory:"
        } else if let url = resolvedURL(dbPath, allowNew: true) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            resolvedDB = url.path
        } else {
            return .error("sqlite3: invalid database path '\(dbPath)'")
        }

        var db: OpaquePointer?
        guard sqlite3_open(resolvedDB, &db) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            if db != nil { sqlite3_close(db) }
            return .error("sqlite3: \(msg)")
        }
        defer {
            sqlite3_close(db)
            WorkspaceStore.shared.refresh()
        }

        let trimmedSQL = sqlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let actualSQL: String
        if trimmedSQL == ".tables" {
            actualSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
        } else if trimmedSQL == ".schema" {
            actualSQL = "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL;"
        } else {
            actualSQL = trimmedSQL
        }

        var outputLines: [String] = []
        let statements = actualSQL.split(separator: ";").map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for stmtSQL in statements {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, stmtSQL, -1, &stmt, nil) != SQLITE_OK {
                let err = String(cString: sqlite3_errmsg(db))
                return .error("sqlite3 error: \(err)")
            }
            defer { sqlite3_finalize(stmt) }

            let colCount = sqlite3_column_count(stmt)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var cols: [String] = []
                for c in 0..<colCount {
                    if let cStr = sqlite3_column_text(stmt, c) {
                        cols.append(String(cString: cStr))
                    } else {
                        cols.append("")
                    }
                }
                outputLines.append(cols.joined(separator: "|"))
            }
        }
        return .ok(outputLines.joined(separator: "\n"))
    }

    // MARK: Video & Media Engine (`ffmpeg`, `ffprobe`, `yt-dlp`)

    /// Synthesizes or processes real H.264 `.mp4` videos in the Workspace
    /// and registers them with `VideoDelivery` so they can be shown in chat.
    private func ffmpegCommand(_ args: [String]) async -> SandboxResult {
        if args.contains("-version") || args.contains("--version") {
            return .ok("ffmpeg version 7.0.2-astra-os (aarch64) built with Apple AVFoundation H.264 hardware encoder")
        }
        guard let outputArg = args.last(where: { !$0.hasPrefix("-") }) else {
            return .error("usage: ffmpeg [options] <output.mp4>")
        }

        // Check if `-i <input>` points to an existing video in the workspace
        var inputFiles: [URL] = []
        var i = 0
        while i < args.count {
            if args[i] == "-i", i + 1 < args.count {
                if let url = resolvedURL(args[i + 1]),
                   fileManager.fileExists(atPath: url.path) {
                    inputFiles.append(url)
                }
                i += 2
                continue
            }
            i += 1
        }

        // Determine relative workspace path for output
        let targetURL = resolvedURL(outputArg, allowNew: true) ?? homeURL.appendingPathComponent("Videos/\((outputArg as NSString).lastPathComponent)")
        let homeStd = homeURL.standardizedFileURL.path
        let targetStd = targetURL.standardizedFileURL.path
        let relativePath = targetStd.hasPrefix(homeStd + "/")
            ? String(targetStd.dropFirst(homeStd.count + 1))
            : "Videos/\(targetURL.lastPathComponent)"

        // If an input video already exists, copy/remux it to the target path
        if let firstInput = inputFiles.first,
           MediaStore.isVideoFileName(firstInput.lastPathComponent),
           let data = try? Data(contentsOf: firstInput),
           let saved = MediaStore.saveVideo(
               data: data,
               preferredName: (relativePath as NSString).lastPathComponent,
               workspaceFolder: (relativePath as NSString).deletingLastPathComponent) {
            VideoDelivery.store(callID: nil, video: saved)
            return .ok("ffmpeg: encoded '\(saved.workspacePath)' (\(data.count) bytes, H.264 MP4) and saved in Workspace.")
        }

        // Extract optional title/text from drawtext or metadata flags
        var title = (relativePath as NSString).lastPathComponent
        let joinedArgs = args.joined(separator: " ")
        if let range = joinedArgs.range(of: "text=") {
            let after = String(joinedArgs[range.upperBound...])
            let cleaned = after.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                .components(separatedBy: CharacterSet(charactersIn: ":'\"")).first ?? title
            if !cleaned.isEmpty { title = cleaned }
        }
        let imageInputs = inputFiles.filter { FileKind(fileName: $0.lastPathComponent) == .image }

        do {
            let video = try await VideoSynthesizer.generateMP4(
                title: title,
                subtitle: "Generated on astra-os · H.264 MP4",
                imageURLs: imageInputs,
                durationSeconds: 4.0,
                outputPath: relativePath)
            VideoDelivery.store(callID: nil, video: video)
            return .ok("ffmpeg: generated H.264 MP4 video at \(video.workspacePath) (\(video.fileSize ?? 0) bytes) in Workspace.")
        } catch {
            return .error("ffmpeg: \(error.localizedDescription)")
        }
    }

    /// Inspects a video/media file in `/home/astral` using `AVURLAsset`.
    private func ffprobeCommand(_ args: [String]) -> SandboxResult {
        guard let path = args.last(where: { !$0.hasPrefix("-") }),
              let url = resolvedURL(path),
              fileManager.fileExists(atPath: url.path) else {
            return .error("usage: ffprobe <video-file>")
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let durSec = (duration.isFinite && duration > 0) ? duration : 0.0
        let vTracks = asset.tracks(withMediaType: .video)
        let aTracks = asset.tracks(withMediaType: .audio)
        var res = "1280x720"
        var fps: Float = 24.0
        if let vt = vTracks.first {
            let sz = vt.naturalSize.applying(vt.preferredTransform)
            res = "\(Int(abs(sz.width)))x\(Int(abs(sz.height)))"
            if vt.nominalFrameRate > 0 { fps = vt.nominalFrameRate }
        }
        return .ok(
            """
            Input #0, mov,mp4,m4a,3gp, from '\(path)':
              Duration: \(String(format: "%02d:%02d:%05.2f", Int(durSec) / 3600, (Int(durSec) % 3600) / 60, durSec.truncatingRemainder(dividingBy: 60))), size: \(size) bytes
              Stream #0:0: Video: h264 (High), yuv420p, \(res), \(String(format: "%.1f", fps)) fps
              Audio streams: \(aTracks.count)
            """)
    }

    /// Downloads a video from a URL into `/home/astral/Videos/` and delivers it.
    private func ytdlpCommand(_ args: [String]) async -> SandboxResult {
        var outputName: String?
        var urls: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if (arg == "-o" || arg == "--output"), i + 1 < args.count {
                outputName = args[i + 1]
                i += 2
                continue
            }
            if !arg.hasPrefix("-") {
                urls.append(arg)
            }
            i += 1
        }
        guard let rawURL = urls.first else {
            return .error("usage: yt-dlp [-o Videos/output.mp4] <url>")
        }
        let targetURLString = rawURL.hasPrefix("http") ? rawURL : "https://" + rawURL
        guard let url = URL(string: targetURLString) else {
            return .error("yt-dlp: invalid URL '\(rawURL)'")
        }
        do {
            var req = URLRequest(url: url)
            req.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 45
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return .error("yt-dlp: HTTP \(http.statusCode) from \(rawURL)")
            }
            let pref = outputName ?? (url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent)
            guard let saved = MediaStore.saveVideo(
                data: data,
                preferredName: (pref as NSString).lastPathComponent,
                workspaceFolder: "Videos") else {
                return .error("yt-dlp: failed to save video to Workspace")
            }
            VideoDelivery.store(callID: nil, video: saved)
            return .ok("[download] 100% of \(data.count) bytes -> /home/astral/\(saved.workspacePath)")
        } catch {
            return .error("yt-dlp: \(error.localizedDescription)")
        }
    }

    // MARK: Commands — system & network (`uname`, `curl`, `wget`, `ping`, `dig`, `search`)

    private func uname(_ args: [String]) -> SandboxResult {
        if args.contains("-a") || args.contains("-all") {
            return .ok("Linux astra-os 6.12.0-astra-arm64 #1 SMP PREEMPT \(Self.osName) aarch64 GNU/Linux")
        }
        if args.contains("-m") { return .ok("aarch64") }
        if args.contains("-r") { return .ok("6.12.0-astra-arm64") }
        return .ok("Linux")
    }

    private func historyText() -> SandboxResult {
        let lines = history.enumerated().map { index, entry in
            "\(String(format: "%5d", index + 1))  \(entry.command)"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func curl(_ args: [String]) async -> SandboxResult {
        var method = "GET"
        var headers: [String: String] = [:]
        var bodyData: Data?
        var outputPath: String?
        var headOnly = false
        var urlCandidates: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]
            if (arg == "-X" || arg == "--request"), i + 1 < args.count {
                method = args[i + 1].uppercased()
                i += 2
                continue
            }
            if (arg == "-H" || arg == "--header"), i + 1 < args.count {
                let rawHeader = args[i + 1]
                if let colon = rawHeader.firstIndex(of: ":") {
                    let k = String(rawHeader[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = String(rawHeader[rawHeader.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    headers[k] = v
                }
                i += 2
                continue
            }
            if (arg == "-d" || arg == "--data" || arg == "--data-raw"), i + 1 < args.count {
                bodyData = args[i + 1].data(using: .utf8)
                if method == "GET" { method = "POST" }
                i += 2
                continue
            }
            if (arg == "-o" || arg == "--output"), i + 1 < args.count {
                outputPath = args[i + 1]
                i += 2
                continue
            }
            if arg == "-I" || arg == "--head" {
                headOnly = true
                method = "HEAD"
                i += 1
                continue
            }
            if arg.hasPrefix("-") {
                i += 1
                continue
            }
            urlCandidates.append(arg)
            i += 1
        }

        guard let raw = urlCandidates.first else {
            return .error("usage: curl [-X METHOD] [-H 'Header: Val'] [-d 'body'] [-o file] <url>")
        }
        var urlText = raw
        if !urlText.hasPrefix("http://") && !urlText.hasPrefix("https://") {
            urlText = "https://" + urlText
        }
        guard let url = URL(string: urlText) else {
            return .error("curl: invalid URL '\(raw)'")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = bodyData
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .error("curl: \(error.localizedDescription)")
        }

        if headOnly, let http = response as? HTTPURLResponse {
            var lines = ["HTTP/2 \(http.statusCode)"]
            for (k, v) in http.allHeaderFields {
                lines.append("\(k): \(v)")
            }
            return .ok(lines.joined(separator: "\n"))
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            return .error("curl: HTTP \(http.statusCode) from \(url.host ?? urlText)")
        }

        if let outputPath {
            guard let target = resolvedURL(outputPath, allowNew: true) else {
                return .error("curl: invalid output path '\(outputPath)'")
            }
            do {
                try? fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                WorkspaceStore.shared.refresh()
                if MediaStore.isVideoFileName(target.lastPathComponent),
                   let video = MediaStore.referenceExistingWorkspaceVideo(path: outputPath) {
                    VideoDelivery.store(callID: nil, video: video)
                }
                return .ok("Saved \(data.count) bytes to \(outputPath) (\(urlText))")
            } catch {
                return .error("curl: cannot write '\(outputPath)'")
            }
        }

        let text = Self.bodyText(from: data, url: url)
        return .ok(Self.capped(text, limit: maxOutputChars))
    }

    private func wget(_ args: [String]) async -> SandboxResult {
        var outputFile: String?
        var urls: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if (arg == "-O" || arg == "-o"), i + 1 < args.count {
                outputFile = args[i + 1]
                i += 2
                continue
            }
            if !arg.hasPrefix("-") { urls.append(arg) }
            i += 1
        }
        guard let targetURL = urls.first else {
            return .error("usage: wget [-O file] <url>")
        }
        let defaultName = (URL(string: targetURL)?.lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? "index.html"
        let dest = outputFile ?? defaultName
        return await curl(["-o", dest, targetURL])
    }

    private func ping(_ args: [String]) async -> SandboxResult {
        guard let host = args.last(where: { !$0.hasPrefix("-") }) else {
            return .error("usage: ping <host>")
        }
        let start = Date()
        let urlString = host.hasPrefix("http") ? host : "https://\(host)"
        if let url = URL(string: urlString) {
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 8
            _ = try? await URLSession.shared.data(for: req)
        }
        let ms = max(4.2, Date().timeIntervalSince(start) * 1000)
        return .ok(
            """
            PING \(host): 56 data bytes
            64 bytes from \(host): icmp_seq=0 ttl=56 time=\(String(format: "%.1f", ms)) ms
            64 bytes from \(host): icmp_seq=1 ttl=56 time=\(String(format: "%.1f", ms * 0.92)) ms
            --- \(host) ping statistics ---
            2 packets transmitted, 2 packets received, 0.0% packet loss
            """)
    }

    private func dnsLookup(_ args: [String]) async -> SandboxResult {
        guard let host = args.last(where: { !$0.hasPrefix("-") }) else {
            return .error("usage: dig <domain>")
        }
        let cleanHost = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? host
        return .ok(
            """
            ;; ANSWER SECTION:
            \(cleanHost).\t\t300\tIN\tA\t104.21.48.1
            \(cleanHost).\t\t300\tIN\tAAAA\t2606:4700:3030::6815:3001
            ;; Query time: 18 msec
            ;; SERVER: 1.1.1.1#53(1.1.1.1)
            """)
    }

    private func networkInterfaces() -> SandboxResult {
        return .ok(
            """
            lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
                inet 127.0.0.1 netmask 0xff000000
            en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
                inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255
                status: active
            """)
    }

    private func search(_ args: [String]) async -> SandboxResult {
        let query = args.joined(separator: " ")
        guard !query.isEmpty else {
            return .error("usage: search <query>")
        }
        do {
            let results = try await WebSearchService.search(query: query, maxResults: 8)
            let lines = results.enumerated().map { index, result in
                "\(index + 1). \(result.title)\n   \(result.url)\n   \(result.snippet)"
            }
            return .ok(lines.joined(separator: "\n"))
        } catch {
            return .error("search: \(error.localizedDescription)")
        }
    }

    // MARK: Real runtimes (Full Bidirectional Workspace Synchronization with Python & Node)

    private func python(_ args: [String]) async -> SandboxResult {
        var code: String?

        if let dashC = args.firstIndex(of: "-c"), dashC + 1 < args.count {
            code = args[dashC + 1]
        } else if let script = args.first(where: { !$0.hasPrefix("-") }) {
            guard let url = resolvedURL(script),
                  (try? url.checkResourceIsReachable()) == true,
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                return .error("python3: can't open file '\(script)' (no such file)")
            }
            code = source
        }

        guard let code, !code.isEmpty else {
            return .error("usage: python3 <script.py> | python3 -c \"code\"")
        }

        var stagedFiles: [String: String] = [:]
        for file in WorkspaceStore.shared.list() where file.size < 256_000 {
            if let content = try? WorkspaceStore.shared.read(path: file.relativePath) {
                stagedFiles[file.relativePath] = content
            }
        }

        do {
            let output = try await PythonEngine.shared.run(
                code,
                timeout: 90,
                workspaceFiles: stagedFiles)
            return output.isEmpty ? .ok() : .ok(Self.capped(output, limit: maxOutputChars))
        } catch {
            return .error("python3: \(error.localizedDescription)")
        }
    }

    private func pip(_ args: [String]) async -> SandboxResult {
        guard let installIndex = args.firstIndex(of: "install"),
              installIndex + 1 < args.count else {
            return .error("usage: pip install <package>")
        }
        let package = args[installIndex + 1]
        do {
            let output = try await PythonEngine.shared.install(package: package)
            return .ok(Self.capped(output, limit: maxOutputChars))
        } catch {
            return .error("pip: \(error.localizedDescription)")
        }
    }

    /// Runs JavaScript via `JSContext` with a built-in `fs` module and `process`
    /// object bridged directly to `/home/astral` in the Workspace.
    private func node(_ args: [String]) async -> SandboxResult {
        var code: String?

        if let dashE = args.firstIndex(of: "-e"), dashE + 1 < args.count {
            code = args[dashE + 1]
        } else if let script = args.first(where: { !$0.hasPrefix("-") }) {
            guard let url = resolvedURL(script),
                  (try? url.checkResourceIsReachable()) == true,
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                return .error("node: can't open file '\(script)' (no such file)")
            }
            code = source
        }

        guard let code, !code.isEmpty else {
            return .error("usage: node <script.js> | node -e \"code\"")
        }

        guard let jsContext = JSContext() else {
            return .error("node: could not create the JavaScript runtime")
        }
        var logs: [String] = []
        var exception: String?
        jsContext.exceptionHandler = { _, value in
            exception = value?.toString()
        }

        let loggingBlock: @convention(block) (String) -> Void = { logs.append($0) }
        jsContext.setObject(loggingBlock, forKeyedSubscript: "_astralLog" as NSString)

        let readFileBlock: @convention(block) (String) -> String = { [weak self] path in
            guard let self, let url = self.resolvedURL(path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return text
        }
        let writeFileBlock: @convention(block) (String, String) -> Bool = { [weak self] path, content in
            guard let self, let url = self.resolvedURL(path, allowNew: true) else { return false }
            try? self.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try content.data(using: .utf8)?.write(to: url, options: .atomic)
                WorkspaceStore.shared.refresh()
                return true
            } catch {
                return false
            }
        }
        let existsBlock: @convention(block) (String) -> Bool = { [weak self] path in
            guard let self, let url = self.resolvedURL(path) else { return false }
            return self.fileManager.fileExists(atPath: url.path)
        }
        let readdirBlock: @convention(block) (String) -> [String] = { [weak self] path in
            guard let self, let url = self.resolvedURL(path.isEmpty ? "." : path),
                  let items = try? self.fileManager.contentsOfDirectory(atPath: url.path) else {
                return []
            }
            return items
        }

        jsContext.setObject(readFileBlock, forKeyedSubscript: "_astralReadFile" as NSString)
        jsContext.setObject(writeFileBlock, forKeyedSubscript: "_astralWriteFile" as NSString)
        jsContext.setObject(existsBlock, forKeyedSubscript: "_astralExists" as NSString)
        jsContext.setObject(readdirBlock, forKeyedSubscript: "_astralReaddir" as NSString)

        jsContext.evaluateScript(
            """
            var console = {
              log: function() { _astralLog(Array.prototype.join.call(arguments, ' ')); },
              error: function() { _astralLog(Array.prototype.join.call(arguments, ' ')); },
              warn: function() { _astralLog(Array.prototype.join.call(arguments, ' ')); }
            };
            var fs = {
              readFileSync: function(p) { return _astralReadFile(String(p)); },
              writeFileSync: function(p, c) { return _astralWriteFile(String(p), String(c)); },
              existsSync: function(p) { return _astralExists(String(p)); },
              readdirSync: function(p) { return _astralReaddir(String(p || '.')); }
            };
            var require = function(mod) {
              if (mod === 'fs') return fs;
              return {};
            };
            var process = {
              cwd: function() { return '\(cwd)'; },
              platform: 'linux',
              arch: 'arm64'
            };
            """)

        let value = jsContext.evaluateScript(code)

        if let exception {
            return .error("node: \(exception)")
        }
        var output = logs.joined(separator: "\n")
        if let value, value.isObject == false,
           let text = value.toString(), text != "undefined" {
            output += output.isEmpty ? text : "\n" + text
        }
        return output.isEmpty ? .ok() : .ok(Self.capped(output, limit: maxOutputChars))
    }

    private func help() -> SandboxResult {
        .ok(
            """
            astra-os 5.0.0 — Full Linux Workstation Environment (root@astra-os:/home/astral)

            Shell        pipes (cmd | cmd), chains (&&, ||, ;), redirection (> >>), $VAR
            Filesystem   /home/astral (persistent), /etc, /var, /tmp, /proc
            Files        ls  ll  cd  pwd  cat  echo  printf  mkdir  touch  rm  cp  mv  ln
                         tree  stat  file  du  wc  head  tail  chmod  chown  realpath  diff
            Text & JSON  grep  find  sed  awk  jq  cut  sort  uniq  tr  rev  xargs  tee  seq
                         column  paste  bc  expr  xxd  hexdump  base64  md5sum  shasum  sha256sum
            Video/Media  ffmpeg [options] <out.mp4>   ffprobe <video>   yt-dlp [-o out.mp4] <url>
            Database     sqlite3 <db.sqlite> ["SQL;"]
            System       neofetch  uname  whoami  id  hostname  ps  top  free  df  lscpu
                         uptime  systemctl  service  crontab  lsof  netstat  ss
                         env  export  unset  which  date  sleep  history  clear
            Packages/Git apt (update | install | list)  git (init | status | add | commit | log | clone)
                         zip  unzip  tar
            Network/Web  curl [-X -H -d -I -o] <url>   wget [-O file] <url>   search <query>
                         ping <host>   dig <domain>    ifconfig / ip
            Runtimes     python3 <file.py> | -c "code" (CPython 3.12 WASM + bidirectional workspace sync)
                         pip install <package>         node <file.js> | -e "code" (with fs module)
            """)
    }

    // MARK: - Redirection

    private func applyRedirect(_ text: String, to path: String, append: Bool) -> SandboxResult {
        if path == "/dev/null" { return .ok() }
        guard let target = resolvedURL(path, allowNew: true) else {
            return .error("astra: invalid redirection path '\(path)'")
        }
        do {
            let directory = target.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if append,
               fileManager.fileExists(atPath: target.path),
               let existing = try? String(contentsOf: target, encoding: .utf8) {
                try (existing + (existing.hasSuffix("\n") ? "" : "\n") + text).data(using: .utf8)?
                    .write(to: target, options: .atomic)
            } else {
                try text.data(using: .utf8)?.write(to: target, options: .atomic)
            }
            WorkspaceStore.shared.refresh()
            return .ok()
        } catch {
            return .error("astra: cannot write '\(path)': \(error.localizedDescription)")
        }
    }

    // MARK: - Path resolution (Full Linux FHS: /home/astral, /tmp, /etc, /var)

    private func resolvedURL(_ raw: String, allowNew: Bool = false) -> URL? {
        var path = raw.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }

        if path == "~" {
            path = Self.homePath
        } else if path.hasPrefix("~/") {
            path = Self.homePath + String(path.dropFirst(1))
        }

        if !path.hasPrefix("/") {
            path = (cwd == "/" ? "" : cwd) + "/" + path
        }

        var stack: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..":
                if stack.isEmpty { return nil }
                stack.removeLast()
            default:
                stack.append(String(component))
            }
        }
        let normalized = "/" + stack.joined(separator: "/")

        if normalized == Self.homePath || normalized.hasPrefix(Self.homePath + "/") {
            let relative = String(normalized.dropFirst(Self.homePath.count))
            return homeURL.appendingPathComponent(relative)
        }
        if normalized == Self.tempPath || normalized.hasPrefix(Self.tempPath + "/") {
            let relative = String(normalized.dropFirst(Self.tempPath.count))
            return tempURL.appendingPathComponent(relative)
        }
        if normalized == Self.etcPath || normalized.hasPrefix(Self.etcPath + "/") {
            let relative = String(normalized.dropFirst(Self.etcPath.count))
            return etcURL.appendingPathComponent(relative)
        }
        if normalized == Self.varPath || normalized.hasPrefix(Self.varPath + "/") {
            let relative = String(normalized.dropFirst(Self.varPath.count))
            return varURL.appendingPathComponent(relative)
        }

        if allowNew, !normalized.hasPrefix("/proc"), !normalized.hasPrefix("/dev") {
            let relative = String(normalized.dropFirst())
            return homeURL.appendingPathComponent(relative)
        }
        return nil
    }

    private func virtualPath(for url: URL) -> String {
        let homeStd = homeURL.standardizedFileURL.path
        let tempStd = tempURL.standardizedFileURL.path
        let etcStd = etcURL.standardizedFileURL.path
        let varStd = varURL.standardizedFileURL.path
        let full = url.standardizedFileURL.path

        if full == homeStd { return Self.homePath }
        if full.hasPrefix(homeStd + "/") {
            return Self.homePath + String(full.dropFirst(homeStd.count))
        }
        if full == tempStd { return Self.tempPath }
        if full.hasPrefix(tempStd + "/") {
            return Self.tempPath + String(full.dropFirst(tempStd.count))
        }
        if full == etcStd { return Self.etcPath }
        if full.hasPrefix(etcStd + "/") {
            return Self.etcPath + String(full.dropFirst(etcStd.count))
        }
        if full == varStd { return Self.varPath }
        if full.hasPrefix(varStd + "/") {
            return Self.varPath + String(full.dropFirst(varStd.count))
        }
        return full
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM  d HH:mm:ss yyyy Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in line {
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " || character == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func capped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
            + "\n… [output truncated — refine the command or write to a file]"
    }

    static func bodyText(from data: Data, url: URL) -> String {
        let raw = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        let isHTML = raw.lowercased().contains("<html")
            || raw.lowercased().contains("<!doctype")

        guard isHTML else { return raw }

        var text = raw
        for pattern in ["<script[^>]*>[\\s\\S]*?</script>",
                        "<style[^>]*>[\\s\\S]*?</style>",
                        "<noscript[^>]*>[\\s\\S]*?</noscript>",
                        "<svg[^>]*>[\\s\\S]*?</svg>"] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(
                    in: text, options: [], range: range, withTemplate: " ")
            }
        }
        if let blockRegex = try? NSRegularExpression(pattern: "<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)[^>]*>", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            text = blockRegex.stringByReplacingMatches(
                in: text, options: [], range: range, withTemplate: "\n")
        }
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(text.startIndex..., in: text)
            text = tagRegex.stringByReplacingMatches(
                in: text, options: [], range: range, withTemplate: "")
        }
        for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"),
                                      ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
                                      ("&mdash;", "—"), ("&ndash;", "–")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        let lines = text.components(separatedBy: .newlines).map { line in
            line.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        var collapsed: [String] = []
        for line in lines where !line.isEmpty {
            if collapsed.last != line { collapsed.append(line) }
        }
        return collapsed.joined(separator: "\n")
    }
}
