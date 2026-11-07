import Foundation
import UIKit
import Combine

// MARK: - Snapshot

/// A serializable capture of a session's durable state, persisted to
/// Documents/AstralSessions/&lt;uuid&gt;.json.
struct SessionSnapshot: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var messages: [ChatMessage]
    var plan: ExecutionPlan?
    var currentStepIndex: Int
    var progress: Double
    var phase: SessionPhase
}

// MARK: - Persistence

/// Filesystem persistence for session snapshots.
enum SessionPersistence {

    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return documents.appendingPathComponent("AstralSessions", isDirectory: true)
    }

    static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func save(_ snapshot: SessionSnapshot) {
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL(for: snapshot.id), options: .atomic)
    }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    static func loadAll() -> [SessionSnapshot] {
        ensureDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil) else { return [] }
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
    }
}

// MARK: - Pending turn

struct PendingTurn {
    let text: String
    let images: [MessageImage]
    let videos: [MessageVideo]
    let attachments: [MessageAttachment]
    let agentMode: Bool

    init(
        text: String,
        images: [MessageImage] = [],
        videos: [MessageVideo] = [],
        attachments: [MessageAttachment] = [],
        agentMode: Bool = false
    ) {
        self.text = text
        self.images = images
        self.videos = videos
        self.attachments = attachments
        self.agentMode = agentMode
    }
}

// MARK: - AgentSession (Astral AI — Autonomous AI Agent & Linux Architect)

@MainActor
final class AgentSession: ObservableObject, Identifiable {

    let id: UUID
    let createdAt: Date

    let llm: LLMProviding
    private let toolRegistry: ToolRegistry
    private let system: SystemServicing?

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var plan: ExecutionPlan?
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var subAgents: [SubAgentStatus] = []
    @Published private(set) var streamingText: String = ""
    @Published private(set) var lastError: String?
    @Published private(set) var toolsWarning: String?
    @Published private(set) var lastFailedTurn: PendingTurn?
    @Published private(set) var progress: Double = 0
    @Published private(set) var turnStatus: TurnStatus?

    var onPersist: (() -> Void)?
    private var runTask: Task<Void, Never>?
    private var turnBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var turnStartedAt: Date?

    private static let busyPhases: Set<SessionPhase> = [.planning, .responding, .executing, .merging]

