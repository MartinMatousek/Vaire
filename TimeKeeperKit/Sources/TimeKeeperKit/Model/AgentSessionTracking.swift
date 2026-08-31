import Foundation
import GRDB

/// Bridges a Claude Code session (identified by its session_id) to an
/// in-progress TimeKeeper block. Written by SessionStart, read and deleted
/// by SessionEnd.
public struct AgentSessionTracking: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var sessionId: String
    public var projectId: UUID
    public var start: Date
    public var note: String?

    public init(sessionId: String, projectId: UUID, start: Date, note: String? = nil) {
        self.sessionId = sessionId
        self.projectId = projectId
        self.start = start
        self.note = note
    }

    public static let databaseTableName = "agentSessionTracking"
}
