import Foundation

// MARK: - Workspace tools (V4.5.2)

/// Creates a folder (with any nested parents) inside the agent workspace.
@MainActor
final class FileMkdirTool: AgentTool {

    let name = "file_mkdir"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Create a folder (and any missing parent folders) in the workspace. "
                + "Use it to organize work: projects, reports, code modules.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Workspace-relative folder path, e.g. Projects/Website"),
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
            let url = try context.workspace.createFolder(path: path)
            if ComputerModeController.shared.prefersCloud, let data = "{}".data(using: .utf8) {
                // Keep the folder present on the cloud machine too.
                try? await E2BComputer.shared.pushFile(
                    path: path + "/.keep", data: data)
            }
            NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
            return ToolResult(content: "Created folder \(path) (absolute: \(url.absoluteString))")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Creates a project folder inside Projects/ — the workspace's dedicated
/// area for multi-file work — and seeds it with a small README.
@MainActor
final class ProjectCreateTool: AgentTool {

    let name = "project_create"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Create a new project in the workspace: a dedicated folder under Projects/<name> "
                + "with a README.md describing the goal. Subsequent work for that goal (files, code, "
                + "documents, exports) should be saved inside the project folder. Returns the project path.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Short project name, e.g. 'Landing Page' or 'تقرير المبيعات'"),
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("One-line goal of the project for the README"),
                    ]),
                ]),
                "required": .array([.string("name")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let rawName = arguments["name"]?.stringValue,
              !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'name'.", isError: true)
        }

        let folderName = WorkspaceStore.sanitizeFolderName(rawName)
        let projectPath = "Projects/\(folderName)"
        let readme =
            "# \(rawName.trimmingCharacters(in: .whitespaces))\n\n"
            + (arguments["description"]?.stringValue ?? "Astral project")
            + "\n\n_Created by the Astral agent on \(Date().formatted(date: .abbreviated, time: .shortened))._\n"

        do {
            _ = try context.workspace.createFolder(path: projectPath)
            _ = try context.workspace.write(path: "\(projectPath)/README.md", content: readme)
            if ComputerModeController.shared.prefersCloud,
               let data = readme.data(using: .utf8) {
                try? await E2BComputer.shared.pushFile(
                    path: "\(projectPath)/README.md", data: data)
            }
            NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
            return ToolResult(
                content: "Project created at \(projectPath). Save all files for this goal inside it.")
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Installs a skill file into the Skills library — from a URL on the
/// internet OR from a file already in the workspace (uploads/…).
/// V4.5.6: the user can attach a `.skill` file to a message; it lands in
/// uploads/ and this tool installs it with its local path.
@MainActor
final class SkillInstallTool: AgentTool {

    let name = "skill_install"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description:
                "Install a skill into the app's Skills library, from a direct http(s) URL "
                + "OR from a file already in the workspace (e.g. uploads/helper.skill — "
                + "files the user attaches arrive there). The file must be an Astral skill "
                + "(`.skill`, `.skill.skill` or JSON format). Use it whenever the user "
                + "shares a skill link or a skill file and asks you to install it.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("Direct http(s) URL of the .skill / .skill.skill / JSON file, OR a workspace-relative path such as uploads/helper.skill"),
                    ]),
                ]),
                "required": .array([.string("url")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let rawSource = arguments["url"]?.stringValue,
              !rawSource.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResult(content: "Error: missing required parameter 'url'.", isError: true)
        }
        let source = rawSource.trimmingCharacters(in: .whitespaces)

        do {
            // Local workspace path (uploads/x.skill, Skills-drops, …) —
            // anything that is not an http(s) URL is treated as a path.
            let skills: [Skill]
            if !source.lowercased().hasPrefix("http://"),
               !source.lowercased().hasPrefix("https://") {
                let content = try context.workspace.read(path: source)
                guard let data = content.data(using: .utf8) else {
                    return ToolResult(
                        content: "Error: could not read the skill file at \(source).",
                        isError: true)
                }
                skills = try SkillStore.shared.importFromData(data)
            } else {
                skills = try await SkillStore.shared.importFromURL(source)
            }
            let names = skills.map(\.name).joined(separator: ", ")
            return ToolResult(
                content: "Skill installed successfully: \(names). It is now in the Skills tab and can be invoked with /.")
        } catch {
            return ToolResult(content: "Error installing skill: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Cloud routing helpers (V4.5.2)
//
// When ComputerMode == .cloud the whole app runs on the Ubuntu machine:
// exec and python route to the cloud, and workspace files are mirrored
// up/down so both machines see the same documents.

@MainActor
enum CloudRouting {

    /// True when execution should go to the cloud machine.
    static var active: Bool {
        ComputerModeController.shared.prefersCloud
    }

    /// Runs a command on the currently selected machine and returns
    /// terminal-shaped output ("$ command" + output), identical in both
    /// modes so the model sees one consistent computer.
    static func exec(_ command: String) async -> (content: String, isError: Bool) {
        if active {
            do {
                let (output, exitCode) = try await E2BComputer.shared.run(command, timeout: 120)
                var body = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if body.isEmpty { body = "(no output — command completed successfully)" }
                if exitCode != 0 { body += "\n(exit code \(exitCode))" }
                return ("$ \(command)\n\(body)", exitCode != 0)
            } catch {
                // The cloud path failed (network, quota, boot): fall back
                // to the local machine so the turn still completes.
                let local = await SandboxShell.shared.run(command)
                NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
                let body = local.stdout.isEmpty
                    ? "(no output — command completed successfully)"
                    : local.stdout
                let fallback = "$ \(command)\n\(body)"
                    + "\n[cloud computer unavailable — ran locally: "
                    + error.localizedDescription + "]"
                return (fallback, local.failed)
            }
        }

        let result = await SandboxShell.shared.run(command)
        NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
        var body = result.stdout
        if body.isEmpty { body = "(no output — command completed successfully)" }
        if result.failed { body += "\n(exit code \(result.exitCode))" }
        return ("$ \(command)\n\(body)", result.failed)
    }

    /// Mirrors a freshly written workspace file up to the cloud machine
    /// (best-effort; local copy always wins on failure).
    static func mirrorUp(path: String, content: String) async {
        guard active, let data = content.data(using: .utf8) else { return }
        try? await E2BComputer.shared.pushFile(path: path, data: data)
    }

    /// Mirrors a freshly written workspace file (binary) up to the cloud.
    static func mirrorUpData(path: String, data: Data) async {
        guard active else { return }
        try? await E2BComputer.shared.pushFile(path: path, data: data)
    }
}
