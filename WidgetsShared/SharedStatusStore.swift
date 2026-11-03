import Foundation

/// A compact snapshot of the agent's state, written by the main app into the
/// app group container and read by the home-screen widget timeline.
public struct AgentStatusSnapshot: Codable, Equatable {
    public var goal: String
    public var phase: String
    public var step: String
    public var progress: Double
    public var running: Bool
    public var updatedAt: Date

    public init(
        goal: String,
        phase: String,
        step: String,
        progress: Double,
        running: Bool,
        updatedAt: Date = Date()
    ) {
        self.goal = goal
        self.phase = phase
        self.step = step
        self.progress = progress
        self.running = running
        self.updatedAt = updatedAt
    }
}

/// Thread-safe read/write of the status snapshot file.
public enum SharedStatusStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func write(_ snapshot: AgentStatusSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: SharedAppGroup.statusFileURL, options: .atomic)
    }

    public static func read() -> AgentStatusSnapshot? {
        guard let data = try? Data(contentsOf: SharedAppGroup.statusFileURL) else { return nil }
        return try? decoder.decode(AgentStatusSnapshot.self, from: data)
    }
}
