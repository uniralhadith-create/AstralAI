import Foundation
import AppIntents
import UIKit

// MARK: - Ask Astral

/// Shortcuts / Spotlight intent: hand a natural-language task to the agent.
/// The app itself is opened through the `astral://task` deep link, which
/// AppEnvironment turns into a new agent session.
struct AskAstralIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Astral"
    static var description = IntentDescription(
        "Send a task to your Astral AI agent and it will plan and execute it.")

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Astral to \(\.$task)")
    }

    @Parameter(title: "Task")
    var task: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let encoded = task.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "astral://task?text=\(encoded)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return .result(dialog: "\(L("intent.opening", "Platform"))")
    }
}

// MARK: - Continue last task

/// Reopens the app and focuses the most recent agent session.
struct ContinueLastTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Last Task"
    static var description = IntentDescription(
        "Reopen Astral AI and jump back into your most recent agent session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let url = URL(string: "astral://continue") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return .result(dialog: "\(L("intent.opening", "Platform"))")
    }
}

// MARK: - Quick Task (V4.7.0 — the Action Button that never opens the app)

/// The Action Button experience, rebuilt the way it should work: pressing
/// the Action Button (iPhone 15 Pro and later) shows the task field over
/// whatever is on screen — and Astral answers RIGHT THERE. The app is
/// never launched: `openAppWhenRun` is false, the answer comes back as
/// the intent's own dialog over the current screen, a copy lands in the
/// notification center, and the full exchange is queued in the shared
/// inbox so it appears inside the app's history the next time the user
/// opens it.
///
/// If the model cannot answer within the time budget (slow provider, no
/// key, network trouble) the task is NOT lost: it is queued as a pending
/// task in the inbox, and the app runs it as a full agent session the
/// next time it is opened.
struct QuickTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Task"
    static var description = IntentDescription(
        "Give Astral a task instantly — the answer appears right over what you're doing. The app never opens.")

    static var parameterSummary: some ParameterSummary {
        Summary("Quick task: \(\.$task)")
    }

    /// THE V4.7.0 rule: the Action Button must not launch the app.
    static var openAppWhenRun: Bool = false

    /// Time budget for the in-place answer. Beyond this the task is
    /// handed to the app instead (the overlay must stay snappy).
    private static let answerBudget: TimeInterval = 28

    @Parameter(title: "Task")
    var task: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: L("intent.quickEmpty", "Platform")))
        }

        // Build the one-shot client from the user's saved provider setup.
        // (A fresh ProviderStore reads the same persisted config the app
        // uses — no UI, no app launch.)
        let store = ProviderStore()
        guard store.active != nil else {
            QuickInbox.queuePendingTask(text)
            return .result(dialog: IntentDialog(stringLiteral: L("intent.noProvider", "Platform")))
        }
        let llm = store.llm

        let systemPrompt =
            "You are Astral, a fast assistant answering from the iPhone Action Button. "
            + "Reply directly and completely in the user's own language (Arabic in → Arabic out, "
            + "English in → English out). Be concise and useful — a few short paragraphs at most. "
            + "You have no tools in this mode; if the task truly needs the full agent (files, "
            + "browser, code execution), answer briefly and tell the user to open the Astral app "
            + "for the full run."

        do {
            let answer = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await llm.complete(
                        messages: [
                            ChatMessage.system(systemPrompt),
                            ChatMessage.user(text),
                        ],
                        model: nil)
                }
                group.addTask {
                    try await Task.sleep(
                        nanoseconds: UInt64(Self.answerBudget * 1_000_000_000))
                    throw QuickAnswerTimeout()
                }
                defer { group.cancelAll() }
                return try await group.next() ?? ""
            }

            let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAnswer.isEmpty else { throw QuickAnswerTimeout() }

            // 1. Keep the exchange: the app's history picks it up later.
            QuickInbox.queueCompletedExchange(question: text, answer: trimmedAnswer)

            // 2. A notification copy the user can reopen any time.
            NotificationBridge.shared.notify(
                title: L("intent.notificationTitle", "Platform"),
                body: trimmedAnswer)

            // 3. The answer itself, right over the current screen.
            let capped = trimmedAnswer.count > 1400
                ? String(trimmedAnswer.prefix(1400)) + "…"
                : trimmedAnswer
            return .result(dialog: IntentDialog(stringLiteral: capped))
        } catch {
            // Could not answer in place — the task is queued and the full
            // agent will run it the moment the app is opened.
            QuickInbox.queuePendingTask(text)
            NotificationBridge.shared.notify(
                title: L("intent.notificationTitle", "Platform"),
                body: L("intent.quickSaved", "Platform"))
            return .result(dialog: IntentDialog(stringLiteral: L("intent.quickSaved", "Platform")))
        }
    }
}

/// Raised when the in-place answer does not arrive within the budget.
private struct QuickAnswerTimeout: Error {}

// MARK: - Quick inbox (V4.7.0)

/// One answered Action Button exchange, persisted to the shared inbox and
/// imported into the app's history as a completed session.
struct QuickExchange: Codable {
    let question: String
    let answer: String
    let date: Date
}

/// The bridge between the no-open Action Button flow and the app.
/// Files land in the shared app-group inbox:
/// - `.astralmeta` — a pending task the app will RUN as a full agent
///   session on next open (the same mechanism the share extension uses).
/// - `.astralquick` — an already-answered quick exchange, imported into
///   the history as a completed session (user question + assistant
///   answer, nothing re-run).
enum QuickInbox {
    static func queuePendingTask(_ text: String) {
        let data = Data(text.utf8)
        write(data, extension: "astralmeta")
    }

    static func queueCompletedExchange(question: String, answer: String) {
        let exchange = QuickExchange(question: question, answer: answer, date: Date())
        guard let data = try? JSONEncoder().encode(exchange) else { return }
        write(data, extension: "astralquick")
    }

    private static func write(_ data: Data, extension fileExtension: String) {
        SharedAppGroup.ensureInboxExists()
        let name = "quick-\(UUID().uuidString.lowercased()).\(fileExtension)"
        let url = SharedAppGroup.inboxURL.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - App Shortcuts

/// Surfaces the zero-setup shortcuts in the Shortcuts app, Spotlight and
/// the Action button. Picking "Quick Task" in Settings > Action Button is
/// enough — the user never has to build anything in the Shortcuts app.
struct AstralShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickTaskIntent(),
            phrases: [
                "Quick task in \(.applicationName)",
                "\(.applicationName) quick task",
            ],
            shortTitle: "Quick Task",
            systemImageName: "wand.and.stars")
        AppShortcut(
            intent: AskAstralIntent(),
            phrases: [
                "Ask \(.applicationName) to run a task",
                "\(.applicationName) run a task",
            ],
            shortTitle: "Ask Astral",
            systemImageName: "sparkles")
        AppShortcut(
            intent: ContinueLastTaskIntent(),
            phrases: [
                "Continue my \(.applicationName) task",
            ],
            shortTitle: "Continue",
            systemImageName: "clock.arrow.circlepath")
    }
}
