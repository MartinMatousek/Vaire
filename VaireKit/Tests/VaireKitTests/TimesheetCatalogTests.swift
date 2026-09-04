import Foundation
import Testing
@testable import VaireKit

@Test func projectIdUsesTrailingCodeFromLabel() throws {
    let id = try TimesheetCatalog.projectId(fromLabel: "ČEZ Prodej - Produkty a KVK - FY27 - ET97")
    #expect(id == "ET97")
}

@Test func projectIdThrowsOnUnparsableLabel() {
    #expect(throws: TimesheetCatalogError.self) {
        _ = try TimesheetCatalog.projectId(fromLabel: "")
    }
}

@Test func refreshInsertsNewProjectsAndTasks() throws {
    let db = try AppDatabase.inMemory()
    let scraped = [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK", "2 - A25 fáze 3"]),
        TimesheetScrapedProject(label: "Acme DE - ŠAD - HSS Rewrite CZ - OK39", taskLabels: ["HSS Rewrite - presales + reserve"]),
    ]

    let diff = try TimesheetCatalog.refresh(db: db, scraped: scraped)

    #expect(diff.newProjectLabels.count == 2)
    #expect(diff.newTaskLabels.count == 3)
    #expect(diff.deactivatedProjectLabels.isEmpty)
    #expect(diff.deactivatedTaskLabels.isEmpty)

    let projects = try db.dbQueue.read { try TimesheetProject.fetchAll($0) }
    #expect(projects.count == 2)
    #expect(projects.allSatisfy { $0.active })

    let tasks = try db.dbQueue.read { try TimesheetTask.fetchAll($0) }
    #expect(tasks.count == 3)
    #expect(tasks.allSatisfy { $0.active })
}

@Test func refreshDeactivatesProjectsAndTasksMissingFromNewScrape() throws {
    let db = try AppDatabase.inMemory()
    let initial = [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK", "2 - A25 fáze 3"]),
        TimesheetScrapedProject(label: "Acme DE - ŠAD - HSS Rewrite CZ - OK39", taskLabels: ["HSS Rewrite - presales + reserve"]),
    ]
    try TimesheetCatalog.refresh(db: db, scraped: initial)

    // Second project entirely gone; first project keeps only one of its two tasks.
    let updated = [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK"]),
    ]
    let diff = try TimesheetCatalog.refresh(db: db, scraped: updated)

    #expect(diff.deactivatedProjectLabels == ["Acme DE - ŠAD - HSS Rewrite CZ - OK39"])
    // Both the explicitly-dropped task under ET97 and the task under the
    // now-gone OK39 project deactivate — a task's project disappearing
    // deactivates it too, not just tasks dropped while their project stays.
    #expect(Set(diff.deactivatedTaskLabels) == ["2 - A25 fáze 3", "HSS Rewrite - presales + reserve"])

    let projects = try db.dbQueue.read { try TimesheetProject.fetchAll($0) }
    let ok39 = try #require(projects.first { $0.id == "OK39" })
    #expect(ok39.active == false)
    let et97 = try #require(projects.first { $0.id == "ET97" })
    #expect(et97.active == true)

    let tasks = try db.dbQueue.read { try TimesheetTask.fetchAll($0) }
    let removedTask = try #require(tasks.first { $0.label == "2 - A25 fáze 3" })
    #expect(removedTask.active == false)
    let remainingTask = try #require(tasks.first { $0.label == "1 - KVK" })
    #expect(remainingTask.active == true)
}

@Test func refreshReactivatesAProjectThatReappearsAfterBeingDeactivated() throws {
    let db = try AppDatabase.inMemory()
    let full = [TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK"])]
    try TimesheetCatalog.refresh(db: db, scraped: full)
    try TimesheetCatalog.refresh(db: db, scraped: []) // deactivates it

    let deactivated = try db.dbQueue.read { try TimesheetProject.fetchOne($0, key: "ET97") }
    #expect(deactivated?.active == false)

    try TimesheetCatalog.refresh(db: db, scraped: full) // reappears

    let reactivated = try db.dbQueue.read { try TimesheetProject.fetchOne($0, key: "ET97") }
    #expect(reactivated?.active == true)
}

@Test func validatePairingReturnsNilWhenProjectHasNoTimesheetPairing() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe")
    try db.dbQueue.write { try project.insert($0) }

    let issue = try TimesheetCatalog.validatePairing(db: db, project: project)
    #expect(issue == nil)
}

@Test func validatePairingReturnsNilWhenPairingIsActive() throws {
    let db = try AppDatabase.inMemory()
    try TimesheetCatalog.refresh(db: db, scraped: [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK"]),
    ])
    let taskId = TimesheetTask.makeId(timesheetProjectId: "ET97", label: "1 - KVK")

    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe", timesheetProjectId: "ET97", defaultTimesheetTaskId: taskId)
    try db.dbQueue.write { try project.insert($0) }

    let issue = try TimesheetCatalog.validatePairing(db: db, project: project)
    #expect(issue == nil)
}

@Test func validatePairingFlagsInactiveProject() throws {
    let db = try AppDatabase.inMemory()
    try TimesheetCatalog.refresh(db: db, scraped: [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK"]),
    ])
    try TimesheetCatalog.refresh(db: db, scraped: []) // deactivates ET97

    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe", timesheetProjectId: "ET97")
    try db.dbQueue.write { try project.insert($0) }

    let issue = try TimesheetCatalog.validatePairing(db: db, project: project)
    #expect(issue == .projectInactiveOrMissing)
}

@Test func validatePairingFlagsInactiveDefaultTask() throws {
    let db = try AppDatabase.inMemory()
    try TimesheetCatalog.refresh(db: db, scraped: [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK", "2 - A25 fáze 3"]),
    ])
    let staleTaskId = TimesheetTask.makeId(timesheetProjectId: "ET97", label: "2 - A25 fáze 3")

    // Task disappears from a later scrape, but the project itself is still active.
    try TimesheetCatalog.refresh(db: db, scraped: [
        TimesheetScrapedProject(label: "ČEZ Prodej - Produkty a KVK - FY27 - ET97", taskLabels: ["1 - KVK"]),
    ])

    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe", timesheetProjectId: "ET97", defaultTimesheetTaskId: staleTaskId)
    try db.dbQueue.write { try project.insert($0) }

    let issue = try TimesheetCatalog.validatePairing(db: db, project: project)
    #expect(issue == .defaultTaskInactiveOrMissing)
}

@Test func makeIdIsDeterministicAcrossCalls() {
    let id1 = TimesheetTask.makeId(timesheetProjectId: "ET97", label: "1 - KVK")
    let id2 = TimesheetTask.makeId(timesheetProjectId: "ET97", label: "1 - KVK")
    #expect(id1 == id2)

    let differentLabel = TimesheetTask.makeId(timesheetProjectId: "ET97", label: "2 - A25 fáze 3")
    #expect(id1 != differentLabel)
}
