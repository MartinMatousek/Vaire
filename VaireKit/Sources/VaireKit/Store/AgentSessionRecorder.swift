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
                isManual: false,
                estimatedHoursWithoutAI: tracking.estimatedHoursWithoutAI
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

    /// Finds an in-progress tracking row for `cwd`, if any. `/clear` and
    /// `/compact` mint a brand new session_id on SessionStart, so a running
    /// timer from before the reset can't be found by session_id anymore —
    /// this is how SessionStart offers "continue the running task" instead
    /// of starting a second, overlapping timer for the same work.
    public static func findActiveTracking(db: AppDatabase, cwd: String) throws -> AgentSessionTracking? {
        try db.dbQueue.read { conn in
            guard let project = try Project.filter(Column("path") == cwd).fetchOne(conn) else {
                return nil
            }
            return try AgentSessionTracking
                .filter(Column("projectId") == project.id)
                .fetchOne(conn)
        }
    }

    /// Re-keys an existing tracking row to `newSessionId`, preserving its
    /// original start time and note. Used when the user chooses to
    /// continue a running task across a /clear or /compact reset.
    public static func continueTracking(db: AppDatabase, oldSessionId: String, newSessionId: String) throws {
        guard oldSessionId != newSessionId else { return }
        try db.dbQueue.write { conn in
            guard let tracking = try AgentSessionTracking.fetchOne(conn, key: oldSessionId) else {
                return
            }
            try tracking.delete(conn)
            let moved = AgentSessionTracking(
                sessionId: newSessionId,
                projectId: tracking.projectId,
                start: tracking.start,
                note: tracking.note,
                estimatedHoursWithoutAI: tracking.estimatedHoursWithoutAI
            )
            try moved.insert(conn)
        }
    }

    /// Records Claude's own estimate of how long this task would normally
    /// take without AI help, so SessionEnd can show the "added value" vs.
    /// the actual logged time. Called by the agent itself (via
    /// `vaire set-estimate`) before ending the session. A no-op if
    /// the session isn't being tracked (e.g. the user opted out).
    public static func setEstimate(db: AppDatabase, sessionId: String, hours: Double) throws {
        try db.dbQueue.write { conn in
            guard var tracking = try AgentSessionTracking.fetchOne(conn, key: sessionId) else {
                return
            }
            tracking.estimatedHoursWithoutAI = hours
            try tracking.update(conn)
        }
    }

    /// Whether `sessionId` has both an active tracking row AND a recorded
    /// estimate. False if either the session isn't tracking or is tracking
    /// without an estimate yet — callers distinguish those cases via
    /// `isTracking` separately when it matters.
    public static func hasEstimate(db: AppDatabase, sessionId: String) throws -> Bool {
        try db.dbQueue.read { conn in
            guard let tracking = try AgentSessionTracking.fetchOne(conn, key: sessionId) else {
                return false
            }
            return tracking.estimatedHoursWithoutAI != nil
        }
    }

    /// All in-progress Claude session timers across every project, oldest
    /// first. Used by the UI to show live/running work alongside completed
    /// blocks — these rows never appear in the `block` table until stopped,
    /// so callers that only read `Block` never see them.
    public static func allActiveTrackings(db: AppDatabase) throws -> [AgentSessionTracking] {
        try db.dbQueue.read { conn in
            try AgentSessionTracking.order(Column("start")).fetchAll(conn)
        }
    }

    /// Records that the user declined to log `sessionId` at the
    /// SessionStart dialog, so LiveImportCoordinator's passive transcript
    /// import skips this session's file instead of logging it anyway.
    public static func declineSession(db: AppDatabase, sessionId: String) throws {
        try db.dbQueue.write { conn in
            try DeclinedSession(sessionId: sessionId).insert(conn, onConflict: .ignore)
        }
    }

    /// Whether `sessionId` was declined at the SessionStart dialog.
    public static func isDeclined(db: AppDatabase, sessionId: String) throws -> Bool {
        try db.dbQueue.read { conn in
            try DeclinedSession.fetchOne(conn, key: sessionId) != nil
        }
    }
}
