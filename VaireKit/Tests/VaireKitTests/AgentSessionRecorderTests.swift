import Foundation
import Testing
@testable import VaireKit

@Test func startCreatesProjectIfMissingAndTracksSession() throws {
    let db = try AppDatabase.inMemory()
    let project = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/new-repo", note: "fixing bug")

    #expect(project.name == "new-repo")
    #expect(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-1"))
}

@Test func startReusesExistingProjectForSameCwd() throws {
    let db = try AppDatabase.inMemory()
    let existing = Project(name: "kvk-fe", path: "/tmp/kvk-fe")
    try db.dbQueue.write { try existing.insert($0) }

    let project = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/kvk-fe", note: nil)
    #expect(project.id == existing.id)

    let allProjects = try db.dbQueue.read { try Project.fetchAll($0) }
    #expect(allProjects.count == 1)
}

@Test func startTwiceForSameSessionDoesNotResetClock() throws {
    let db = try AppDatabase.inMemory()
    let start = Date(timeIntervalSince1970: 1000)

    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/repo", note: nil, now: start)
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/repo", note: nil, now: start.addingTimeInterval(600))

    let result = try AgentSessionRecorder.stop(db: db, sessionId: "sess-1", now: start.addingTimeInterval(1200))
    #expect(result?.block.duration == 1200) // from the FIRST start, not the second
}

@Test func stopPersistsBlockWithNoteAndClaudeSessionSource() throws {
    let db = try AppDatabase.inMemory()
    let start = Date(timeIntervalSince1970: 1000)
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/repo", note: "fixing batch update bug", now: start)

    let result = try AgentSessionRecorder.stop(db: db, sessionId: "sess-1", now: start.addingTimeInterval(1800))

    #expect(result?.block.note == "fixing batch update bug")
    #expect(result?.block.source == .claudeSession)
    #expect(result?.block.isManual == false)
    #expect(result?.project.path == "/tmp/repo")

    #expect(!(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-1")))
}

@Test func stopUntrackedSessionReturnsNil() throws {
    let db = try AppDatabase.inMemory()
    let result = try AgentSessionRecorder.stop(db: db, sessionId: "never-started")
    #expect(result == nil)
}

@Test func isTrackingReflectsOptOut() throws {
    let db = try AppDatabase.inMemory()
    #expect(!(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-1")))
}

@Test func findActiveTrackingLocatesRunningTimerByCwd() throws {
    let db = try AppDatabase.inMemory()
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-old", cwd: "/tmp/repo", note: "fixing bug")

    let found = try AgentSessionRecorder.findActiveTracking(db: db, cwd: "/tmp/repo")
    #expect(found?.sessionId == "sess-old")
    #expect(found?.note == "fixing bug")
}

@Test func findActiveTrackingReturnsNilWhenNothingRunning() throws {
    let db = try AppDatabase.inMemory()
    #expect(try AgentSessionRecorder.findActiveTracking(db: db, cwd: "/tmp/repo") == nil)
}

@Test func continueTrackingPreservesStartTimeAcrossSessionIdChange() throws {
    let db = try AppDatabase.inMemory()
    let start = Date(timeIntervalSince1970: 1000)
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-old", cwd: "/tmp/repo", note: "fixing bug", now: start)

    try AgentSessionRecorder.continueTracking(db: db, oldSessionId: "sess-old", newSessionId: "sess-new")

    #expect(!(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-old")))
    #expect(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-new"))

    let result = try AgentSessionRecorder.stop(db: db, sessionId: "sess-new", now: start.addingTimeInterval(1800))
    #expect(result?.block.duration == 1800) // preserved from the original start, across the /clear
    #expect(result?.block.note == "fixing bug")
}

@Test func continueTrackingWithMissingOldSessionIsANoOp() throws {
    let db = try AppDatabase.inMemory()
    try AgentSessionRecorder.continueTracking(db: db, oldSessionId: "never-existed", newSessionId: "sess-new")
    #expect(!(try AgentSessionRecorder.isTracking(db: db, sessionId: "sess-new")))
}

@Test func setEstimateCarriesThroughToTheStoppedBlock() throws {
    let db = try AppDatabase.inMemory()
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/repo", note: "tricky bug")

    try AgentSessionRecorder.setEstimate(db: db, sessionId: "sess-1", hours: 4.0)
    let result = try AgentSessionRecorder.stop(db: db, sessionId: "sess-1")

    #expect(result?.block.estimatedHoursWithoutAI == 4.0)
}

@Test func setEstimateOnUntrackedSessionIsANoOp() throws {
    let db = try AppDatabase.inMemory()
    try AgentSessionRecorder.setEstimate(db: db, sessionId: "never-started", hours: 4.0)
    // No crash, and nothing to assert on — the session was never tracked.
}

@Test func continueTrackingPreservesEstimate() throws {
    let db = try AppDatabase.inMemory()
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-old", cwd: "/tmp/repo", note: nil)
    try AgentSessionRecorder.setEstimate(db: db, sessionId: "sess-old", hours: 2.5)

    try AgentSessionRecorder.continueTracking(db: db, oldSessionId: "sess-old", newSessionId: "sess-new")
    let result = try AgentSessionRecorder.stop(db: db, sessionId: "sess-new")

    #expect(result?.block.estimatedHoursWithoutAI == 2.5)
}

@Test func hasEstimateReflectsTrackingAndEstimateState() throws {
    let db = try AppDatabase.inMemory()

    #expect(!(try AgentSessionRecorder.hasEstimate(db: db, sessionId: "sess-1"))) // not tracking

    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/repo", note: nil)
    #expect(!(try AgentSessionRecorder.hasEstimate(db: db, sessionId: "sess-1"))) // tracking, no estimate

    try AgentSessionRecorder.setEstimate(db: db, sessionId: "sess-1", hours: 1.0)
    #expect(try AgentSessionRecorder.hasEstimate(db: db, sessionId: "sess-1")) // tracking, has estimate
}

@Test func allActiveTrackingsReturnsEveryRunningSessionOldestFirst() throws {
    let db = try AppDatabase.inMemory()
    let earlier = Date(timeIntervalSince1970: 1000)
    let later = Date(timeIntervalSince1970: 2000)

    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-later", cwd: "/tmp/a", note: nil, now: later)
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-earlier", cwd: "/tmp/b", note: nil, now: earlier)

    let all = try AgentSessionRecorder.allActiveTrackings(db: db)
    #expect(all.map(\.sessionId) == ["sess-earlier", "sess-later"])
}

@Test func allActiveTrackingsExcludesStoppedSessions() throws {
    let db = try AppDatabase.inMemory()
    _ = try AgentSessionRecorder.start(db: db, sessionId: "sess-1", cwd: "/tmp/a", note: nil)
    _ = try AgentSessionRecorder.stop(db: db, sessionId: "sess-1")

    #expect(try AgentSessionRecorder.allActiveTrackings(db: db).isEmpty)
}
