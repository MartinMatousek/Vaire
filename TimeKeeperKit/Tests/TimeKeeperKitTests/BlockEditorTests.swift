import Foundation
import Testing
@testable import TimeKeeperKit

private func makeProject(_ db: AppDatabase) throws -> Project {
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }
    return project
}

@Test func moveByDaysPreservesLengthAndSetsManual() throws {
    let db = try AppDatabase.inMemory()
    let project = try makeProject(db)
    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .claudeSession)
    try db.dbQueue.write { try block.insert($0) }

    let moved = try BlockEditor.move(db: db, blockId: block.id, byDays: 1)

    #expect(moved.start == Date(timeIntervalSince1970: 86400))
    #expect(moved.end == Date(timeIntervalSince1970: 86400 + 3600))
    #expect(moved.duration == block.duration)
    #expect(moved.isManual)
}

@Test func splitProducesTwoAdjacentBlocksCoveringOriginalRange() throws {
    let db = try AppDatabase.inMemory()
    let project = try makeProject(db)
    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7200), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let splitPoint = Date(timeIntervalSince1970: 3600)
    let (first, second) = try BlockEditor.split(db: db, blockId: block.id, at: splitPoint)

    #expect(first.start == block.start)
    #expect(first.end == splitPoint)
    #expect(second.start == splitPoint)
    #expect(second.end == block.end)
    #expect(first.isManual && second.isManual)

    let allBlocks = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(allBlocks.count == 2)
}

@Test func splitOutOfRangeThrows() throws {
    let db = try AppDatabase.inMemory()
    let project = try makeProject(db)
    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    #expect(throws: BlockEditorError.self) {
        try BlockEditor.split(db: db, blockId: block.id, at: Date(timeIntervalSince1970: 9000))
    }
}

@Test func splitThenMergeRestoresOriginalRange() throws {
    let db = try AppDatabase.inMemory()
    let project = try makeProject(db)
    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7200), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let (first, second) = try BlockEditor.split(db: db, blockId: block.id, at: Date(timeIntervalSince1970: 3600))
    let merged = try BlockEditor.merge(db: db, blockIds: [first.id, second.id])

    #expect(merged.start == block.start)
    #expect(merged.end == block.end)

    let allBlocks = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(allBlocks.count == 1)
}

@Test func mergeAcrossDifferentProjectsThrows() throws {
    let db = try AppDatabase.inMemory()
    let projectA = try makeProject(db)
    let projectB = Project(name: "b", path: "/tmp/b")
    try db.dbQueue.write { try projectB.insert($0) }

    let blockA = Block(projectId: projectA.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .manual)
    let blockB = Block(projectId: projectB.id, start: Date(timeIntervalSince1970: 3600), end: Date(timeIntervalSince1970: 7200), source: .manual)
    try db.dbQueue.write {
        try blockA.insert($0)
        try blockB.insert($0)
    }

    #expect(throws: BlockEditorError.self) {
        try BlockEditor.merge(db: db, blockIds: [blockA.id, blockB.id])
    }
}

@Test func setProjectReassignsAndMarksManual() throws {
    let db = try AppDatabase.inMemory()
    let projectA = try makeProject(db)
    let projectB = Project(name: "b", path: "/tmp/b")
    try db.dbQueue.write { try projectB.insert($0) }

    let block = Block(projectId: projectA.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .claudeSession)
    try db.dbQueue.write { try block.insert($0) }

    let updated = try BlockEditor.setProject(db: db, blockId: block.id, projectId: projectB.id)
    #expect(updated.projectId == projectB.id)
    #expect(updated.isManual)
}

@Test func setNoteUpdatesDescriptionOrClearsIt() throws {
    let db = try AppDatabase.inMemory()
    let project = try makeProject(db)
    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let withNote = try BlockEditor.setNote(db: db, blockId: block.id, note: "fixing batch update bug")
    #expect(withNote.note == "fixing batch update bug")

    let cleared = try BlockEditor.setNote(db: db, blockId: block.id, note: "")
    #expect(cleared.note == nil)
}