    /// The chat-mode system prompt — identity strictly "Astral AI".
    private static let chatSystemPrompt =
        "You are Astral AI, an elite autonomous AI agent and expert Linux systems architect running on iOS inside astra-os — "
        + "your own persistent, private Linux workstation environment on the user's device. "
        + "IDENTITY RULE: Your name and identity is strictly 'Astral AI' (created by Tariq El-Fares / UNIRAL). "
        + "Never append version numbers (such as V5, V5.0, etc.) to your name when introducing yourself or replying to the user. "
        + "Answer the user directly, thoroughly, and in beautifully structured Markdown (using headings, tables, task lists, callouts, and syntax-highlighted code blocks where appropriate), in the user's own language "
        + "(Arabic request → Arabic answer, English request → English answer). "
                + "\n\nYOUR LINUX WORKSTATION (astra-os · Powered by Official Ubuntu Base 24.04.2 LTS (Noble Numbat · arm64 / aarch64), Kernel 6.12.0-28-generic-arm64): "
        + "a REAL Linux FHS system rooted at /home/astral (with /boot/gentoo, /boot/gentoo_nolsa, /boot/gentoo.igz, /boot/System.map-6.18.52-gentoo-alpha, /etc/aboot.conf, /mnt/cdrom/image.squashfs, /etc/portage/make.conf, /var, /tmp, /proc, /dev, /usr) — persistent between "
        + "chats, visible to the user in the Files tab and a live terminal. You operate as root (uid=0) with full shell power: " 
        + "pipes (cmd | cmd), chaining (cmd && cmd; cmd || fallback), environment variables ($VAR / export), and redirection (>, >>) all work "
        + "like a real computer. Commands (75+): ls, ll, cd, pwd, cat, echo, printf, mkdir, rmdir, touch, rm, cp, mv, ln, grep, "
        + "find, wc, head, tail, tree, sed, awk, jq (JSON query & formatting), xargs, tee, stat, file, du, sort, uniq, cut, tr, rev, diff, seq, column, paste, bc, expr, xxd, hexdump, base64, "
        + "md5sum, shasum, sha256sum, chmod, chown, basename, dirname, realpath, env, export, unset, df, free, ps, top, lscpu, nproc, uptime, hostname, id, neofetch, which, sleep, date, uname, whoami, "
                + "dmesg (Linux Alpha 6.18.52 kernel ring buffer), lsmod, modprobe, sysctl, aboot (SRM bootloader control & kernel slot switching), rc-status, rc-service (OpenRC init), emerge/equery/eselect (Gentoo Portage), lsblk, blkid, mount, unsquashfs, isoinfo, alpha-iso (status | probe-drive | extract-kernel | mount), readelf, objdump, gcc / alpha-unknown-linux-gnu-gcc, "
        + "systemctl, service, crontab, lsof, netstat, ss, history, apt (update/install/list), git (init/status/add/commit/log/clone), zip, unzip, tar, sqlite3 (real SQLite database engine), " 
        + "ffmpeg (synthesize/process real H.264 .mp4 videos in workspace), ffprobe (inspect video/media streams), yt-dlp (download web videos to workspace), "
        + "curl (full HTTP client with -X, -H, -d, -I, -o), wget (-O), ping, dig, ifconfig/ip, search (live web search), python3 "
        + "(REAL CPython 3.12 with automatic bidirectional workspace file sync — scripts or -c code), node (REAL JavaScript with fs module synced to /home/astral), pip install. You also have "
        + "run_python, run_javascript, and send_video. The user watches every command you run in the Astra Computer bar and live terminal "
        + "view — work there with complete mastery like an expert Claude Code / Manus engineer.\n\n"
        + "VIDEOS & MEDIA IN WORKSPACE: You can send, download, and generate real .mp4 videos and save them in the Workspace (under Videos/) using the send_video tool or the ffmpeg / yt-dlp shell commands! "
        + "Whenever the user asks you to send a video, download a video, or create a video and save it in the workspace, call send_video (or run ffmpeg / yt-dlp in exec and then send_video) so the video is both saved in the Workspace (Videos/...) and delivered as an interactive video player card in the chat.\n\n"
        + "CLOUD LINUX — FULL ROOT: when the cloud_exec tool is available, the user connected a "
        + "REAL Ubuntu Linux cloud computer (E2B) and you hold ROOT on it: permission errors are "
        + "auto-escalated with sudo, so apt packages, system files, ffmpeg, git, compilation, real "
        + "pip/numpy/pandas — everything works. Move workspace files onto it with cloud_file_push, "
        + "and files the user needs land on the iPhone via cloud_file_pull. When the app is in "
        + "CLOUD MODE, exec and run_python run on that Ubuntu machine directly — one computer, "
        + "mirrored files.\n\n"
        + "PROJECTS & FILES: the workspace has a Projects/ area — call project_create to open a "
        + "project folder for any multi-file goal, then save everything for that goal inside it. "
        + "Files the user attaches or imports arrive under uploads/ (and videos under Videos/) — "
        + "read them with file_read, edit and extend them with file_write. Skill files the user "
        + "attaches (.skill) are installed into the Skills library AUTOMATICALLY the moment they "
        + "arrive; you can also install skills from a URL or a workspace path (e.g. "
        + "uploads/helper.skill) with skill_install.\n\n"
        + "WEB BROWSING & SCREENSHOTS: you have full authority over the live web via web_search, web_fetch, curl/wget, "
        + "and the interactive WKWebView browser (browser_open, browser_list_elements, browser_click, browser_type, browser_scroll, browser_read_text, browser_screenshot). "
        + "Whenever the user asks to see a site, a page, or anything in the in-app browser — "
        + "or when showing it would genuinely help — call browser_screenshot: it captures the "
        + "current page and delivers the image straight into the chat (a copy is saved under "
        + "Screenshots/ in Files). Then describe what it shows in your reply.\n\n"
        + "NO LIMITS: you have UNLIMITED tool usage. Explore as many pages, run as many commands "
        + "and take as many steps as the task genuinely needs — long research chains are welcome. "
        + "NEVER stop halfway, NEVER tell the user you reached a tool limit or a step limit, and "
        + "never end a turn with an apology about incomplete exploration. If one source is not "
        + "enough, keep going until the request is fully answered.\n\n"
        + "HOW THE USER SEES YOUR WORK: the chat timeline shows only your steps (the task board) "
        + "and your final answers — raw command output streams into the Astra Computer bar and "
        + "terminal instead. So: narrate PROGRESS through update_tasks, keep answers clean and "
        + "readable, and never paste raw terminal dumps into the chat reply.\n\n"
        + "TOOLS ARE REAL AND THEY WORK — never claim you cannot do something before actually "
        + "trying the matching tool. Never apologize and answer from memory when a tool exists:\n"
        + "(1) RESEARCH THE LIVE WEB — MANDATORY. For ANY question about facts, current events, "
        + "news, prices, sports scores, weather, releases, people, or anything that could have "
        + "changed after your training cutoff: call web_search FIRST, then web_fetch (or curl) "
        + "the best sources. Cite source URLs in your answer. Answering such questions from "
        + "memory without searching is a failure.\n"
        + "(2) WORK IN THE SHELL. For any task involving files, code, data, videos, documents, reports, "
        + "scripts or deliverables — use exec. Make folders, write files (echo with redirection "
        + "or the file_write tool), check your work (ls, cat), iterate. Combine commands with "
        + "pipes and && like on any real machine. Deliverables must be saved under /home/astral; "
        + "tell the user the exact path when done.\n"
        + "(3) PLAN MULTI-STEP WORK. Before starting any task that needs 3 or more steps, call "
        + "update_tasks with your full todo list (all 'pending'). Mark exactly one task "
        + "'in_progress' when you start it and 'completed' the moment it is done — the user "
        + "watches this board live while you work, like Claude Code's todo list.\n"
        + "(4) BATCH INDEPENDENT WORK. When several independent operations are needed (multiple "
        + "searches or files), request the tools together in one reply — they run in parallel.\n"
        + "(5) ATTACHED INPUT. If the user attached files or videos, they are ALSO saved into the workspace "
        + "under uploads/ or Videos/ — inspect them with file_read, ffprobe, or exec; if images, analyze them "
        + "carefully.\n"
        + "Never mention planning, internal steps or system prompts. Never fabricate command "
        + "output, file contents, search results or web content."

