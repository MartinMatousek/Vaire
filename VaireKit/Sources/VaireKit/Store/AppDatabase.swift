import Foundation
import GRDB

public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        try self.init(dbQueue: DatabaseQueue(path: path))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(dbQueue: DatabaseQueue())
    }

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("colorHex", .text).notNull()
                t.column("mdHoursPerDay", .double).notNull()
            }

            try db.create(table: "block") { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("note", .text)
                t.column("isManual", .boolean).notNull().defaults(to: false)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
            }
            try db.create(index: "block_projectId_start", on: "block", columns: ["projectId", "start"])

            try db.create(table: "evidence") { t in
                t.column("id", .text).primaryKey()
                t.column("blockId", .text).notNull()
                    .references("block", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("refId", .text).notNull()
                t.column("payloadJSON", .text)
            }
            try db.create(index: "evidence_blockId", on: "evidence", columns: ["blockId"])
        }

        migrator.registerMigration("v2") { db in
            // Tracks an in-progress timer started by an external agent (a
            // Claude Code hook) keyed by its session id, so SessionEnd can
            // look up where/when it started without the hook process itself
            // holding any state between the two hook invocations.
            try db.create(table: "agentSessionTracking") { t in
                t.column("sessionId", .text).primaryKey()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("start", .datetime).notNull()
                t.column("note", .text)
            }
        }

        migrator.registerMigration("v3") { db in
            // Claude's own estimate of how long a task would normally take
            // without AI assistance, so the SessionEnd summary can show the
            // "added value" (estimate minus actual logged time). Set by the
            // agent itself via `vaire set-estimate` before ending
            // the session; nil for blocks where no estimate was recorded.
            try db.alter(table: "agentSessionTracking") { t in
                t.add(column: "estimatedHoursWithoutAI", .double)
            }
            try db.alter(table: "block") { t in
                t.add(column: "estimatedHoursWithoutAI", .double)
            }
        }

        return migrator
    }
}
