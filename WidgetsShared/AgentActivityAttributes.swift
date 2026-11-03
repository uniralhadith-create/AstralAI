import Foundation
import ActivityKit

/// Live Activity attributes describing one agent run — shown on the Lock
/// Screen and in the Dynamic Island while the agent works in the background.
public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The step currently being executed.
        public var step: String
        /// Overall progress, 0...1.
        public var progress: Double
        /// running | done | failed
        public var status: String

        public init(step: String, progress: Double, status: String) {
            self.step = step
            self.progress = progress
            self.status = status
        }
    }

    /// The high-level goal of the session.
    public var goal: String
    public var startedAt: Date

    public init(goal: String, startedAt: Date = Date()) {
        self.goal = goal
        self.startedAt = startedAt
    }
}
