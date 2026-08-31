import Foundation
import GRDB

public struct AgentSessionStopResult: Sendable {
    public let block: Block
    public let project: Project
}

public enum AgentSessionRecorder {
    /// Called from a SessionStart hook. Resolves (or creates) the project
    /// for `cwd` and records that this session started tracking it. A
    /// second start for the same session id is a no-op — hooks can fire
    /// more than once (e.g. `/clear`) and shouldn't reset the clock.
    public static func start(db: AppDatabase, sessionId: String, cwd: String, note: String?, now: Date = .init()) throws -> Project {
        let project = try Project.findOrCreate(byPath: cwd, db: db)

        try db.dbQueue.write { conn in
            if try AgentSessionTracking.fetchOne(conn, key: sessionId) == nil {
                let tracking = AgentSessionTracking(sessionId: sessionId, projectId: project.id, start: now, note: note)
                try tracking.insert(conn)
            }
        }

        return project
    }

    /// Called from a SessionEnd hook. Returns nil if this session was never
    /// started (e.g. the user opted out, or SessionStart failed) — the
    /// caller should treat that as a silent no-op, not an error.
    @discardableResult
    public static func stop(db: AppDatabase, sessionId: String, now: Date = .init()) throws -> AgentSessionStopResult? {
        try db.dbQueue.write { conn in
            guard let tracking = try AgentSessionTracking.fetchOne(conn, key: sessionId) else {
                return nil
            }
            guard let project = try Project.fetchOne(conn, key: tracking.projectId) else {
                try tracking.delete(conn)
                return nil
            }

            let block = Block(
                projectId: tracking.projectId,
                start: tracking.start,
                end: now,
                source: .claudeSession,
                note: tracking.note,
                isManual: false
            )
            try block.insert(conn)
            try tracking.delete(conn)

            return AgentSessionStopResult(block: block, project: project)
        }
    }

    /// Whether `sessionId` currently has a tracked timer. Lets SessionEnd
    /// skip its dialog entirely when the user opted out at SessionStart.
    public static func isTracking(db: AppDatabase, sessionId: String) throws -> Bool {
        try db.dbQueue.read { conn in
            try AgentSessionTracking.fetchOne(conn, key: sessionId) != nil
        }
    }
}
