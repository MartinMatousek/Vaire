import Foundation
import Testing
@testable import TimeKeeperKit

@Test func hoursToManDaysConversion() {
    #expect(ManDayCalculator.manDays(hours: 16, hoursPerDay: 8) == 2)
    #expect(ManDayCalculator.manDays(hours: 4, hoursPerDay: 8) == 0.5)
}

@Test func manDaysToHoursConversion() {
    #expect(ManDayCalculator.hours(manDays: 2, hoursPerDay: 8) == 16)
}

@Test func zeroHoursPerDayReturnsZeroInsteadOfCrashing() {
    #expect(ManDayCalculator.manDays(hours: 10, hoursPerDay: 0) == 0)
}

@Test func totalManDaysSumsAllBlocksForProject() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p", mdHoursPerDay: 8)
    try db.dbQueue.write { try project.insert($0) }

    let blockA = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 8 * 3600), source: .manual)
    let blockB = Block(projectId: project.id, start: Date(timeIntervalSince1970: 100_000), end: Date(timeIntervalSince1970: 100_000 + 4 * 3600), source: .manual)
    try db.dbQueue.write {
        try blockA.insert($0)
        try blockB.insert($0)
    }

    let totalMD = try ManDayCalculator.totalManDays(db: db, project: project)
    #expect(totalMD == 1.5)
}
