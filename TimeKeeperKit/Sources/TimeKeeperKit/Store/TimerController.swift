import Foundation
import Observation

@Observable
public final class TimerController {
    public private(set) var isRunning: Bool = false
    public private(set) var runningProjectId: UUID?
    private var runningStart: Date?

    private let db: AppDatabase
    private let now: () -> Date

    public init(db: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.db = db
        self.now = now
    }

    public func start(projectId: UUID) {
        guard !isRunning else { return }
        runningProjectId = projectId
        runningStart = now()
        isRunning = true
    }

    @discardableResult
    public func stop() throws -> Block? {
        guard isRunning, let projectId = runningProjectId, let start = runningStart else { return nil }

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

        isRunning = false
        runningProjectId = nil
        runningStart = nil
        return block
    }

    /// Elapsed seconds of the current running block, or 0 if nothing is running.
    public func elapsed() -> TimeInterval {
        guard let start = runningStart else { return 0 }
        return now().timeIntervalSince(start)
    }
}
