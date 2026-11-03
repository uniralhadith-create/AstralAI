import Foundation

// MARK: - AgentPlanner

/// Turns a user goal into a minimal, effective execution plan.
enum AgentPlanner {

    static let systemPrompt = "You are the planning module of Astral, an autonomous AI agent app running on iOS. Given the user's goal and recent conversation, produce a minimal, effective execution plan. Respond with ONLY a valid JSON object, no markdown fences, in exactly this shape: {\"goal\": \"<restated goal in the user's language>\", \"steps\": [{\"title\": \"<short imperative title>\", \"detail\": \"<one-sentence instruction for the executor>\", \"parallelizable\": <true|false>, \"needsBrowser\": <true|false>}]}. Rules: Return 1 to 6 steps. If the request is simple chat or a single direct question needing no research, files or tools, return exactly one step titled \"Answer directly\". Mark independent research steps parallelizable=true so they can run simultaneously. Mark steps that need live web information needsBrowser=true. Never invent unnecessary steps."

    /// The JSON contract the planner model must produce.
    private struct PlanDTO: Decodable {
        struct StepDTO: Decodable {
            let title: String?
            let detail: String?
            let parallelizable: Bool?
            let needsBrowser: Bool?
        }

        let goal: String?
        let steps: [StepDTO]?
    }

    /// Builds a plan for the goal. Any planner failure falls back to a single
    /// "Answer directly" step so the conversation always continues.
    static func plan(
        goal: String,
        history: [ChatMessage],
        llm: LLMProviding,
        model: String?
    ) async throws -> ExecutionPlan {
        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user(plannerPrompt(goal: goal, history: history)),
        ]

        let dto: PlanDTO
        do {
            dto = try await llm.structured(messages: messages, type: PlanDTO.self, model: model)
        } catch {
            return fallbackPlan(goal: goal)
        }

        var steps: [PlanStep] = []
        let rawSteps = Array((dto.steps ?? []).prefix(8))
        for raw in rawSteps {
            let title = (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            steps.append(
                PlanStep(
                    index: steps.count,
                    title: title,
                    detail: (raw.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    status: .pending,
                    result: "",
                    parallelizable: raw.parallelizable ?? false,
                    needsBrowser: raw.needsBrowser ?? false))
        }

        guard !steps.isEmpty else {
            return fallbackPlan(goal: goal)
        }

        let planGoal: String
        if let restated = dto.goal?.trimmingCharacters(in: .whitespacesAndNewlines), !restated.isEmpty {
            planGoal = restated
        } else {
            planGoal = goal
        }
        return ExecutionPlan(goal: planGoal, summary: nil, steps: steps)
    }

    // MARK: Private

    private static func fallbackPlan(goal: String) -> ExecutionPlan {
        ExecutionPlan(
            goal: goal,
            steps: [
                PlanStep(
                    index: 0,
                    title: "Answer directly",
                    detail: goal,
                    status: .pending,
                    result: "",
                    parallelizable: false,
                    needsBrowser: false),
            ])
    }

    private static func plannerPrompt(goal: String, history: [ChatMessage]) -> String {
        var condensed: [String] = []
        for message in history.suffix(6) {
            let role: String
            switch message.role {
            case .system:
                continue
            case .user:
                role = "User"
            case .assistant:
                role = "Assistant"
            case .tool:
                role = "Tool result"
            }
            var content = message.content.replacingOccurrences(of: "\n", with: " ")
            if content.count > 200 {
                content = String(content.prefix(200)) + "..."
            }
            if content.isEmpty { continue }
            condensed.append("\(role): \(content)")
        }

        var prompt = ""
        if !condensed.isEmpty {
            prompt += "RECENT CONVERSATION:\n"
            prompt += condensed.joined(separator: "\n")
            prompt += "\n\n"
        }
        prompt += "GOAL: \(goal)"
        return prompt
    }
}
