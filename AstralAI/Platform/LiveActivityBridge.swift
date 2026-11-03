import Foundation
import ActivityKit

/// Owns the single Live Activity presented while the agent works.
/// The Lock Screen / Dynamic Island UI itself lives in the Widgets
/// extension (`AgentLiveActivityWidget`) and renders `AgentActivityAttributes`.
@MainActor
final class LiveActivityBridge {
    static let shared = LiveActivityBridge()

    private var activity: Activity<AgentActivityAttributes>?

    private init() {}

    /// Whether a Live Activity is currently presented.
    var isActive: Bool { activity != nil }

    // MARK: - Lifecycle

    /// Starts a Live Activity for the given goal. Silently does nothing when
    /// Live Activities are disabled (Lock Screen setting, Low Power Mode, or
    /// the user asked the system to kill previous activities).
    func startActivity(goal: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityBridge] Live Activities are not enabled")
            return
        }

        // Retire any stale activity from a previous run before requesting a
        // new one — only one agent Live Activity is presented at a time.
        if let previous = activity {
            activity = nil
            Task {
                await previous.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = AgentActivityAttributes(goal: goal, startedAt: Date())
        let state = AgentActivityAttributes.ContentState(
            step: L("la.starting", "Platform"),
            progress: 0,
            status: "running")

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil))
        } catch {
            print("[LiveActivityBridge] request failed: \(error)")
        }
    }

    /// Pushes a new step + overall progress (0...1) to the presented activity.
    func update(step: String, progress: Double) {
        guard let activity else { return }
        let state = AgentActivityAttributes.ContentState(
            step: step,
            progress: min(max(progress, 0), 1),
            status: "running")
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Ends the presented activity with a final state. The activity stays on
    /// the Lock Screen for 8 more seconds so the user can see the result.
    func end(success: Bool) {
        guard let current = activity else { return }
        let state = AgentActivityAttributes.ContentState(
            step: success ? L("la.completed", "Platform") : L("la.stopped", "Platform"),
            progress: 1,
            status: success ? "done" : "failed")
        Task {
            await current.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(8)))
            self.activity = nil
        }
    }
}
