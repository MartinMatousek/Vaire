import Foundation
import GRDB

public enum ReimportGuard {
    /// Persists freshly-ingested candidate blocks for a project without
    /// touching any block the user has manually corrected. Manual edits
    /// (isManual == true) survive every reimport; only auto-sourced blocks
    /// are replaced wholesale for the affected time range.
    ///
    /// Strategy: delete existing non-manual blocks that overlap the
    /// candidates' time range for this project, then insert the new ones.
    /// Manual blocks in that same range are left untouched, so a corrected
    /// block never gets silently overwritten by the next import.
    public static func reconcile(db: AppDatabase, projectId: UUID, candidates: [MergedBlock]) throws {
        guard !candidates.isEmpty else { return }

        let rangeStart = candidates.map(\.start).min()!
        let rangeEnd = candidates.map(\.end).max()!

        try db.dbQueue.write { conn in
            try Block
                .filter(Column("projectId") == projectId)
                .filter(Column("isManual") == false)
                .filter(Column("start") < rangeEnd && Column("end") > rangeStart)
                .deleteAll(conn)

            for candidate in candidates {
                let block = Block(
                    projectId: candidate.projectId,
                    start: candidate.start,
                    end: candidate.end,
                    source: candidate.sources.first ?? .claudeSession,
                    isManual: false
                )
                try block.insert(conn)
            }
        }
    }
}
