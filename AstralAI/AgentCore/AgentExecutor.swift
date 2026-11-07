import Foundation

// MARK: - AgentExecutor

/// Executes an approved plan step by step: sequential steps run inline with a
/// full tool loop and self-correction; consecutive parallelizable steps are
/// delegated to parallel sub-agents; a final synthesis pass merges everything
/// into the user-facing answer.
@MainActor
enum AgentExecutor {

    struct Callbacks {
        var onPhase: (SessionPhase) -> Void = { _ in }
        var onPlanUpdate: (ExecutionPlan) -> Void = { _ in }
        var onMessage: (ChatMessage) -> Void = { _ in }
        var onStreaming: (String) -> Void = { _ in }
        var onSubAgents: ([SubAgentStatus]) -> Void = { _ in }
        var onProgress: (Double) -> Void = { _ in }
        var onError: (String?) -> Void = { _ in }
    }

    static let stepSystemPrompt = "You are Astral AI, an autonomous AI agent executing one step of a plan on iOS, working inside astra-os — your persistent Linux workstation environment at /home/astral (shell commands through the exec tool: ls, cd, cat, echo with > >> redirection, mkdir, rm, cp, mv, grep, find, head, tail, sed, awk, jq, tree, curl, wget, sqlite3, ffmpeg, ffprobe, yt-dlp, search, python3 (REAL Python via Pyodide with workspace sync), node (REAL JavaScript with fs module), pip install). Your identity is strictly 'Astral AI' (never append version numbers to your name). You also have: web_search, web_fetch, browser_open/click/type/read/scroll/screenshot, send_video (send/download/generate videos in chat and save them in the workspace under Videos/), file_write/read/list/delete/zip/pdf, run_python, run_javascript, analyze_data, update_tasks, create_reminder, create_event, notify_user. When cloud_exec is available, a REAL Ubuntu Linux cloud computer (E2B) can run anything: apt, real pip (numpy/pandas), git, compilation — use it for heavy jobs and pull results back with cloud_file_pull. Real work happens in the shell: create files, organize folders, fetch and process data, generate or download videos, run code, save deliverables under /home/astral. When the current step is fully achieved, end your reply with a line starting exactly with STEP_COMPLETE: followed by a concise 2-4 sentence summary. If genuinely blocked after real attempts, end with STEP_BLOCKED: followed by the reason. Never fabricate tool results, command output or web content."

    static let synthesisSystemPrompt = "You are Astral AI, finalizing a completed multi-step task for the user. Your identity is strictly 'Astral AI' (never add version numbers to your name). You receive the original goal and every step's result. Write the final answer in rich Markdown: open with the direct answer or summary, then key findings, details, data, and links as appropriate. If files or videos were created, add a section titled '## Deliverables' listing each file path. Match the user's language exactly (Arabic request → Arabic answer). Be complete but not bloated."

    /// Appends the enabled-skills instruction block to a base system prompt.
    /// Returns the prompt unchanged when no skills are enabled.
    static func withSkills(_ base: String) -> String {
        let block = SkillStore.shared.activePromptBlock()
        guard !block.isEmpty else { return base }
        return base + "\n\n" + block
    }

    private static let maxStepRounds = 40

    // MARK: Entry point

