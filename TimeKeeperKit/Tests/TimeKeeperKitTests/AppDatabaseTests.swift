import Foundation
import Testing
@testable import TimeKeeperKit

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
