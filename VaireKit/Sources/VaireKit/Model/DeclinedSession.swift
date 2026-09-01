import Foundation
import GRDB

/// Tombstone for a Claude Code session_id the user declined to log at the
/// SessionStart dialog. Checked by LiveImportCoordinator so its passive
/// transcript import — which otherwise runs for any hooksEnabled project
/// regardless of that answer — skips this session's file.
public struct DeclinedSession: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }

    public static let databaseTableName = "declinedSession"
}