    @discardableResult
    static func execute(
        plan: ExecutionPlan,
        history: [ChatMessage],
        goal: String,
        llm: LLMProviding,
        toolRegistry: ToolRegistry,
        system: SystemServicing?,
        callbacks: Callbacks,
        sessionID: UUID
    ) async throws -> (finalText: String, updatedPlan: ExecutionPlan) {
        var workingPlan = plan
        var workingMessages: [ChatMessage] = [ChatMessage.system(Self.withSkills(stepSystemPrompt))]
        workingMessages.append(contentsOf: history.suffix(20))

        callbacks.onPhase(.executing)
        callbacks.onPlanUpdate(workingPlan)

        var index = 0
        while index < workingPlan.steps.count {
            try Task.checkCancellation()
            let step = workingPlan.steps[index]
            guard step.status == .pending else {
                index += 1
                continue
            }

            // Group CONSECUTIVE parallelizable pending steps into one batch.
            if step.parallelizable, index + 1 < workingPlan.steps.count {
                var batchIndices: [Int] = [index]
                var scan = index + 1
                while scan < workingPlan.steps.count,
                      workingPlan.steps[scan].parallelizable,
                      workingPlan.steps[scan].status == .pending {
                    batchIndices.append(scan)
                    scan = scan + 1
                }

                if batchIndices.count >= 2 {
                    callbacks.onPhase(.merging)
                    let batchSteps = batchIndices.map { workingPlan.steps[$0] }
                    let summary = contextSummary(for: workingPlan, upTo: index)
                    let subAgentModel = llm.modelID(for: .subAgent)
                    let updatedSteps = await SubAgentRunner.run(
                        steps: batchSteps,
                        goal: goal,
                        contextSummary: summary,
                        llm: llm,
                        toolRegistry: toolRegistry,
                        system: system,
                        model: subAgentModel,
                        sessionID: sessionID) { statuses in
                            callbacks.onSubAgents(statuses)
                        }

                    for (position, batchIndex) in batchIndices.enumerated()
                    where position < updatedSteps.count {
                        workingPlan.steps[batchIndex] = updatedSteps[position]
                    }

                    callbacks.onPhase(.executing)
                    callbacks.onPlanUpdate(workingPlan)
                    publishProgress(for: workingPlan, callbacks: callbacks)
                    let batchTitle = batchSteps.first?.title ?? goal
                    system?.updateLiveActivity(step: batchTitle, progress: progressValue(for: workingPlan))
                    index = scan
                    continue
                }
            }

            // Solo step: mark in progress, publish, run.
            workingPlan.steps[index].status = .inProgress
            callbacks.onPlanUpdate(workingPlan)
            system?.updateLiveActivity(
                step: workingPlan.steps[index].title,
                progress: progressValue(for: workingPlan))

            let (updatedStep, updatedMessages) = try await runStep(
                step: workingPlan.steps[index],
                stepNumber: index + 1,
                totalSteps: workingPlan.steps.count,
                previousResults: previousResults(for: workingPlan, upTo: index),
                workingMessages: workingMessages,
                goal: goal,
                llm: llm,
                toolRegistry: toolRegistry,
                system: system,
                sessionID: sessionID,
                callbacks: callbacks)

            workingPlan.steps[index] = updatedStep
            workingMessages = updatedMessages
            callbacks.onPlanUpdate(workingPlan)
            publishProgress(for: workingPlan, callbacks: callbacks)
            index += 1
        }

        // Final synthesis.
        callbacks.onPhase(.merging)
        let allFailed = !workingPlan.steps.isEmpty
            && workingPlan.steps.allSatisfy { $0.status == .failed }
        let finalText = try await synthesize(
            goal: goal,
            plan: workingPlan,
            allFailed: allFailed,
            llm: llm,
            callbacks: callbacks)

        if allFailed {
            callbacks.onError(L("agent.allStepsFailed", "Agent"))
        }
        return (finalText, workingPlan)
    }

    // MARK: Step runner

