import Foundation
import GRDB

/// One row in the git-import review sheet: an editable candidate the user
/// can accept, retime, rename, or discard before anything is written.
public struct GitImportCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var start: Date
    public var end: Date
    public var note: String
    public var included: Bool

    public init(id: UUID = UUID(), start: Date, end: Date, note: String, included: Bool = true) {
        self.id = id
        self.start = start
        self.end = end
        self.note = note
        self.included = included
    }
}

public enum GitImportReviewer {
    /// Turns raw commits into review candidates scoped to `weekStart`...
    /// `weekStart + 7 days` — the import always operates on one displayed
    /// week rather than a fixed 90-day window, so re-running it is a
    /// deliberate, bounded action instead of silently rewriting months of
    /// history every time.
    public static func candidates(from commits: [GitCommit], weekStart: Date) -> [GitImportCandidate] {
        let weekEnd = weekStart.addingTimeInterval(7 * 86400)
        let inWeek = commits.filter { $0.date >= weekStart && $0.date < weekEnd }
        return GitImporter.candidatesWithCommits(from: inWeek).map {
            GitImportCandidate(start: $0.block.start, end: $0.block.end, note: $0.suggestedNote)
        }
    }

    /// Writes the accepted (non-discarded) candidates as manual blocks —
    /// manual because the user has just individually reviewed each one, so
    /// they're corrections by definition and should never be silently
    /// overwritten by a later reimport, same as any other manual edit.
    ///
    /// If `replacingExisting` is true, first deletes this project's
    /// existing `.gitCommit`-sourced blocks that overlap the review week
    /// (never touches Claude-session or other-sourced blocks, unlike
    /// ReimportGuard.reconcile which wipes every non-manual block in
    /// range regardless of source) — lets re-running the import for a
    /// week you already imported update those blocks instead of
    /// duplicating them.
    public static func commit(
        db: AppDatabase,
        projectId: UUID,
        candidates: [GitImportCandidate],
        weekStart: Date,
        replacingExisting: Bool
    ) throws {
        let accepted = candidates.filter(\.included)
        guard !accepted.isEmpty || replacingExisting else { return }

        let weekEnd = weekStart.addingTimeInterval(7 * 86400)

        try db.dbQueue.write { conn in
            if replacingExisting {
                try Block
                    .filter(Column("projectId") == projectId)
                    .filter(Column("source") == Source.gitCommit.rawValue)
                    .filter(Column("start") < weekEnd && Column("end") > weekStart)
                    .deleteAll(conn)
            }

            for candidate in accepted {
                let block = Block(
                    projectId: projectId,
                    start: candidate.start,
                    end: candidate.end,
                    source: .gitCommit,
                    note: candidate.note.isEmpty ? nil : candidate.note,
                    isManual: true
                )
                try block.insert(conn)
            }
        }
    }
}
