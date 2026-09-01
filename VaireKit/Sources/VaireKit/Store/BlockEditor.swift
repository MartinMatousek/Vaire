import Foundation
import GRDB

public enum BlockEditorError: Error {
    case blockNotFound
    case blocksNotAdjacent
    case splitTimeOutOfRange
    case invalidTimeRange
}

public enum BlockEditor {
    /// Moves a block by a whole number of days, preserving its duration and
    /// time-of-day. Used for drag & drop between days in the weekly view.
    /// Marks the block as manual so a later reimport of auto-sources won't
    /// overwrite the correction.
    public static func move(db: AppDatabase, blockId: UUID, byDays days: Int) throws -> Block {
        try db.dbQueue.write { conn in
            guard var block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            let offset = TimeInterval(days) * 86400
            block.start = block.start.addingTimeInterval(offset)
            block.end = block.end.addingTimeInterval(offset)
            block.isManual = true
            try block.update(conn)
            return block
        }
    }

    /// Splits a block into two at `splitPoint`. Both halves inherit the
    /// original's project and source, and are marked manual.
    @discardableResult
    public static func split(db: AppDatabase, blockId: UUID, at splitPoint: Date) throws -> (Block, Block) {
        try db.dbQueue.write { conn in
            guard let original = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            guard splitPoint > original.start, splitPoint < original.end else {
                throw BlockEditorError.splitTimeOutOfRange
            }

            var first = original
            first.end = splitPoint
            first.isManual = true

            let second = Block(
                projectId: original.projectId,
                start: splitPoint,
                end: original.end,
                source: original.source,
                note: original.note,
                isManual: true
            )

            try first.update(conn)
            try second.insert(conn)

            return (first, second)
        }
    }

    /// Merges two or more blocks into one spanning their combined range.
    /// All blocks must belong to the same project; the earliest start and
    /// latest end are kept. Extra blocks are deleted.
    @discardableResult
    public static func merge(db: AppDatabase, blockIds: [UUID]) throws -> Block {
        try db.dbQueue.write { conn in
            let blocks = try blockIds.compactMap { id in
                try Block.fetchOne(conn, key: id)
            }
            guard blocks.count == blockIds.count else { throw BlockEditorError.blockNotFound }
            guard let projectId = blocks.first?.projectId, blocks.allSatisfy({ $0.projectId == projectId }) else {
                throw BlockEditorError.blocksNotAdjacent
            }

            var survivor = blocks.min { $0.start < $1.start }!
            survivor.start = blocks.map(\.start).min()!
            survivor.end = blocks.map(\.end).max()!
            survivor.isManual = true
            try survivor.update(conn)

            for block in blocks where block.id != survivor.id {
                try block.delete(conn)
            }

            return survivor
        }
    }

    public static func setProject(db: AppDatabase, blockId: UUID, projectId: UUID) throws -> Block {
        try db.dbQueue.write { conn in
            guard var block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            block.projectId = projectId
            block.isManual = true
            try block.update(conn)
            return block
        }
    }

    public static func setNote(db: AppDatabase, blockId: UUID, note: String?) throws -> Block {
        try db.dbQueue.write { conn in
            guard var block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            block.note = (note?.isEmpty ?? true) ? nil : note
            try block.update(conn)
            return block
        }
    }

    /// Overwrites a block's start/end, e.g. rounding a just-stopped timer to
    /// the nearest quarter hour. Marks the block manual so reimport won't
    /// clobber the correction.
    public static func setTimes(db: AppDatabase, blockId: UUID, start: Date, end: Date) throws -> Block {
        guard start < end else { throw BlockEditorError.invalidTimeRange }
        return try db.dbQueue.write { conn in
            guard var block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            block.start = start
            block.end = end
            block.isManual = true
            try block.update(conn)
            return block
        }
    }

    /// Deletes a block. For an auto-sourced block (isManual == false) this
    /// also records a tombstone of its time range — otherwise the next
    /// live reimport of the same source transcript would re-derive and
    /// re-insert the exact same block, making the delete not stick.
    public static func delete(db: AppDatabase, blockId: UUID) throws {
        try db.dbQueue.write { conn in
            guard let block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            if !block.isManual {
                try DeletedBlockRange(projectId: block.projectId, start: block.start, end: block.end).insert(conn)
            }
            try block.delete(conn)
        }
    }

    /// Overwrites a block's "estimated hours without AI" — lets the user
    /// correct Claude's own estimate after the fact, e.g. from the
    /// SessionEnd review dialog or the Úspory view. Pass nil to clear it.
    public static func setEstimate(db: AppDatabase, blockId: UUID, hours: Double?) throws -> Block {
        try db.dbQueue.write { conn in
            guard var block = try Block.fetchOne(conn, key: blockId) else {
                throw BlockEditorError.blockNotFound
            }
            block.estimatedHoursWithoutAI = hours
            try block.update(conn)
            return block
        }
    }
}
