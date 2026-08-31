import Foundation
import Observation

@Observable
public final class TimerController {
    public private(set) var runningStarts: [UUID: Date] = [:]
    public private(set) var runningNotes: [UUID: String] = [:]
    public private(set) var runningEstimates: [UUID: Double] = [:]

    private let db: AppDatabase
    private let now: () -> Date

    public init(db: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.db = db
        self.now = now
    }

    public func isRunning(projectId: UUID) -> Bool {
        runningStarts[projectId] != nil
    }

    public var hasAnyRunning: Bool {
        !runningStarts.isEmpty
    }

    /// Starts a timer for `projectId`, optionally with a note captured up
    /// front (e.g. "so I don't forget") and an upfront effort estimate (in
    /// hours) to compare against the actual logged time once stopped.
    /// Multiple projects can run at once — e.g. a long-running build or
    /// agent on one project while you're actively working another.
    /// Starting an already-running project is a no-op; its start time,
    /// note, and estimate don't reset.
    public func start(projectId: UUID, note: String? = nil, estimatedHours: Double? = nil) {
        guard runningStarts[projectId] == nil else { return }
        runningStarts[projectId] = now()
        if let note, !note.isEmpty {
            runningNotes[projectId] = note
        }
        if let estimatedHours, estimatedHours > 0 {
            runningEstimates[projectId] = estimatedHours
        }
    }

    @discardableResult
    public func stop(projectId: UUID) throws -> Block? {
        guard let start = runningStarts[projectId] else { return nil }

        let block = Block(
            projectId: projectId,
            start: start,
            end: now(),
            source: .manual,
            note: runningNotes[projectId],
            isManual: true,
            estimatedHoursWithoutAI: runningEstimates[projectId]
        )
        try db.dbQueue.write { conn in
            try block.insert(conn)
        }

        runningStarts.removeValue(forKey: projectId)
        runningNotes.removeValue(forKey: projectId)
        runningEstimates.removeValue(forKey: projectId)
        return block
    }

    /// Elapsed seconds for `projectId`'s running block, or 0 if it isn't running.
    public func elapsed(projectId: UUID) -> TimeInterval {
        guard let start = runningStarts[projectId] else { return 0 }
        return now().timeIntervalSince(start)
    }

    /// Restarts a timer at a specific `start` time rather than now — used
    /// when the user stops a timer, then decides they cut it off too early
    /// and wants to pick up where the (now-deleted) block left off.
    public func resume(projectId: UUID, from start: Date, note: String?, estimatedHours: Double? = nil) {
        runningStarts[projectId] = start
        if let note, !note.isEmpty {
            runningNotes[projectId] = note
        }
        if let estimatedHours, estimatedHours > 0 {
            runningEstimates[projectId] = estimatedHours
        }
    }
}
