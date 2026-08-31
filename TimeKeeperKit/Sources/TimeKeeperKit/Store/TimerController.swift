import Foundation
import Observation

@Observable
public final class TimerController {
    public private(set) var runningStarts: [UUID: Date] = [:]

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

    /// Starts a timer for `projectId`. Multiple projects can run at once —
    /// e.g. a long-running build or agent on one project while you're
    /// actively working another. Starting an already-running project is a
    /// no-op; its start time doesn't reset.
    public func start(projectId: UUID) {
        guard runningStarts[projectId] == nil else { return }
        runningStarts[projectId] = now()
    }

    @discardableResult
    public func stop(projectId: UUID) throws -> Block? {
        guard let start = runningStarts[projectId] else { return nil }

        let block = Block(
            projectId: projectId,
            start: start,
            end: now(),
            source: .manual,
            isManual: true
        )
        try db.dbQueue.write { conn in
            try block.insert(conn)
        }

        runningStarts.removeValue(forKey: projectId)
        return block
    }

    /// Elapsed seconds for `projectId`'s running block, or 0 if it isn't running.
    public func elapsed(projectId: UUID) -> TimeInterval {
        guard let start = runningStarts[projectId] else { return 0 }
        return now().timeIntervalSince(start)
    }
}
