import Foundation
import GRDB
import Testing
@testable import VaireKit

/// Confirms the v8 migration (renaming trask*/Trask* columns/tables to
/// timesheet*/Timesheet*) preserves existing data for users who already had
/// rows under the old v7 schema — this is the one place that assumption
/// gets verified against an actual pre-v8 database shape.
@Test func v8MigrationPreservesExistingTraskData() throws {
    let dbQueue = try DatabaseQueue()

    var partialMigrator = DatabaseMigrator()
    partialMigrator.registerMigration("v1") { db in
        try db.create(table: "project") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("path", .text).notNull().unique()
            t.column("colorHex", .text).notNull()
            t.column("mdHoursPerDay", .double).notNull()
        }
        try db.create(table: "block") { t in
            t.column("id", .text).primaryKey()
            t.column("projectId", .text).notNull().references("project", onDelete: .cascade)
            t.column("start", .datetime).notNull()
            t.column("end", .datetime).notNull()
            t.column("source", .text).notNull()
            t.column("note", .text)
            t.column("isManual", .boolean).notNull().defaults(to: false)
            t.column("confidence", .double).notNull().defaults(to: 1.0)
        }
    }
    partialMigrator.registerMigration("v4") { db in
        try db.alter(table: "project") { t in
            t.add(column: "hooksEnabled", .boolean).notNull().defaults(to: false)
        }
    }
    partialMigrator.registerMigration("v7") { db in
        try db.create(table: "traskProject") { t in
            t.column("id", .text).primaryKey()
            t.column("label", .text).notNull()
            t.column("active", .boolean).notNull().defaults(to: true)
        }
        try db.create(table: "traskTask") { t in
            t.column("id", .text).primaryKey()
            t.column("traskProjectId", .text).notNull().references("traskProject", onDelete: .cascade)
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
    try partialMigrator.migrate(dbQueue, upTo: "v7")

    // Insert data through the pre-v8 (trask-named) schema via raw SQL,
    // simulating a real user's already-populated database.
    let blockId = UUID().uuidString
    let projectId = UUID().uuidString
    try dbQueue.write { db in
        try db.execute(sql: "INSERT INTO traskProject (id, label, active) VALUES (?, ?, ?)", arguments: ["ET97", "ČEZ Prodej - Produkty a KVK - FY27 - ET97", true])
        try db.execute(sql: "INSERT INTO traskTask (id, traskProjectId, label, active) VALUES (?, ?, ?, ?)", arguments: ["task1", "ET97", "1 - KVK", true])
        try db.execute(sql: "INSERT INTO project (id, name, path, colorHex, mdHoursPerDay, hooksEnabled, traskProjectId, defaultTraskTaskId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                       arguments: [projectId, "kvk-fe", "/tmp/kvk-fe", "#34C759", 8.0, false, "ET97", "task1"])
        try db.execute(sql: "INSERT INTO block (id, projectId, start, end, source, isManual, confidence, traskTaskId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                       arguments: [blockId, projectId, Date(), Date(), "manual", true, 1.0, "task1"])
    }

    var fullMigrator = partialMigrator
    fullMigrator.registerMigration("v8") { db in
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
    try fullMigrator.migrate(dbQueue)

    let (projects, tasks) = try dbQueue.read { db in
        (try TimesheetProject.fetchAll(db), try TimesheetTask.fetchAll(db))
    }
    #expect(projects.count == 1)
    #expect(projects[0].id == "ET97")
    #expect(projects[0].label == "ČEZ Prodej - Produkty a KVK - FY27 - ET97")
    #expect(tasks.count == 1)
    #expect(tasks[0].timesheetProjectId == "ET97")

    let project = try dbQueue.read { db in
        try Project.filter(Column("path") == "/tmp/kvk-fe").fetchOne(db)
    }
    #expect(project?.timesheetProjectId == "ET97")
    #expect(project?.defaultTimesheetTaskId == "task1")

    let block = try dbQueue.read { db in try Block.fetchOne(db, key: blockId) }
    #expect(block?.timesheetTaskId == "task1")
}
