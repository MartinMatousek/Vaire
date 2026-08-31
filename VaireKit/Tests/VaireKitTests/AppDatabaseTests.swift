import Foundation
import Testing
@testable import VaireKit

@Test func schemaMigratesAndRoundTripsAProjectAndBlock() throws {
    let db = try AppDatabase.inMemory()

    let project = Project(name: "kvk-fe", path: "/Users/martinmatousek/IdeaProjects/kvk-fe")
    try db.dbQueue.write { conn in
        try project.insert(conn)
    }

    let block = Block(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 3600),
        source: .claudeSession
    )
    try db.dbQueue.write { conn in
        try block.insert(conn)
    }

    let fetchedBlocks = try db.dbQueue.read { conn in
        try Block.fetchAll(conn)
    }

    #expect(fetchedBlocks.count == 1)
    #expect(fetchedBlocks[0].id == block.id)
    #expect(fetchedBlocks[0].projectId == project.id)
}

@Test func findProjectByPathReturnsMatchOrNil() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "kvk-fe", path: "/Users/martinmatousek/IdeaProjects/kvk-fe")
    try db.dbQueue.write { try project.insert($0) }

    let found = try Project.find(byPath: "/Users/martinmatousek/IdeaProjects/kvk-fe", db: db)
    #expect(found?.id == project.id)

    let notFound = try Project.find(byPath: "/nonexistent", db: db)
    #expect(notFound == nil)
}

@Test func findOrCreateReturnsExistingProjectWithoutDuplicating() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe")
    try db.dbQueue.write { try project.insert($0) }

    let found = try Project.findOrCreate(byPath: "/tmp/kvk-fe", db: db)
    #expect(found.id == project.id)

    let all = try db.dbQueue.read { try Project.fetchAll($0) }
    #expect(all.count == 1)
}

@Test func findOrCreateMakesNewProjectNamedAfterLastPathComponent() throws {
    let db = try AppDatabase.inMemory()
    let created = try Project.findOrCreate(byPath: "/Users/martinmatousek/IdeaProjects/new-repo", db: db)

    #expect(created.name == "new-repo")
    #expect(created.path == "/Users/martinmatousek/IdeaProjects/new-repo")

    let all = try db.dbQueue.read { try Project.fetchAll($0) }
    #expect(all.count == 1)
}
