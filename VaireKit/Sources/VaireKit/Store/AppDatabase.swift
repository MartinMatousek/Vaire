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

        migrator.registerMigration("v4") { db in
            // Hooks now opt in per repository instead of tracking every
            // cwd a Claude Code session happens to run in. Defaults to
            // false so existing auto-created projects don't suddenly start
            // popping dialogs; the user enables the repos they want.
            try db.alter(table: "project") { t in
                t.add(column: "hooksEnabled", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v5") { db in
            // Deleting an auto-imported block only removed the row — the
            // next live reimport of the same Claude Code session file
            // would re-derive and re-insert it, since the source
            // transcript still has those turns. A tombstone of the
            // deleted time range lets ReimportGuard.reconcile skip
            // re-creating anything that overlaps it, so a delete sticks.
            try db.create(table: "deletedBlockRange") { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
            }
            try db.create(index: "deletedBlockRange_projectId", on: "deletedBlockRange", columns: ["projectId"])
        }

        migrator.registerMigration("v6") { db in
            // The SessionStart "Log time?" dialog only controls the
            // hook-driven manual timer (AgentSessionTracking/start-session).
            // LiveImportCoordinator passively imports every session's
            // transcript for any project with hooksEnabled, regardless of
            // that answer, so declining still produced a block. A tombstone
            // keyed by session_id lets the passive importer skip a session
            // the user explicitly declined to log.
            try db.create(table: "declinedSession") { t in
                t.column("sessionId", .text).primaryKey()
            }
        }

        migrator.registerMigration("v7") { db in
            // The external timesheet's project/task catalog is scraped from
            // the live my.trask.cz UI (it has no API) and cached here so
            // Settings can offer real pickers without re-scraping on every
            // screen open. `id` is derived from the scraped label (the
            // stable trailing code for a project, e.g. "ET97" — the
            // client/fiscal-year prefix churns yearly; a hash of the label
            // for a task, which has no such stable code) so a re-scrape can
            // upsert by identity instead of only ever growing the table.
            // `active` is flipped false rather than deleting a row that
            // disappears from a scrape, so a project/task the user already
            // paired against can be detected as stale and flagged for
            // re-pairing instead of silently pointing at nothing.
            try db.create(table: "traskProject") { t in
                t.column("id", .text).primaryKey()
                t.column("label", .text).notNull()
                t.column("active", .boolean).notNull().defaults(to: true)
            }

            try db.create(table: "traskTask") { t in
                t.column("id", .text).primaryKey()
                t.column("traskProjectId", .text).notNull()
                    .references("traskProject", onDelete: .cascade)
                t.column("label", .text).notNull()
                t.column("active", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "traskTask_traskProjectId", on: "traskTask", columns: ["traskProjectId"])

            try db.alter(table: "project") { t in
                t.add(column: "traskProjectId", .text)
                t.add(column: "defaultTraskTaskId", .text)
            }

            try db.alter(table: "block") { t in
                t.add(column: "traskTaskId", .text)
            }
        }

        migrator.registerMigration("v8") { db in
            // De-brands Vaire's own table/column naming for the external
            // timesheet integration — "Trask" was never Vaire's name to
            // use, it's the external product's name. Renamed here (not just
            // at the Swift-type level) so already-installed users' DBs
            // don't end up with columns that no longer match anything in
            // the app.
            //
            // `traskProject` is renamed in place (it has no foreign key
            // clauses pointing at it that need rewriting, and no incoming
            // rename of its own columns). `traskTask` is rebuilt from
            // scratch instead of renamed in place — confirmed live that
            // `ALTER TABLE traskTask RENAME TO timesheetTask` (and the
            // column rename after it) leaves the CREATE TABLE's own
            // `REFERENCES traskProject(id)` clause referring to the
            // OLD table name, since SQLite's rename doesn't rewrite a
            // table's own foreign-key clause text to match a column rename
            // performed in a separate statement — this then trips a real
            // foreign-key-constraint violation on every future write
            // against a column that, from the app's Swift-level view,
            // looks completely renamed and healthy.
            try db.rename(table: "traskProject", to: "timesheetProject")

            try db.create(table: "timesheetTask") { t in
                t.column("id", .text).primaryKey()
                t.column("timesheetProjectId", .text).notNull()
                    .references("timesheetProject", onDelete: .cascade)
                t.column("label", .text).notNull()
                t.column("active", .boolean).notNull().defaults(to: true)
            }
            try db.execute(sql: """
                INSERT INTO timesheetTask (id, timesheetProjectId, label, active)
                SELECT id, traskProjectId, label, active FROM traskTask
                """)
            try db.drop(table: "traskTask")
            try db.create(index: "timesheetTask_timesheetProjectId", on: "timesheetTask", columns: ["timesheetProjectId"])

            try db.alter(table: "project") { t in
                t.rename(column: "traskProjectId", to: "timesheetProjectId")
                t.rename(column: "defaultTraskTaskId", to: "defaultTimesheetTaskId")
            }
            try db.alter(table: "block") { t in
                t.rename(column: "traskTaskId", to: "timesheetTaskId")
            }
        }

        return migrator
    }
}
