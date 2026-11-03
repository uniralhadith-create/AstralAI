import Foundation
import SwiftUI
import Combine

/// The central composition root: builds and wires every subsystem and owns
/// deep-link routing, scene-phase handling and the share-extension inbox.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    // Subsystems
    let language: LocalizationManager
    let providerStore: ProviderStore
    let workspace: WorkspaceStore
    let browser: BrowserController
    let platform: PlatformServices
    let sessionStore: SessionStore
    let skillStore: SkillStore

    /// Section presented as a sheet over the always-visible chat (Apple's
    /// chat-first pattern — no tab bar). Deep links and intents set this.
    @Published var presentedSection: AppTab?

    /// The astra-os terminal, presented on its own glass sheet from the
    /// composer action panel and the Files toolbar.
    @Published var showTerminal = false

    /// V4.6.0: the Quick Launch overlay — the Action Button experience.
    /// Presented as a full-screen cover straight over the chat; the
    /// `astral://quick` deep link (and the Quick Task app intent) lands
    /// here with the task text pre-seeded.
    @Published var showQuickLaunch = false
    /// Seed text for the Quick Launch input (consumed on open).
    @Published var quickLaunchSeed: String?

    /// Presents a section sheet in a way that survives every dismissal
    /// race. State changes made while a `Menu` or sheet is animating
    /// closed can be silently dropped on iOS 17–26, so the request is
    /// re-fired idempotently: once after the dismissal settles, with a
    /// second and third attempt as insurance. Setting the same item
    /// while its sheet is already up is a no-op, so repeats are free.
    func presentSection(_ section: AppTab) {
        for delay in [0.35, 0.8, 1.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.presentedSection != section else { return }
                self.presentedSection = section
            }
        }
    }

    private init() {
        let language = LocalizationManager.shared
        self.language = language
        let providerStore = ProviderStore()
        self.providerStore = providerStore
        let platform = PlatformServices.shared
        self.platform = platform
        let workspace = WorkspaceStore.shared
        self.workspace = workspace
        let browser = BrowserController()
        self.browser = browser
        let skillStore = SkillStore.shared
        self.skillStore = skillStore
        let sessionStore = SessionStore(
            llm: providerStore.llm,
            browser: browser,
            workspace: workspace,
            system: platform)
        self.sessionStore = sessionStore

        BackgroundManager.shared.configure(store: sessionStore)
        sessionStore.loadPersisted()
        writeStatusSnapshot()
        observeSessions()
        observeSandbox()
    }

    // MARK: - Sandbox bridge

    /// Any shell command that may have touched workspace files refreshes
    /// the Files tab, so agent-created deliverables appear instantly.
    private func observeSandbox() {
        NotificationCenter.default.publisher(for: .sandboxDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.workspace.refresh()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session observation (status snapshot for widgets)

    private var cancellables = Set<AnyCancellable>()

    private func observeSessions() {
        let store = sessionStore
        // Polling-free: piggyback on objectWillChange of the active session.
        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.writeStatusSnapshot()
                _ = store
            }
            .store(in: &cancellables)
    }

    private func writeStatusSnapshot() {
        let snapshot: AgentStatusSnapshot
        if let session = sessionStore.activeSession, session.isBusy {
            snapshot = AgentStatusSnapshot(
                goal: session.title,
                phase: session.phase.rawValue,
                step: session.plan?.steps.first(where: { $0.status == .inProgress })?.title
                    ?? session.plan.map { _ in L("status.working", "Shared") }
                    ?? "",
                progress: session.progress,
                running: true,
                updatedAt: Date())
        } else {
            snapshot = AgentStatusSnapshot(
                goal: "",
                phase: SessionPhase.idle.rawValue,
                step: "",
                progress: 0,
                running: false,
                updatedAt: Date())
        }
        SharedStatusStore.write(snapshot)
    }

    // MARK: - Scene phase

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            BackgroundManager.shared.sceneDidEnterBackground()
            sessionStore.persistAll()
            BackgroundManager.shared.scheduleRefresh()
        case .active:
            BackgroundManager.shared.sceneDidBecomeActive()
            // V4.7.0: the inbox is re-checked on EVERY activation —
            // Action Button exchanges answered while the app was closed
            // (or backgrounded) appear the moment the user returns. The
            // import consumes its files, so repeated calls are free.
            importInboxIfNeeded()
            // A turn that was interrupted by an iOS suspension picks up
            // where it left off the moment the user returns — the
            // Manus-style "the agent kept working" experience.
            sessionStore.resumeInterruptedIfNeeded()
        default:
            break
        }
    }

    // MARK: - Deep links

    /// Handles `astral://` URLs: task, import, continue, chat.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "astral" else { return false }
        let host = url.host?.lowercased() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        switch host {
        case "task":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?
                .first(where: { $0.name == "text" })?
                .value?
                .removingPercentEncoding?
                .replacingOccurrences(of: "+", with: " ") ?? ""
            guard !text.isEmpty else { return false }
            presentedSection = nil
            startTask(text)
            return true
        case "quick":
            // V4.6.0 Action Button entry: land in the Quick Launch overlay
            // instead of the bare chat — with the text pre-seeded.
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?
                .first(where: { $0.name == "text" })?
                .value?
                .removingPercentEncoding?
                .replacingOccurrences(of: "+", with: " ") ?? ""
            presentedSection = nil
            quickLaunchSeed = text.isEmpty ? nil : text
            showTerminal = false
            showQuickLaunch = true
            return true
        case "import":
            presentedSection = nil
            importInboxIfNeeded()
            return true
        case "continue":
            presentedSection = nil
            resumeMostRecent()
            return true
        case "chat":
            presentedSection = nil
            return true
        default:
            return false
        }
    }

    private func startTask(_ text: String) {
        let session = sessionStore.activeSession ?? sessionStore.newSession()
        sessionStore.select(session)
        Task { @MainActor in
            session.send(text)
        }
    }

    private func resumeMostRecent() {
        guard let last = sessionStore.sessions.first else { return }
        sessionStore.select(last)
    }

    // MARK: - Share extension inbox

    /// Imports any content left by the share extension — or by the V4.7.0
    /// no-open Action Button flow — into the app:
    /// - `.astralmeta`: raw text (shared content or a queued quick task)
    ///   becomes a new agent task.
    /// - `.astralquick`: an exchange Astral already answered while the app
    ///   was closed becomes a completed session in the history — nothing
    ///   is re-run.
    func importInboxIfNeeded() {
        let inboxURL = SharedAppGroup.inboxURL
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return }

        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil) else { return }

        var collected: [String] = []
        var attachments: [URL] = []
        var quickExchanges: [(question: String, answer: String)] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard entry.lastPathComponent != ".DS_Store" else { continue }
            let fileExtension = entry.pathExtension.lowercased()
            if fileExtension == "astralmeta" {
                if let data = try? Data(contentsOf: entry),
                   let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    collected.append(text)
                }
                try? fileManager.removeItem(at: entry)
            } else if fileExtension == "astralquick",
                      let data = try? Data(contentsOf: entry),
                      let exchange = try? JSONDecoder().decode(QuickExchange.self, from: data) {
                quickExchanges.append((exchange.question, exchange.answer))
                try? fileManager.removeItem(at: entry)
            } else {
                attachments.append(entry)
            }
        }

        for attachment in attachments {
            let destination = workspace.rootURL.appendingPathComponent(attachment.lastPathComponent)
            try? fileManager.copyItem(at: attachment, to: destination)
            try? fileManager.removeItem(at: attachment)
            collected.append("Attached file: \(attachment.lastPathComponent)")
        }
        workspace.refresh()

        // Completed Action Button exchanges become finished sessions in
        // the history (newest conversation on top, never stealing focus).
        for exchange in quickExchanges {
            let session = sessionStore.newSession()
            session.importCompletedExchange(
                question: exchange.question,
                answer: exchange.answer)
        }

        guard !collected.isEmpty else { return }
        let prompt = """
        I shared the following content with you from another app:
        \(collected.joined(separator: "\n"))
        Analyze it and help me with it.
        """
        startTask(prompt)
    }
}
