import Foundation
import Testing
@testable import TimeKeeperKit

private func day(_ dateString: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: dateString)!
}

@Test func totalHoursSumsBlocksWithinTheDay() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let blockA = Block(projectId: project.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 10:00"), source: .manual)
    let blockB = Block(projectId: project.id, start: day("2026-08-21 13:00"), end: day("2026-08-21 15:30"), source: .claudeSession)
    try db.dbQueue.write {
        try blockA.insert($0)
        try blockB.insert($0)
    }

    let total = try DailySummary.totalHours(db: db, day: day("2026-08-21 00:00"), calendar: calendar)
    #expect(total == 4.5)
}

@Test func totalHoursClipsBlocksSpanningMidnight() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    // Block runs from 23:00 on the 21st to 01:00 on the 22nd — 1h should count toward each day.
    let block = Block(projectId: project.id, start: day("2026-08-21 23:00"), end: day("2026-08-22 01:00"), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let day21Total = try DailySummary.totalHours(db: db, day: day("2026-08-21 00:00"), calendar: calendar)
    let day22Total = try DailySummary.totalHours(db: db, day: day("2026-08-22 00:00"), calendar: calendar)

    #expect(day21Total == 1.0)
    #expect(day22Total == 1.0)
}

@Test func perProjectTotalsOmitsProjectsWithNoBlocksThatDay() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let active = Project(name: "active", path: "/tmp/active")
    let idle = Project(name: "idle", path: "/tmp/idle")
    try db.dbQueue.write {
        try active.insert($0)
        try idle.insert($0)
    }

    let block = Block(projectId: active.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 09:00"), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let totals = try DailySummary.perProjectTotals(db: db, day: day("2026-08-21 00:00"), calendar: calendar)
    #expect(totals.count == 1)
    #expect(totals[0].project.id == active.id)
    #expect(totals[0].hours == 1.0)
}

@Test func todaysBlocksReturnsMostRecentFirst() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let earlier = Block(projectId: project.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 09:00"), source: .manual, note: "morning work")
    let later = Block(projectId: project.id, start: day("2026-08-21 13:00"), end: day("2026-08-21 14:00"), source: .manual, note: "afternoon work")
    try db.dbQueue.write {
        try earlier.insert($0)
        try later.insert($0)
    }

    let blocks = try DailySummary.todaysBlocks(db: db, projectId: project.id, day: day("2026-08-21 15:00"), calendar: calendar)
    #expect(blocks.count == 2)
    #expect(blocks[0].note == "afternoon work")
    #expect(blocks[1].note == "morning work")
}

@Test func todaysBlocksExcludesOtherProjectsAndOtherDays() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let projectA = Project(name: "a", path: "/tmp/a")
    let projectB = Project(name: "b", path: "/tmp/b")
    try db.dbQueue.write {
        try projectA.insert($0)
        try projectB.insert($0)
    }

    let todayA = Block(projectId: projectA.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 09:00"), source: .manual)
    let todayB = Block(projectId: projectB.id, start: day("2026-08-21 08:00"), end: day("2026-08-21 09:00"), source: .manual)
    let yesterdayA = Block(projectId: projectA.id, start: day("2026-08-20 08:00"), end: day("2026-08-20 09:00"), source: .manual)
    try db.dbQueue.write {
        try todayA.insert($0)
        try todayB.insert($0)
        try yesterdayA.insert($0)
    }

    let blocks = try DailySummary.todaysBlocks(db: db, projectId: projectA.id, day: day("2026-08-21 15:00"), calendar: calendar)
    #expect(blocks.count == 1)
    #expect(blocks[0].id == todayA.id)
}
