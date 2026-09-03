import Foundation
import Testing
@testable import VaireKit

private func day(_ dateString: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: dateString)!
}

// 2026-08-24 is a Monday; 2026-08-29 is the Saturday of that week.
@Test func daysNeedingReviewExcludesWeekdaysAtTarget() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let monday = day("2026-08-24 00:00")
    let fullDay = Block(projectId: project.id, start: day("2026-08-24 08:00"), end: day("2026-08-24 16:00"), source: .manual)
    try db.dbQueue.write { try fullDay.insert($0) }

    let results = try WeekFinisher.daysNeedingReview(db: db, weekStart: monday, targetHours: 8, calendar: calendar)

    #expect(!results.contains { calendar.isDate($0.day, inSameDayAs: monday) })
}

@Test func daysNeedingReviewExcludesEmptySaturday() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let monday = day("2026-08-24 00:00")
    let saturday = day("2026-08-29 00:00")

    let results = try WeekFinisher.daysNeedingReview(db: db, weekStart: monday, targetHours: 8, calendar: calendar)

    #expect(!results.contains { calendar.isDate($0.day, inSameDayAs: saturday) })
}

@Test func daysNeedingReviewIncludesSaturdayWithLoggedHours() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let monday = day("2026-08-24 00:00")
    let saturday = day("2026-08-29 00:00")
    let block = Block(projectId: project.id, start: day("2026-08-29 09:00"), end: day("2026-08-29 11:00"), source: .manual)
    try db.dbQueue.write { try block.insert($0) }

    let results = try WeekFinisher.daysNeedingReview(db: db, weekStart: monday, targetHours: 8, calendar: calendar)

    #expect(results.contains { calendar.isDate($0.day, inSameDayAs: saturday) })
}

@Test func daysNeedingReviewIncludesIncompleteWeekdays() throws {
    let db = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let monday = day("2026-08-24 00:00")
    let tuesday = day("2026-08-25 00:00")

    let results = try WeekFinisher.daysNeedingReview(db: db, weekStart: monday, targetHours: 8, calendar: calendar)

    #expect(results.contains { calendar.isDate($0.day, inSameDayAs: monday) })
    #expect(results.contains { calendar.isDate($0.day, inSameDayAs: tuesday) })
    #expect(results.count == 5) // Mon-Fri incomplete; empty Sat/Sun excluded
}
