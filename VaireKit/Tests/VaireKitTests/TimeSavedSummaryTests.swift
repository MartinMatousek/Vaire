import Foundation
import Testing
@testable import VaireKit

private func day(_ dateString: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: dateString)!
}

@Test func weekSummaryIncludesOnlyBlocksWithEstimates() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    // 2026-08-24 is a Monday.
    let estimated = Block(projectId: project.id, start: day("2026-08-24 09:00"), end: day("2026-08-24 09:30"), source: .claudeSession, estimatedHoursWithoutAI: 4.0)
    let unestimated = Block(projectId: project.id, start: day("2026-08-24 10:00"), end: day("2026-08-24 11:00"), source: .manual)
    try db.dbQueue.write {
        try estimated.insert($0)
        try unestimated.insert($0)
    }

    let summary = try TimeSavedSummary.weekSummary(db: db, day: day("2026-08-24 12:00"), calendar: calendar)
    #expect(summary.entries.count == 1)
    #expect(summary.entries[0].block.id == estimated.id)
}

@Test func weekSummaryComputesSavedHoursCorrectly() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let block = Block(projectId: project.id, start: day("2026-08-24 09:00"), end: day("2026-08-24 09:30"), source: .claudeSession, estimatedHoursWithoutAI: 4.0)
    try db.dbQueue.write { try block.insert($0) }

    let summary = try TimeSavedSummary.weekSummary(db: db, day: day("2026-08-24 12:00"), calendar: calendar)
    #expect(summary.entries[0].actualHours == 0.5)
    #expect(summary.entries[0].estimatedHours == 4.0)
    #expect(summary.entries[0].savedHours == 3.5)
}

@Test func weekSummaryAggregatesTotalsAcrossEntries() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let blockA = Block(projectId: project.id, start: day("2026-08-24 09:00"), end: day("2026-08-24 09:30"), source: .claudeSession, estimatedHoursWithoutAI: 4.0)
    let blockB = Block(projectId: project.id, start: day("2026-08-25 09:00"), end: day("2026-08-25 10:00"), source: .claudeSession, estimatedHoursWithoutAI: 2.0)
    try db.dbQueue.write {
        try blockA.insert($0)
        try blockB.insert($0)
    }

    let summary = try TimeSavedSummary.weekSummary(db: db, day: day("2026-08-24 12:00"), calendar: calendar)
    #expect(summary.totalActualHours == 1.5)
    #expect(summary.totalEstimatedHours == 6.0)
    #expect(summary.totalSavedHours == 4.5)
}

@Test func weekSummaryExcludesBlocksFromOtherWeeks() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    // A week earlier.
    let lastWeek = Block(projectId: project.id, start: day("2026-08-17 09:00"), end: day("2026-08-17 09:30"), source: .claudeSession, estimatedHoursWithoutAI: 4.0)
    try db.dbQueue.write { try lastWeek.insert($0) }

    let summary = try TimeSavedSummary.weekSummary(db: db, day: day("2026-08-24 12:00"), calendar: calendar)
    #expect(summary.entries.isEmpty)
}