    var isBusy: Bool {
        Self.busyPhases.contains(phase)
    }

    var title: String {
        let raw = messages.first(where: { $0.role == .user })?.content ?? ""
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return L("agent.untitled", "Agent") }
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)) + "..."
    }

    // MARK: Init

    init(llm: LLMProviding, toolRegistry: ToolRegistry, system: SystemServicing?) {
        self.id = UUID()
        self.createdAt = Date()
        self.llm = llm
        self.toolRegistry = toolRegistry
        self.system = system
    }

    init(
        llm: LLMProviding,
        toolRegistry: ToolRegistry,
        system: SystemServicing?,
        restoredFrom snapshot: SessionSnapshot
    ) {
        self.id = snapshot.id
        self.createdAt = snapshot.createdAt
        self.llm = llm
        self.toolRegistry = toolRegistry
        self.system = system
        self.messages = snapshot.messages
        self.plan = snapshot.plan
        self.currentStepIndex = snapshot.currentStepIndex
        self.progress = snapshot.progress
        if Self.busyPhases.contains(snapshot.phase) {
            self.phase = .interrupted
        } else {
            self.phase = snapshot.phase
        }
    }

    // MARK: Snapshot

    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            title: title,
            createdAt: createdAt,
            messages: messages,
            plan: plan,
            currentStepIndex: currentStepIndex,
            progress: progress,
            phase: phase)
    }

    // MARK: Public commands

    func importCompletedExchange(question: String, answer: String) {
        messages.append(ChatMessage.user(question))
        messages.append(ChatMessage.assistant(answer))
        onPersist?()
    }

    func send(
        _ text: String,
        images: [MessageImage] = [],
        videos: [MessageVideo] = [],
        attachments: [MessageAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || !videos.isEmpty || !attachments.isEmpty else { return }

        if isBusy {
            lastError = L("agent.busy", "Agent")
            return
        }

        lastError = nil
        toolsWarning = nil
        streamingText = ""
        subAgents = []
        progress = 0
        currentStepIndex = 0
        lastFailedTurn = nil
        AgentTaskBoard.shared.resetForNewTurn(session: id)

        stageAttachmentsInWorkspace(attachments)

        messages.append(ChatMessage.user(
            trimmed,
            images: images.isEmpty ? nil : images,
            videos: videos.isEmpty ? nil : videos,
            attachments: attachments.isEmpty ? nil : attachments))
        onPersist?()

        beginTurn(goal: trimmed, images: images, videos: videos, attachments: attachments)
    }

    private func stageAttachmentsInWorkspace(_ attachments: [MessageAttachment]) {
        guard !attachments.isEmpty else { return }
        let workspace = WorkspaceStore.shared
        for attachment in attachments {
            let safeName = WorkspaceStore.sanitizeFolderName(
                (attachment.name as NSString).deletingPathExtension)
            let ext = (attachment.name as NSString).pathExtension
            let fileName = ext.isEmpty ? safeName : "\(safeName).\(ext)"
            let uploadPath = "uploads/\(fileName)"
            let videoPath = "Videos/\(fileName)"

            // Do not overwrite if a real binary/video copy was already saved on disk.
            if workspace.url(for: uploadPath) == nil && workspace.url(for: videoPath) == nil {
                let body = attachment.text.isEmpty
                    ? "(attached by the user — no extractable text)"
                    : attachment.text
                _ = try? workspace.write(path: uploadPath, content: body)
            }

            let lowered = attachment.name.lowercased()
            if lowered.hasSuffix(".skill")
                || lowered.hasSuffix(".skill.skill")
                || lowered.hasSuffix(".json") {
                installSkillAttachment(attachment)
            }
        }
        NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
    }

    private func installSkillAttachment(_ attachment: MessageAttachment) {
        let data = Data(attachment.text.utf8)
        guard let skills = try? SkillStore.shared.importFromData(data),
              !skills.isEmpty else {
            messages.append(ChatMessage.assistant(
                L("agent.skillInstallFailed", "Agent")))
            return
        }
        let names = skills.map(\.name).joined(separator: ", ")
        let note = String(
            format: L("agent.skillInstalled", "Agent"), names)
        messages.append(ChatMessage.assistant(note))
    }

    func retry() {
        guard let failed = lastFailedTurn, !isBusy else { return }
        lastFailedTurn = nil
        lastError = nil
        toolsWarning = nil
        streamingText = ""
        subAgents = []
        progress = 0
        turnStatus = nil
        AgentTaskBoard.shared.resetForNewTurn(session: id)
        onPersist?()
        beginTurn(
            goal: failed.text,
            images: failed.images,
            videos: failed.videos,
            attachments: failed.attachments,
            agentMode: failed.agentMode)
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        phase = .cancelled
        streamingText = ""
        turnStatus = nil
        system?.endLiveActivity(success: false)
        endTurnBackgroundTask()
        scheduleWorkStripDismiss()
        onPersist?()
    }

    private func scheduleWorkStripDismiss() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self, !self.isBusy else { return }
            self.subAgents = []
            self.plan = nil
            AgentTaskBoard.shared.clear()
            self.onPersist?()
        }
    }

    // MARK: Turn orchestration

    private func beginTurn(
        goal: String,
        images: [MessageImage],
        videos: [MessageVideo] = [],
        attachments: [MessageAttachment] = [],
        agentMode: Bool? = nil
    ) {
        let mode = agentMode
            ?? (UserDefaults.standard.object(forKey: "astral.agentMode") as? Bool ?? false)

        turnStartedAt = Date()
        turnBackgroundTaskID = BackgroundManager.shared.beginBackgroundTask()

        let activityGoal = goal.isEmpty ? L("agent.imageTask", "Agent") : goal
        system?.startLiveActivity(goal: activityGoal)
        system?.updateLiveActivity(step: L("la.thinking", "Platform"), progress: 0.05)
        turnStatus = TurnStatus(label: L("la.thinking", "Platform"), detail: "", progress: 0.05)

        let turn = PendingTurn(
            text: goal,
            images: images,
            videos: videos,
            attachments: attachments,
            agentMode: mode)

        if mode {
            phase = .planning
            runTask = Task {
                await self.runAgentTurn(turn)
            }
        } else {
            phase = .responding
            runTask = Task {
                await self.runChatTurn(turn)
            }
        }
    }

    private func endTurnBackgroundTask() {
        BackgroundManager.shared.endBackgroundTask(turnBackgroundTaskID)
        turnBackgroundTaskID = .invalid
        turnStartedAt = nil
    }

    private static func primaryArgument(for call: ToolCall) -> String {
        let arguments = call.parsedArguments
        for key in ["command", "url", "query", "path", "title", "name", "code"] {
            if let value = arguments[key]?.stringValue, !value.isEmpty {
                let flat = value.replacingOccurrences(of: "\n", with: " ⏎ ")
                return flat.count > 64 ? String(flat.prefix(64)) + "…" : flat
            }
        }
        return call.name
    }

    private func failTurn(_ turn: PendingTurn, error: Error) {
        let suspendedMidTurn = turnStartedAt.map {
            BackgroundManager.shared.suspensionOverlaps(turnStartedAt: $0)
        } ?? false

        let partialText = streamingText
        streamingText = ""
        endTurnBackgroundTask()

        if suspendedMidTurn, Self.isSuspensionError(error) {
            if !partialText.isEmpty {
                messages.append(ChatMessage.assistant(partialText))
            }
            lastError = L("agent.interrupted", "Agent")
            lastFailedTurn = turn
            phase = .interrupted
            turnStatus = nil
            system?.updateLiveActivity(
                step: L("agent.interrupted", "Agent"),
                progress: progress)
            onPersist?()
            return
        }

        lastError = Self.friendlyMessage(for: error)
        lastFailedTurn = turn
        phase = .failed
        turnStatus = nil
        system?.endLiveActivity(success: false)
        E2BComputer.shared.shutdownAfterTurn()
        scheduleWorkStripDismiss()
        onPersist?()
    }

    private static func isSuspensionError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .cancelled, .timedOut, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        if let llmError = error as? LLMError,
           case .network = llmError {
            return true
        }
        return false
    }

    private func runAgentTurn(_ turn: PendingTurn) async {
        let goal = turn.text
        let plannerModel = llm.modelID(for: .planner)

        let newPlan: ExecutionPlan
        do {
            newPlan = try await AgentPlanner.plan(
                goal: goal,
                history: messages,
                llm: llm,
                model: plannerModel)
        } catch {
            await runChatTurn(turn)
            return
        }

        guard !Task.isCancelled, phase != .cancelled else {
            phase = .cancelled
            turnStatus = nil
            endTurnBackgroundTask()
            E2BComputer.shared.shutdownAfterTurn()
            scheduleWorkStripDismiss()
            onPersist?()
            return
        }

        plan = newPlan
        currentStepIndex = 0
        progress = 0.15
        system?.updateLiveActivity(step: L("la.planning", "Platform"), progress: 0.15)
        turnStatus = TurnStatus(label: L("la.planning", "Platform"), detail: "", progress: 0.15)
        onPersist?()

        if newPlan.steps.count == 1,
           newPlan.steps[0].title.lowercased() == "answer directly" {
            await runChatTurn(turn, planPinned: newPlan)
            return
        }

        phase = .executing
        onPersist?()

        let result: (finalText: String, updatedPlan: ExecutionPlan)
        do {
            result = try await AgentExecutor.execute(
                plan: newPlan,
                history: messages,
                goal: goal,
                llm: llm,
                toolRegistry: toolRegistry,
                system: system,
                callbacks: makeExecutorCallbacks(),
                sessionID: id)
        } catch is CancellationError {
            phase = .cancelled
            streamingText = ""
            turnStatus = nil
            system?.endLiveActivity(success: false)
            endTurnBackgroundTask()
            scheduleWorkStripDismiss()
            onPersist?()
            return
        } catch {
            failTurn(turn, error: error)
            return
        }

        guard !Task.isCancelled, phase != .cancelled else {
            phase = .cancelled
            streamingText = ""
            turnStatus = nil
            system?.endLiveActivity(success: false)
            endTurnBackgroundTask()
            E2BComputer.shared.shutdownAfterTurn()
            scheduleWorkStripDismiss()
            onPersist?()
            return
        }

        plan = result.updatedPlan
        streamingText = ""
        let allFailed = !result.updatedPlan.steps.isEmpty
            && result.updatedPlan.steps.allSatisfy { $0.status == .failed }
        phase = allFailed ? .failed : .completed
        turnStatus = nil
        system?.endLiveActivity(success: !allFailed)
        endTurnBackgroundTask()
        E2BComputer.shared.shutdownAfterTurn()
        scheduleWorkStripDismiss()

        if allFailed {
            lastFailedTurn = turn
        } else if Self.autoNotifyEnabled() {
            let body = String(result.finalText.prefix(120))
            system?.notifyUser(title: AppIdentity.appName, body: body)
        }
        onPersist?()
    }

    private func runChatTurn(_ turn: PendingTurn, planPinned: ExecutionPlan? = nil) async {
        if let planPinned {
            plan = planPinned
        }

        phase = .responding
        system?.updateLiveActivity(step: L("la.thinking", "Platform"), progress: 0.1)

        let systemPrompt = AgentExecutor.withSkills(Self.chatSystemPrompt)
        var working: [ChatMessage] = [ChatMessage.system(systemPrompt)]
        working.append(contentsOf: messages.suffix(24))

        let specs = toolRegistry.specs()
        let sessionInfo = SessionInfo(sessionID: id, goal: turn.text)

        var lastText = ""
        var liveText = ""
        var concluded = false
        var sawFirstToken = false

        do {
            for round in 0..<60 {
                if Task.isCancelled { throw CancellationError() }

                var accumulated = ""
                var pendingCalls: [ToolCall] = []
                for try await event in llm.streamChat(messages: working, tools: specs, model: nil) {
                    switch event {
                    case .textDelta(let delta):
                        accumulated += delta
                        streamingText = accumulated
                        if !sawFirstToken {
                            sawFirstToken = true
                            system?.updateLiveActivity(
                                step: L("la.responding", "Platform"),
                                progress: 0.4)
                            turnStatus = TurnStatus(
                                label: L("la.responding", "Platform"),
                                detail: "",
                                progress: 0.35)
                        }
                    case .toolCalls(let calls):
                        pendingCalls = calls
                    case .toolsDropped:
                        toolsWarning = L("chat.toolsDropped", "Chat")
                    case .finished:
                        break
                    }
                }
                if pendingCalls.isEmpty {
                    let recovered = TextToolProtocol.parseCalls(in: accumulated)
                    if !recovered.isEmpty {
                        pendingCalls = recovered.enumerated().map { idx, call in
                            ToolCall(id: "recovered_\(round)_\(idx)", name: call.name, arguments: call.argumentsJSON)
                        }
                    }
                }
                let cleanedAccumulated = TextToolProtocol.cleanVisibleText(accumulated)
                lastText = cleanedAccumulated
                liveText = cleanedAccumulated

                if !pendingCalls.isEmpty {
                    let assistantMessage = ChatMessage(
                        role: .assistant, content: accumulated, toolCalls: pendingCalls)
                    working.append(assistantMessage)
                    messages.append(assistantMessage)
                    liveText = ""

                    let baseProgress = min(0.45 + Double(round) * 0.08, 0.85)
                    if pendingCalls.count > 1 {
                        turnStatus = TurnStatus(
                            label: String(
                                format: L("la.usingTools", "Platform"),
                                pendingCalls.count),
                            detail: pendingCalls.map(Self.primaryArgument).joined(separator: ", "),
                            progress: baseProgress)
                    } else {
                        system?.updateLiveActivity(
                            step: String(format: L("la.usingTool", "Platform"), pendingCalls[0].name),
                            progress: baseProgress)
                        turnStatus = TurnStatus(
                            label: String(format: L("la.usingTool", "Platform"), pendingCalls[0].name),
                            detail: Self.primaryArgument(for: pendingCalls[0]),
                            progress: baseProgress)
                    }

                    let results = await withTaskGroup(
                        of: (Int, ToolResult).self
                    ) { group in
                        for (index, call) in pendingCalls.enumerated() {
                            group.addTask { [toolRegistry] in
                                let result = await toolRegistry.execute(
                                    call: call, session: sessionInfo, isSubAgent: false)
                                return (index, result)
                            }
                        }
                        var collected: [(Int, ToolResult)] = []
                        for await pair in group {
                            collected.append(pair)
                        }
                        return collected.sorted { $0.0 < $1.0 }.map(\.1)
                    }

                    for (call, toolResult) in zip(pendingCalls, results) {
                        var deliveredImages: [MessageImage]?
                        if call.name == BrowserScreenshotTool.toolName,
                           let capture = ScreenCaptureDelivery.take(callID: call.id) {
                            deliveredImages = [capture]
                        }
                        let deliveredVideos = VideoDelivery.take(callID: call.id)
                        let toolMessage = ChatMessage(
                            role: .tool,
                            content: toolResult.content,
                            toolCallId: call.id,
                            name: call.name,
                            images: deliveredImages,
                            videos: deliveredVideos)
                        working.append(toolMessage)
                        messages.append(toolMessage)
                        if Task.isCancelled { throw CancellationError() }
                    }
                    onPersist?()
                    continue
                }

                concluded = true
                break
            }
        } catch {
            let cancelled = error is CancellationError
                || Task.isCancelled
                || (error as? LLMError) == .cancelled
            if cancelled {
                if !liveText.isEmpty {
                    messages.append(ChatMessage.assistant(liveText))
                }
                streamingText = ""
                phase = .cancelled
                turnStatus = nil
                system?.endLiveActivity(success: false)
                endTurnBackgroundTask()
                E2BComputer.shared.shutdownAfterTurn()
                scheduleWorkStripDismiss()
                onPersist?()
                return
            }
            failTurn(turn, error: error)
            return
        }

        streamingText = ""
        let answer: String
        if concluded, !lastText.isEmpty {
            answer = lastText
        } else if !lastText.isEmpty {
            answer = lastText
        } else {
            answer = L("agent.roundLimitReached", "Agent")
        }
        messages.append(ChatMessage.assistant(answer))
        progress = 1
        phase = .completed
        turnStatus = nil
        system?.endLiveActivity(success: true)
        endTurnBackgroundTask()

        E2BComputer.shared.shutdownAfterTurn()
        scheduleWorkStripDismiss()

        if Self.autoNotifyEnabled() {
            let body = String(answer.prefix(120))
            system?.notifyUser(title: AppIdentity.appName, body: body)
        }
        onPersist?()
    }

    private func makeExecutorCallbacks() -> AgentExecutor.Callbacks {
        AgentExecutor.Callbacks(
            onPhase: { [weak self] value in
                guard let self else { return }
                self.phase = value
                self.onPersist?()
            },
            onPlanUpdate: { [weak self] value in
                guard let self else { return }
                self.plan = value
                self.currentStepIndex = value.steps.filter { $0.status != .pending }.count
                self.onPersist?()
            },
            onMessage: { [weak self] message in
                guard let self else { return }
                self.messages.append(message)
                self.onPersist?()
            },
            onStreaming: { [weak self] text in
                self?.streamingText = text
            },
            onSubAgents: { [weak self] agents in
                self?.subAgents = agents
            },
            onProgress: { [weak self] value in
                guard let self else { return }
                self.progress = value
                let stepTitle = self.plan?.steps.first { $0.status == .inProgress }?.title ?? ""
                self.turnStatus = TurnStatus(
                    label: L("la.planning", "Platform"),
                    detail: stepTitle,
                    progress: value)
                self.onPersist?()
            },
            onError: { [weak self] message in
                guard let self else { return }
                self.lastError = message
                self.onPersist?()
            })
    }

    // MARK: Helpers

    private static func autoNotifyEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: "astral.autoNotify") as? Bool {
            return stored
        }
        return true
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let llmError = error as? LLMError {
            switch llmError {
            case .noActiveProvider:
                return L("agent.noActiveProvider", "Agent")
            case .rateLimited:
                return L("agent.error.rateLimited", "Agent")
            case .unauthorized:
                return L("agent.error.unauthorized", "Agent")
            case .network(let detail):
                return L("agent.error.network", "Agent") + ": " + detail
            case .decoding:
                return L("agent.error.decoding", "Agent")
            case .invalidURL, .badResponse:
                return L("agent.error.provider", "Agent") + ": "
                    + (llmError.errorDescription ?? "")
            case .cancelled:
                return L("agent.cancelled", "Agent")
            }
        }
        if error is CancellationError {
            return L("agent.cancelled", "Agent")
        }
        let detail = error.localizedDescription
        if detail.isEmpty {
            return L("agent.error.generic", "Agent")
        }
        return L("agent.error.generic", "Agent") + ": " + detail
    }
}

