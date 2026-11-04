import Foundation

// MARK: - SubAgentTracker

/// Aggregates live status for a batch of parallel sub-agents and reports a
/// fresh copy of the whole status list on every change.
@MainActor
private final class SubAgentTracker {

    private var statuses: [SubAgentStatus] = []
    private let report: ([SubAgentStatus]) -> Void

    init(report: @escaping ([SubAgentStatus]) -> Void) {
        self.report = report
    }

    func markRunning(stepID: UUID, name: String, role: String) {
        statuses.append(
            SubAgentStatus(
                id: stepID,
                name: name,
                role: role,
                state: .running,
                currentAction: L("agent.thinking", "Agent"),
                progress: 0))
        emit()
    }

    func setAction(stepID: UUID, action: String) {
        guard let index = statuses.firstIndex(where: { $0.id == stepID }) else { return }
        statuses[index].currentAction = action
        emit()
    }

    func setProgress(stepID: UUID, progress: Double) {
        guard let index = statuses.firstIndex(where: { $0.id == stepID }) else { return }
        statuses[index].progress = min(max(progress, 0), 1)
        emit()
    }

    func markFinished(stepID: UUID, success: Bool) {
        guard let index = statuses.firstIndex(where: { $0.id == stepID }) else { return }
        statuses[index].state = success ? .finished : .failed
        statuses[index].progress = 1
        statuses[index].currentAction = ""
        emit()
    }

    func markRemainingFailed() {
        var changed = false
        for index in statuses.indices where statuses[index].state == .running {
            statuses[index].state = .failed
            statuses[index].currentAction = ""
            statuses[index].progress = 1
            changed = true
        }
        if changed { emit() }
    }

    private func emit() {
        report(statuses)
    }
}

// MARK: - SubAgentRunner

/// Runs independent plan steps as parallel sub-agents. All work executes on
/// the main actor; interleaving at await points gives real I/O parallelism
/// while every piece of state stays main-isolated.
@MainActor
enum SubAgentRunner {

    private static let agentNames = [
        "Research Agent",
        "Data Agent",
        "Writer Agent",
        "Scout Agent",
    ]
    private static let maxRounds = 30

    static func run(
        steps: [PlanStep],
        goal: String,
        contextSummary: String,
        llm: LLMProviding,
        toolRegistry: ToolRegistry,
        system: SystemServicing?,
        model: String?,
        sessionID: UUID,
        report: @escaping ([SubAgentStatus]) -> Void
    ) async -> [PlanStep] {
        let tracker = SubAgentTracker(report: report)
        var updatedByID: [UUID: PlanStep] = [:]

        await withTaskGroup(of: (PlanStep, String)?.self) { group in
            for (position, step) in steps.enumerated() {
                let name = agentNames[position % agentNames.count]
                tracker.markRunning(stepID: step.id, name: name, role: step.title)
                group.addTask { [llm, toolRegistry] in
                    if Task.isCancelled { return nil }
                    return await runSubAgent(
                        step: step,
                        name: name,
                        goal: goal,
                        contextSummary: contextSummary,
                        llm: llm,
                        toolRegistry: toolRegistry,
                        model: model,
                        sessionID: sessionID,
                        tracker: tracker)
                }
            }

            for await childResult in group {
                if let (updatedStep, _) = childResult {
                    updatedByID[updatedStep.id] = updatedStep
                    tracker.markFinished(
                        stepID: updatedStep.id,
                        success: updatedStep.status == .done)
                }
            }
        }

        tracker.markRemainingFailed()

        return steps.map { original in
            if let updated = updatedByID[original.id] {
                return updated
            }
            var cancelled = original
            cancelled.status = .failed
            cancelled.result = "Cancelled before completion."
            return cancelled
        }
    }

    // MARK: Single sub-agent

    private static func runSubAgent(
        step: PlanStep,
        name: String,
        goal: String,
        contextSummary: String,
        llm: LLMProviding,
        toolRegistry: ToolRegistry,
        model: String?,
        sessionID: UUID,
        tracker: SubAgentTracker
    ) async -> (PlanStep, String)? {
        var current = step
        current.status = .inProgress
        current.result = ""

        let systemPrompt = "You are \(name), a parallel sub-agent of Astral AI executing one independent step: \"\(step.title)\". DETAIL: \(step.detail). Use the available tools to complete exactly this step, staying within its scope. End your final reply with a line starting SUBAGENT_RESULT: followed by a concise summary of what you found or produced."
        let userPrompt = "OVERALL GOAL: \(goal)\nCONTEXT: \(contextSummary)\n\nComplete your step now, and end with SUBAGENT_RESULT: followed by your summary."

        var messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user(userPrompt),
        ]
        let specs = toolRegistry.specs()
        let sessionInfo = SessionInfo(sessionID: sessionID, goal: goal)
        var lastText = ""

        for round in 0..<maxRounds {
            if Task.isCancelled {
                current.status = .failed
                current.result = "Cancelled before completion."
                return (current, name)
            }
            tracker.setAction(stepID: step.id, action: L("agent.thinking", "Agent"))
            tracker.setProgress(stepID: step.id, progress: Double(round) / Double(maxRounds))

            var accumulated = ""
            var pendingCalls: [ToolCall] = []
            do {
                for try await event in llm.streamChat(
                    messages: messages, tools: specs, model: model) {
                    switch event {
                    case .textDelta(let delta):
                        accumulated += delta
                    case .toolCalls(let calls):
                        pendingCalls = calls
                    case .toolsDropped:
                        break
                    case .finished:
                        break
                    }
                }
            } catch {
                current.status = .failed
                current.result = "Sub-agent error: \(error.localizedDescription)"
                return (current, name)
            }
            lastText = accumulated

            if !pendingCalls.isEmpty {
                tracker.setAction(stepID: step.id, action: L("agent.runningTools", "Agent"))
                messages.append(
                    ChatMessage(role: .assistant, content: accumulated, toolCalls: pendingCalls))
                for call in pendingCalls {
                    let result = await toolRegistry.execute(
                        call: call, session: sessionInfo, isSubAgent: true)
                    var deliveredImages: [MessageImage]?
                    if call.name == BrowserScreenshotTool.toolName,
                       let capture = ScreenCaptureDelivery.take(callID: call.id) {
                        deliveredImages = [capture]
                    }
                    let deliveredVideos = VideoDelivery.take(callID: call.id)
                    messages.append(
                        ChatMessage(
                            role: .tool,
                            content: result.content,
                            toolCallId: call.id,
                            name: call.name,
                            images: deliveredImages,
                            videos: deliveredVideos))
                }
                continue
            }

            if let range = lastText.range(of: "SUBAGENT_RESULT:", options: .caseInsensitive) {
                let summary = String(lastText[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                current.result = summary.isEmpty ? lastText : summary
                current.status = .done
                return (current, name)
            }

            if round == maxRounds - 1 {
                let trimmed = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    current.status = .failed
                    current.result = "The sub-agent produced no output."
                } else {
                    current.status = .done
                    current.result = trimmed
                }
                return (current, name)
            }

            messages.append(ChatMessage.assistant(lastText))
            messages.append(
                ChatMessage.user("Continue. Finish your step and end with SUBAGENT_RESULT: followed by a concise summary."))
        }

        let trimmed = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        current.result = trimmed.isEmpty ? "The sub-agent did not produce a result." : trimmed
        current.status = trimmed.isEmpty ? .failed : .done
        return (current, name)
    }
}
