import Foundation

// MARK: - Computer tools (V4.0)

/// Runs REAL Python on-device through the Pyodide WebAssembly engine -
/// the AI's own local interpreter. stdout/stderr and the final expression
/// value are returned to the model. Files written with open(..., "w") can
/// be staged from the workspace and saved back into it.
@MainActor
final class RunPythonTool: AgentTool {

    let name = "run_python"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Execute real Python 3 code on the user's device (CPython compiled to WebAssembly). "
                + "print() output, expression results and errors are returned. Supports the Python standard library "
                + "(math, json, re, datetime, statistics, itertools...). Use it for calculations, data processing, "
                + "generating content, working with files and anything that needs real computation. "
                + "The first run boots the engine (needs internet once); later runs are instant.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "code": .object([
                        "type": .string("string"),
                        "description": .string("The Python source to run, e.g. 'print(sum(range(100)))'"),
                    ]),
                    "save_output_to": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional workspace path. When set, the combined output is ALSO saved as a file the user can download."),
                    ]),
                ]),
                "required": .array([.string("code")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let code = arguments["code"]?.stringValue,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'code'.", isError: true)
        }

        let output: String
        // V4.5.2: in cloud mode Python runs on the REAL Ubuntu machine
        // (full CPython + system packages); locally it runs on Pyodide.
        if CloudRouting.active {
            do {
                let script = "python3 <<'ASTRAL_PY_EOF'\n\(code)\nASTRAL_PY_EOF"
                let (cloudOutput, exitCode) = try await E2BComputer.shared.run(
                    script, timeout: 120)
                output = cloudOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if exitCode != 0 {
                    return ToolResult(
                        content: "Python error (cloud):\n\(output.isEmpty ? "exit code \(exitCode)" : output)",
                        isError: true)
                }
            } catch {
                // Fall back to the local Pyodide engine.
                do {
                    output = try await PythonEngine.shared.run(code, timeout: 90)
                } catch {
                    return ToolResult(content: "Python error: \(error.localizedDescription)", isError: true)
                }
            }
        } else {
            do {
                output = try await PythonEngine.shared.run(code, timeout: 90)
            } catch {
                return ToolResult(content: "Python error: \(error.localizedDescription)", isError: true)
            }
        }

        var content = output.isEmpty ? "(no output - the code ran successfully)" : output

        if let saveTo = arguments["save_output_to"]?.stringValue, !saveTo.isEmpty, !output.isEmpty {
            do {
                let url = try context.workspace.write(path: saveTo, content: output)
                NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
                content += "\n[output saved to workspace: \(saveTo) — \(url.lastPathComponent)]"
            } catch {
                content += "\n[could not save output file: \(error.localizedDescription)]"
            }
        }

        return ToolResult(content: content)
    }
}

/// Runs commands on a REAL Ubuntu Linux machine in the cloud (E2B
/// microVM - the same infrastructure Manus uses). Full bash, apt, real
/// Python with pip, a genuine file system. Only available when the user
/// configured an E2B API key in Settings.
///
/// V4.7.0: the machine is the agent's OWN computer — when a command is
/// blocked by permissions it is automatically re-run with sudo (root),
/// so apt installs, system files and root-only operations all work.
@MainActor
final class CloudExecTool: AgentTool {

    let name = "cloud_exec"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Run a bash command on your REAL Ubuntu Linux cloud computer (E2B) — a full machine you hold ROOT on. "
                + "Any bash command, apt-get, real Python 3 with pip, git, curl, wget, ffmpeg, compilation — everything, "
                + "and permission errors are auto-escalated with sudo (root), so nothing is ever blocked. "
                + "The command runs with /bin/bash -lc in /home/user. stdout, stderr and the exit code are returned. "
                + "Use it for the big jobs the local device cannot do; prefer the local exec tool for simple file work (faster).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bash command line, e.g. 'apt-get install -y jq && jq --version' or 'python3 -c \"print(2**100)\"'"),
                    ]),
                    "timeout_seconds": .object([
                        "type": .string("integer"),
                        "description": .string("Optional timeout in seconds (default 120, max 600)"),
                    ]),
                ]),
                "required": .array([.string("command")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard E2BComputer.shared.isConfigured else {
            return ToolResult(
                content: "Error: no cloud computer configured. Ask the user to add an E2B API key in Settings > Cloud Computer.",
                isError: true)
        }
        guard let command = arguments["command"]?.stringValue,
              !command.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'command'.", isError: true)
        }
        let timeout = min(max(arguments["timeout_seconds"]?.intValue ?? 120, 10), 600)

        do {
            let (output, exitCode) = try await E2BComputer.shared.run(
                command, timeout: TimeInterval(timeout))
            var content = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { content = "(no output)" }
            if exitCode != 0 {
                content += "\n[exit code: \(exitCode)]"
            }
            return ToolResult(content: content, isError: exitCode != 0)
        } catch {
            return ToolResult(content: "Cloud computer error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Downloads a file from the cloud Linux machine into the local workspace
/// so the user can open / share / keep it on their iPhone.
@MainActor
final class CloudPullTool: AgentTool {

    let name = "cloud_file_pull"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Download a file from the cloud Linux computer into the user's local workspace (visible in the Files tab "
                + "and the iPhone Files app). Use it after cloud_exec produced a file the user should receive.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path on the cloud machine, e.g. /home/user/report.pdf"),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        do {
            let name = try await E2BComputer.shared.pullFile(path: path, into: context.workspace)
            return ToolResult(content: "Downloaded \(path) into the workspace as \(name). The user can find it in the Files tab.")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Uploads a file from the local workspace onto the cloud Linux machine
/// (V4.7.0) — the missing half of the two-computer mirror: local files
/// the agent wants to process with real Linux power (ffmpeg, pandas,
/// gcc…) land on the cloud machine under the same relative path.
@MainActor
final class CloudPushTool: AgentTool {

    let name = "cloud_file_push"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Upload a file from the local workspace onto the cloud Linux computer, keeping the same relative path. "
                + "Use it before cloud_exec when a workspace file needs real Linux tools (ffmpeg, pandas, gcc, apt packages) "
                + "that only exist on the cloud machine.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace path of the file to upload, e.g. uploads/video.mp4 or data.csv"),
                    ]),
                    "cloud_path": .object([
                        "type": .string("string"),
                        "description": .string("Optional destination path on the cloud machine (defaults to /home/user/<same path>)"),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let localPath = arguments["path"]?.stringValue, !localPath.isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'path'.", isError: true)
        }
        guard let localURL = context.workspace.url(for: localPath),
              let data = try? Data(contentsOf: localURL) else {
            return ToolResult(content: "Error: '\(localPath)' was not found in the workspace.", isError: true)
        }
        let cloudPath = arguments["cloud_path"]?.stringValue
            ?? "/home/user/" + localPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        do {
            try await E2BComputer.shared.pushFile(path: cloudPath, data: data)
            return ToolResult(
                content: "Uploaded \(localPath) (\(data.count) bytes) to the cloud computer at \(cloudPath). "
                    + "It is ready for cloud_exec now.")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}