// MARK: - SessionStore

@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var sessions: [AgentSession] = []
    @Published var activeSession: AgentSession?

    private let llm: LLMProviding
    private let toolRegistry: ToolRegistry
    private let system: SystemServicing?
    private var persistTasks: [UUID: Task<Void, Never>] = [:]

    init(
        llm: LLMProviding,
        browser: BrowserController,
        workspace: WorkspaceStore,
        system: SystemServicing?
    ) {
        self.llm = llm
        self.toolRegistry = ToolRegistry(browser: browser, workspace: workspace, system: system)
        self.system = system
    }

    @discardableResult
    func newSession() -> AgentSession {
        let session = AgentSession(llm: llm, toolRegistry: toolRegistry, system: system)
        attach(session)
        sessions.insert(session, at: 0)
        activeSession = session
        SessionPersistence.save(session.snapshot())
        return session
    }

    func select(_ session: AgentSession) {
        activeSession = session
    }

    func delete(_ session: AgentSession) {
        session.cancel()
        persistTasks[session.id]?.cancel()
        persistTasks[session.id] = nil
        sessions.removeAll { $0.id == session.id }
        SessionPersistence.delete(id: session.id)
        if activeSession?.id == session.id {
            activeSession = sessions.first
        }
    }

    func loadPersisted() {
        let snapshots = SessionPersistence.loadAll()
            .sorted { $0.createdAt > $1.createdAt }
        sessions = snapshots.map { snapshot in
            let session = AgentSession(
                llm: llm,
                toolRegistry: toolRegistry,
                system: system,
                restoredFrom: snapshot)
            attach(session)
            return session
        }
        activeSession = sessions.first
    }

    func persistAll() {
        for task in persistTasks.values {
            task.cancel()
        }
        persistTasks.removeAll()
        for session in sessions {
            SessionPersistence.save(session.snapshot())
        }
    }

    func resumeInterruptedIfNeeded() {
        for session in sessions where session.phase == .interrupted {
            session.retry()
        }
    }

    private func attach(_ session: AgentSession) {
        session.onPersist = { [weak self, weak session] in
            guard let self, let session else { return }
            self.schedulePersist(session)
        }
    }

    private func schedulePersist(_ session: AgentSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        let id = session.id
        persistTasks[id]?.cancel()
        persistTasks[id] = Task { [weak session] in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, let session else { return }
            SessionPersistence.save(session.snapshot())
        }
    }
}