    private static func runStep(
        step: PlanStep,
        stepNumber: Int,
        totalSteps: Int,
        previousResults: [String],
        workingMessages: [ChatMessage],
        goal: String,
        llm: LLMProviding,
        toolRegistry: ToolRegistry,
        system: SystemServicing?,
        sessionID: UUID,
        callbacks: Callbacks
    ) async throws -> (updatedStep: PlanStep, updatedMessages: [ChatMessage]) {
        var current = step

        var messages = workingMessages
        var prompt = "CURRENT STEP \(stepNumber)/\(totalSteps): \(step.title)\n"
        prompt += "DETAIL: \(step.detail)\n\nPrevious results:\n"
        prompt += previousResults.isEmpty
            ? "This is the first step."
            : previousResults.joined(separator: "\n")
        messages.append(ChatMessage.user(prompt))

        let specs = toolRegistry.specs()
        let sessionInfo = SessionInfo(sessionID: sessionID, goal: goal)
        var blockedRetried = false

        var lastNarration = ""
        for round in 0..<maxStepRounds {
            try Task.checkCancellation()

            var accumulated = ""
            var pendingCalls: [ToolCall] = []
            for try await event in llm.streamChat(messages: messages, tools: specs, model: nil) {
                switch event {
                case .textDelta(let delta):
                    accumulated += delta
                    callbacks.onStreaming(accumulated)
                case .toolCalls(let calls):
                    pendingCalls = calls
                case .toolsDropped:
                    break
                case .finished:
                    break
                }
            }
            if !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastNarration = accumulated
            }

            if pendingCalls.isEmpty {
                let recovered = TextToolProtocol.parseCalls(in: accumulated)
                if !recovered.isEmpty {
                    pendingCalls = recovered.enumerated().map { idx, call in
                        ToolCall(id: "exec_rec_\(round)_\(idx)", name: call.name, arguments: call.argumentsJSON)
                    }
                }
            }
            if !pendingCalls.isEmpty {
                let assistantMessage = ChatMessage(
                    role: .assistant, content: accumulated, toolCalls: pendingCalls)
                messages.append(assistantMessage)
                callbacks.onMessage(assistantMessage)

                for call in pendingCalls {
                    let result = await toolRegistry.execute(
                        call: call, session: sessionInfo, isSubAgent: false)
                    var deliveredImages: [MessageImage]?
                    if call.name == BrowserScreenshotTool.toolName,
                       let capture = ScreenCaptureDelivery.take(callID: call.id) {
                        deliveredImages = [capture]
                    }
                    let deliveredVideos = VideoDelivery.take(callID: call.id)
                    let toolMessage = ChatMessage(
                        role: .tool,
                        content: result.content,
                        toolCallId: call.id,
                        name: call.name,
                        images: deliveredImages,
                        videos: deliveredVideos)
                    messages.append(toolMessage)
                    callbacks.onMessage(toolMessage)
                }
                continue
            }

            // Finished without tool calls: inspect the completion markers.
            if let completeRange = accumulated.range(
                of: "STEP_COMPLETE:", options: .caseInsensitive) {
                let summary = String(accumulated[completeRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                current.result = summary.isEmpty ? accumulated : summary
                current.status = .done
                callbacks.onStreaming("")
                return (current, messages)
            }

            if let blockedRange = accumulated.range(
                of: "STEP_BLOCKED:", options: .caseInsensitive) {
                let reason = String(accumulated[blockedRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !blockedRetried {
                    blockedRetried = true
                    messages.append(ChatMessage.assistant(accumulated))
                    messages.append(
                        ChatMessage.user("That approach failed. Try an alternative approach for this step."))
                    continue
                }
                current.result = reason.isEmpty ? accumulated : reason
                current.status = .failed
                callbacks.onStreaming("")
                return (current, messages)
            }

            if round == maxStepRounds - 1 {
                let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    current.result = "The step finished without producing output."
                    current.status = .failed
                } else {
                    current.result = accumulated
                    current.status = .done
                }
                callbacks.onStreaming("")
                return (current, messages)
            }

            messages.append(ChatMessage.assistant(accumulated))
            messages.append(
                ChatMessage.user("Continue with the current step. When it is fully achieved, end your reply with STEP_COMPLETE: followed by a concise summary. If genuinely blocked, end with STEP_BLOCKED: followed by the reason."))
        }

        let trimmedNarration = lastNarration.trimmingCharacters(in: .whitespacesAndNewlines)
        current.result = trimmedNarration.isEmpty
            ? "The step completed its work."
            : trimmedNarration
        current.status = .done
        callbacks.onStreaming("")
        return (current, messages)
    }

    // MARK: Synthesis

    private static func synthesize(
        goal: String,
        plan: ExecutionPlan,
        allFailed: Bool,
        llm: LLMProviding,
        callbacks: Callbacks
    ) async throws -> String {
        var userText = "GOAL: \(goal)\n\nSTEP RESULTS:\n"
        for step in plan.steps {
            let result = step.result.isEmpty ? "(no result)" : step.result
            userText += "- \(step.title): \(result)\n"
        }
        if allFailed {
            userText += "\nNOTE: Every step failed. Write a sincere, concise apology in the user's language explaining that the task could not be completed and summarizing what went wrong."
        }

        let messages = [
            ChatMessage.system(Self.withSkills(synthesisSystemPrompt)),
            ChatMessage.user(userText),
        ]

        var finalText = ""
        do {
            for try await event in llm.streamChat(messages: messages, tools: nil, model: nil) {
                switch event {
                case .textDelta(let delta):
                    finalText += delta
                    callbacks.onStreaming(finalText)
                case .toolCalls:
                    break
                case .toolsDropped:
                    break
                case .finished:
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            finalText = ""
        }

        callbacks.onStreaming("")
        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalText = localSummary(goal: goal, plan: plan)
        }
        callbacks.onMessage(ChatMessage.assistant(finalText))
        return finalText
    }

    private static func localSummary(goal: String, plan: ExecutionPlan) -> String {
        var lines = ["# \(goal)", ""]
        for step in plan.steps {
            let status = step.status == .done ? "done" : "failed"
            let result = step.result.isEmpty ? "no result" : step.result
            lines.append("- **\(step.title)** (\(status)): \(result)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Progress helpers

    private static func publishProgress(for plan: ExecutionPlan, callbacks: Callbacks) {
        callbacks.onProgress(progressValue(for: plan))
    }

    private static func progressValue(for plan: ExecutionPlan) -> Double {
        guard !plan.steps.isEmpty else { return 1 }
        let finished = plan.steps.filter { $0.status != .pending && $0.status != .inProgress }.count
        return Double(finished) / Double(plan.steps.count)
    }

    private static func previousResults(for plan: ExecutionPlan, upTo index: Int) -> [String] {
        guard index > 0 else { return [] }
        return plan.steps[0..<index].compactMap { step in
            guard step.status == .done || step.status == .failed, !step.result.isEmpty else {
                return nil
            }
            return "- \(step.title): \(String(step.result.prefix(300)))"
        }
    }

    private static func contextSummary(for plan: ExecutionPlan, upTo index: Int) -> String {
        let bullets = previousResults(for: plan, upTo: index)
        if bullets.isEmpty {
            return "This is the beginning of the task; no results yet."
        }
        return bullets.joined(separator: "\n")
    }
}
