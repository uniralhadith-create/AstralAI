import Foundation
import UIKit
import BackgroundTasks
import WidgetKit

/// Central background-execution coordinator.
///
/// Responsibilities:
/// - BGTaskScheduler registration (app refresh + processing) — must happen
///   before `didFinishLaunching` returns, exactly once per process.
/// - Submitting future background windows (`scheduleRefresh()`).
/// - UIKit background-task bookkeeping for short windows that keep the agent
///   running right after the app leaves the foreground.
/// - Refreshing the shared status snapshot + widget timelines while the app
///   works in the background.
@MainActor
final class BackgroundManager {
    static let shared = BackgroundManager()

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist
    /// (declared by the frozen project.yml).
    private static let refreshIdentifier = "com.uniral.astralai.refresh"
    private static let processingIdentifier = "com.uniral.astralai.processing"

    /// Session store injected by AppEnvironment. A strong reference is fine —
    /// AppEnvironment owns the manager and both live for the whole process.
    private var store: SessionStore?

    /// Timestamp of the most recent transition to background. Agent sessions
    /// compare it against their turn-start time to distinguish "network is
    /// broken" from "iOS suspended the app mid-turn" so a suspension reads
    /// as an interruption (resumable) instead of a hard failure.
    private(set) var lastBackgroundedAt: Date?

    /// Timestamp of the most recent transition back to the foreground.
    private(set) var lastActivatedAt: Date?

    /// True when the app was backgrounded after `turnStartedAt` — i.e. the
    /// in-flight turn lived through a suspension window.
    func suspensionOverlaps(turnStartedAt: Date) -> Bool {
        guard let backgrounded = lastBackgroundedAt else { return false }
        return backgrounded > turnStartedAt
    }

    /// Records scene-phase transitions (called by AppEnvironment).
    func sceneDidEnterBackground() {
        lastBackgroundedAt = Date()
    }

    func sceneDidBecomeActive() {
        lastActivatedAt = Date()
    }

    /// BGTaskScheduler crashes when the same identifier is registered twice,
    /// so registration is guarded to be strictly idempotent.
    private var registered = false

    private init() {}

    // MARK: - Configuration

    /// Called by AppEnvironment once the session store has been built.
    func configure(store: SessionStore) {
        self.store = store
    }

    // MARK: - BGTaskScheduler registration

    /// Registers both background task handlers. Safe to call repeatedly;
    /// only the first call has any effect. Called from
    /// `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func register() {
        guard !registered else { return }
        registered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { [weak self] task in
            // Force-casting to the concrete task type is the accepted
            // pattern for identifier-specific registrations.
            self?.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleProcessing(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Scheduling

    /// Submits both background requests:
    /// - an app refresh no earlier than 15 minutes from now, and
    /// - a processing window no earlier than 30 minutes from now that needs
    ///   network connectivity but not external power.
    /// Submission errors (Low Power Mode, simulator, duplicate pending
    /// request) are logged and never crash the app.
    func scheduleRefresh() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(refresh)
        } catch {
            print("[BackgroundManager] app refresh submit failed: \(error)")
        }

        let processing = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(processing)
        } catch {
            print("[BackgroundManager] processing submit failed: \(error)")
        }
    }

    // MARK: - Task handlers

    /// App-refresh window: persist sessions, refresh the shared status
    /// snapshot + widget timelines, then re-arm the next window.
    private func handleAppRefresh(task: BGAppRefreshTask) {
        let completion = CompletionGuard()
        task.expirationHandler = {
            completion.run { task.setTaskCompleted(success: false) }
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion.run { task.setTaskCompleted(success: true) }
                return
            }
            // Persist in-flight session state so a cold relaunch restores it.
            self.store?.persistAll()
            // Refresh the widget pipeline (snapshot + timelines).
            self.refreshSharedStatus()
            WidgetCenter.shared.reloadAllTimelines()
            // Re-arm the next background window before finishing.
            self.scheduleRefresh()
            completion.run { task.setTaskCompleted(success: true) }
        }
    }

    /// Processing window: same core work as the refresh handler, plus a
    /// longer execution window description — this is the slot the system
    /// prefers for maintenance-grade work (longer runtime budget).
    private func handleProcessing(task: BGProcessingTask) {
        let completion = CompletionGuard()
        task.expirationHandler = {
            completion.run { task.setTaskCompleted(success: false) }
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion.run { task.setTaskCompleted(success: true) }
                return
            }
            // Persist every session, re-stamp the shared status snapshot and
            // reload all widget timelines while we hold the processing window.
            self.store?.persistAll()
            self.refreshSharedStatus()
            WidgetCenter.shared.reloadAllTimelines()
            self.scheduleRefresh()
            completion.run { task.setTaskCompleted(success: true) }
        }
    }

    /// Re-stamps the shared status snapshot (written by AppEnvironment) so
    /// widgets can tell the data was just refreshed.
    private func refreshSharedStatus() {
        if var snapshot = SharedStatusStore.read() {
            snapshot.updatedAt = Date()
            SharedStatusStore.write(snapshot)
        }
    }

    // MARK: - UIKit background tasks

    /// Begins a named UIKit background task (~30s window) so an agent run
    /// keeps executing right after the app is backgrounded. The expiration
    /// handler ends the task defensively if the caller forgets.
    @discardableResult
    func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        // Reference box so the escaping expiration handler can end exactly
        // this task without capturing a mutable local.
        final class Handle {
            var identifier: UIBackgroundTaskIdentifier = .invalid
        }
        let handle = Handle()
        handle.identifier = UIApplication.shared.beginBackgroundTask(withName: "astral.session") {
            // System background time ran out — end the task so iOS does not
            // terminate the app outright.
            let id = handle.identifier
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
        }
        return handle.identifier
    }

    /// Ends a previously begun UIKit background task. Passing `.invalid`
    /// is a harmless no-op.
    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Helpers

    /// Guarantees a BGTask completion closure runs exactly once, no matter
    /// whether the work finishes first or the expiration handler fires first.
    private final class CompletionGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ work: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            work()
        }
    }
}
