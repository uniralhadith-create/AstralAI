import Foundation

// MARK: - ExecTool (V5.0.0 — Full Root Linux Workstation Shell)

/// The astra-os 5.0 terminal — the agent's primary way of working. Runs any
/// sandbox shell command inside the persistent `/home/astral` Linux FHS
/// workspace, or on the cloud Ubuntu microVM when Cloud Mode is enabled.
@MainActor
final class ExecTool: AgentTool {

    let name = "exec"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Run a bash/shell command inside the astra-os 5.0 Linux workstation environment (root@astra-os:/home/astral on the user's device). "
                + "FULL SHELL: pipes (cmd | cmd), logical chaining (cmd && cmd || fallback; cmd), redirection (> >>), and environment variables ($VAR / export) all work like a real Linux computer. "
                + "Available commands (60+): ls, ll, cd, pwd, cat, echo, printf, mkdir (-p), rmdir, touch, rm (-rf), cp, mv, ln, grep (-i -n -r -v -c), find (-name), wc, head, tail, "
                + "tree, sed (-i s/pat/repl/g), awk (-F), jq (JSON query & pretty-print), xargs, tee, stat, file, du, date, uname (-a), whoami, id, hostname, neofetch, env, export, unset, "
                + "df (-h), free (-m), ps (aux), top, lscpu, nproc, uptime, which, sleep, chmod, chown, basename, dirname, realpath, diff, seq, sort (-r -n -u), uniq (-c), cut (-d -f), tr (-d), rev, "
                + "base64 (-d), md5sum, shasum, sha256sum, history, apt (update | install | list), git (init | status | add | commit | log | clone), zip, unzip, tar, "
                + "curl [-X -H -d -I -o] <url> (HTTP client & page reader), wget [-O file] <url> (file downloader), ping <host>, dig <domain>, ifconfig/ip, search <query> (live web search), "
                + "python3 <file.py> | python3 -c \"code\" (REAL CPython 3.12 via Pyodide with automatic workspace file sync), node <file.js> | node -e \"code\" (REAL JavaScript), pip install <package>. "
                + "Use this Linux workstation proactively to create projects, write and test code, process JSON/CSV/text pipelines, scrape web pages, and build deliverables.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The Linux shell command line, e.g. 'mkdir -p Projects/App && echo \"# App\" > Projects/App/README.md' or 'curl -s https://api.github.com/zen | tee quote.txt'"),
                    ]),
                ]),
                "required": .array([.string("command")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let command = arguments["command"]?.stringValue,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: "Error: missing required parameter 'command'.",
                isError: true)
        }

        let outcome = await CloudRouting.exec(command)
        return ToolResult(content: outcome.content, isError: outcome.isError)
    }
}

// MARK: - WebFetchTool

/// Fetches a URL and returns clean readable text (HTML stripped).
@MainActor
final class WebFetchTool: AgentTool {

    let name = "web_fetch"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Fetch a URL and return its content as clean readable text (HTML is converted to plain text, scripts and styles removed). "
                + "Use it after web_search to read the full content of a promising result.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("The http(s) URL to fetch"),
                    ]),
                ]),
                "required": .array([.string("url")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard var urlText = arguments["url"]?.stringValue,
              !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: "Error: missing required parameter 'url'.",
                isError: true)
        }
        urlText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlText.hasPrefix("http://") && !urlText.hasPrefix("https://") {
            urlText = "https://" + urlText
        }
        guard let url = URL(string: urlText) else {
            return ToolResult(content: "Error: invalid URL '\(urlText)'.", isError: true)
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return ToolResult(
                content: "Fetch failed: \(error.localizedDescription)",
                isError: true)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            return ToolResult(
                content: "Fetch failed: HTTP \(http.statusCode) from \(url.host ?? urlText)",
                isError: true)
        }

        let text = SandboxShell.bodyText(from: data, url: url)
        return ToolResult(content: SandboxShell.capped(text, limit: 16_000), isError: false)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted after any sandbox command that may have changed workspace
    /// files, so the Files tab can refresh.
    static let sandboxDidChange = Notification.Name("astral.sandboxDidChange")
}
