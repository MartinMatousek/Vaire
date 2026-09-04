import Foundation
import Testing
@testable import VaireKit

private func day(_ dateString: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: dateString)!
}

@Test func statusOnEmptyDayReportsFullGap() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let status = try DayFinisher.status(db: db, day: day("2026-08-21 00:00"), targetHours: 8, calendar: calendar)

    #expect(status.loggedHours == 0)
    #expect(status.gapHours == 8)
    #expect(!status.isComplete)
}

@Test func statusOnPartialDayReportsRemainingGap() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }
    let block = Block(projectId: project.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 11:00"), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let status = try DayFinisher.status(db: db, day: day("2026-08-21 00:00"), targetHours: 8, calendar: calendar)

    #expect(status.loggedHours == 3)
    #expect(status.gapHours == 5)
    #expect(!status.isComplete)
}

@Test func statusOnOverTargetDayHasZeroGap() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }
    let block = Block(projectId: project.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 19:00"), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let status = try DayFinisher.status(db: db, day: day("2026-08-21 00:00"), targetHours: 8, calendar: calendar)

    #expect(status.loggedHours == 11)
    #expect(status.gapHours == 0)
    #expect(status.isComplete)
}

@Test func overlapFilterDropsCommitInsideExistingBlockForSameProject() {
    let projectId = UUID()
    let blocks = [
        Block(projectId: projectId, start: day("2026-08-21 08:00"), end: day("2026-08-21 12:00"), source: .manual),
    ]
    let range = (start: day("2026-08-21 09:00"), end: day("2026-08-21 10:00"))

    #expect(GitImporter.overlapsExistingBlock(range, projectId: projectId, blocks: blocks))
}

@Test func overlapFilterKeepsAdjacentRange() {
    let projectId = UUID()
    let blocks = [
        Block(projectId: projectId, start: day("2026-08-21 08:00"), end: day("2026-08-21 12:00"), source: .manual),
    ]
    let range = (start: day("2026-08-21 12:00"), end: day("2026-08-21 13:00"))

    #expect(!GitImporter.overlapsExistingBlock(range, projectId: projectId, blocks: blocks))
}

@Test func overlapFilterKeepsRangeOverlappingDifferentProjectsBlock() {
    let projectId = UUID()
    let otherProjectId = UUID()
    let blocks = [
        Block(projectId: otherProjectId, start: day("2026-08-21 08:00"), end: day("2026-08-21 12:00"), source: .manual),
    ]
    let range = (start: day("2026-08-21 09:00"), end: day("2026-08-21 10:00"))

    #expect(!GitImporter.overlapsExistingBlock(range, projectId: projectId, blocks: blocks))
}

@Test func applyGitCommitSuggestionInsertsManualGitCommitBlock() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let suggestion = FinishSuggestion(
        kind: .gitCommit(shas: ["abc"], suggestedNote: "Fix bug"),
        projectId: project.id,
        start: day("2026-08-21 08:00"),
        durationMinutes: 45,
        note: "Fix bug"
    )

    let block = try DayFinisher.apply(db: db, suggestion: suggestion)

    #expect(block.source == .gitCommit)
    #expect(block.isManual)
    #expect(block.note == "Fix bug")
    #expect(block.start == day("2026-08-21 08:00"))
    #expect(block.end == day("2026-08-21 08:45"))
}

@Test func applyProlongSuggestionExtendsExistingBlockEnd() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }
    let original = Block(projectId: project.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 09:00"), source: .claudeSession, isManual: false)
    try db.dbQueue.write { try original.insert($0) }

    let suggestion = FinishSuggestion(
        kind: .prolong(blockId: original.id, currentStart: original.start, currentEnd: original.end),
        projectId: project.id,
        start: original.end,
        durationMinutes: 30,
        note: ""
    )

    let updated = try DayFinisher.apply(db: db, suggestion: suggestion)

    #expect(updated.id == original.id)
    #expect(updated.start == day("2026-08-21 08:00"))
    #expect(updated.end == day("2026-08-21 09:30"))
    #expect(updated.isManual)
}

@Test func applyManualSuggestionInsertsManualBlock() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let suggestion = FinishSuggestion(
        kind: .manual,
        projectId: project.id,
        start: day("2026-08-21 17:00"),
        durationMinutes: 60,
        note: "Meeting"
    )

    let block = try DayFinisher.apply(db: db, suggestion: suggestion)

    #expect(block.source == .manual)
    #expect(block.isManual)
    #expect(block.note == "Meeting")
    #expect(block.end == day("2026-08-21 18:00"))
}
