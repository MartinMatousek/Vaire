import Foundation
import Testing
@testable import TimeKeeperKit

@Test func startThenStopPersistsAManualBlock() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "test", path: "/tmp/test")
    try db.dbQueue.write { try project.insert($0) }

    var currentTime = Date(timeIntervalSince1970: 1000)
    let controller = TimerController(db: db, now: { currentTime })

    controller.start(projectId: project.id)
    #expect(controller.isRunning(projectId: project.id))

    currentTime = currentTime.addingTimeInterval(1800)
    let block = try controller.stop(projectId: project.id)

    #expect(!controller.isRunning(projectId: project.id))
    #expect(block?.isManual == true)
    #expect(block?.source == .manual)
    #expect(block?.duration == 1800)

    let stored = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(stored.count == 1)
}

@Test func stopWithoutStartReturnsNil() throws {
    let db = try AppDatabase.inMemory()
    let controller = TimerController(db: db)
    #expect(try controller.stop(projectId: UUID()) == nil)
}

@Test func startingAnAlreadyRunningProjectDoesNotResetItsStartTime() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "a", path: "/tmp/a")
    try db.dbQueue.write { try project.insert($0) }

    var currentTime = Date(timeIntervalSince1970: 1000)
    let controller = TimerController(db: db, now: { currentTime })

    controller.start(projectId: project.id)
    currentTime = currentTime.addingTimeInterval(600)
    controller.start(projectId: project.id) // should be a no-op

    #expect(controller.elapsed(projectId: project.id) == 600)
}

@Test func multipleProjectsCanRunConcurrently() throws {
    let db = try AppDatabase.inMemory()
    let projectA = Project(name: "a", path: "/tmp/a")
    let projectB = Project(name: "b", path: "/tmp/b")
    try db.dbQueue.write {
        try projectA.insert($0)
        try projectB.insert($0)
    }

    let controller = TimerController(db: db)
    controller.start(projectId: projectA.id)
    controller.start(projectId: projectB.id)

    #expect(controller.isRunning(projectId: projectA.id))
    #expect(controller.isRunning(projectId: projectB.id))
    #expect(controller.hasAnyRunning)
}

@Test func stoppingOneConcurrentTimerLeavesTheOtherRunning() throws {
    let db = try AppDatabase.inMemory()
    let projectA = Project(name: "a", path: "/tmp/a")
    let projectB = Project(name: "b", path: "/tmp/b")
    try db.dbQueue.write {
        try projectA.insert($0)
        try projectB.insert($0)
    }

    let controller = TimerController(db: db)
    controller.start(projectId: projectA.id)
    controller.start(projectId: projectB.id)

    _ = try controller.stop(projectId: projectA.id)

    #expect(!controller.isRunning(projectId: projectA.id))
    #expect(controller.isRunning(projectId: projectB.id))
}

@Test func noteCapturedAtStartLandsOnTheStoppedBlock() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "a", path: "/tmp/a")
    try db.dbQueue.write { try project.insert($0) }

    let controller = TimerController(db: db)
    controller.start(projectId: project.id, note: "fixing batch update bug")
    let block = try controller.stop(projectId: project.id)

    #expect(block?.note == "fixing batch update bug")
}

@Test func startingWithoutNoteLeavesBlockNoteNil() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "a", path: "/tmp/a")
    try db.dbQueue.write { try project.insert($0) }

    let controller = TimerController(db: db)
    controller.start(projectId: project.id)
    let block = try controller.stop(projectId: project.id)

    #expect(block?.note == nil)
}
