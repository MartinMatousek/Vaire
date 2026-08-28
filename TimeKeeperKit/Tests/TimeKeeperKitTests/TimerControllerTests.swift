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
    #expect(controller.isRunning)

    currentTime = currentTime.addingTimeInterval(1800)
    let block = try controller.stop()

    #expect(!controller.isRunning)
    #expect(block?.isManual == true)
    #expect(block?.source == .manual)
    #expect(block?.duration == 1800)

    let stored = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(stored.count == 1)
}

@Test func stopWithoutStartReturnsNil() throws {
    let db = try AppDatabase.inMemory()
    let controller = TimerController(db: db)
    #expect(try controller.stop() == nil)
}

@Test func startWhileRunningIsIgnored() throws {
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

    #expect(controller.runningProjectId == projectA.id)
}
