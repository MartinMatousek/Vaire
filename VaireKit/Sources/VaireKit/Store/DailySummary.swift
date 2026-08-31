import Foundation
import GRDB

public struct ProjectDayTotal: Equatable, Sendable {
    public let project: Project
    public let hours: Double
}

public enum DailySummary {
    /// Total hours across all projects for the given calendar day, summing
    /// each block's duration clipped to the day's bounds.
    public static func totalHours(db: AppDatabase, day: Date, calendar: Calendar = .current) throws -> Double {
        let (dayStart, dayEnd) = dayBounds(for: day, calendar: calendar)

        return try db.dbQueue.read { conn in
            let blocks = try Block
                .filter(Column("start") < dayEnd && Column("end") > dayStart)
                .fetchAll(conn)

            let seconds = blocks.reduce(0.0) { total, block in
                let clippedStart = max(block.start, dayStart)
                let clippedEnd = min(block.end, dayEnd)
                return total + max(0, clippedEnd.timeIntervalSince(clippedStart))
            }
            return seconds / 3600
        }
    }

    public static func perProjectTotals(db: AppDatabase, day: Date, calendar: Calendar = .current) throws -> [ProjectDayTotal] {
        let (dayStart, dayEnd) = dayBounds(for: day, calendar: calendar)

        return try db.dbQueue.read { conn in
            let projects = try Project.fetchAll(conn)
            var totals: [ProjectDayTotal] = []

            for project in projects {
                let blocks = try Block
                    .filter(Column("projectId") == project.id)
                    .filter(Column("start") < dayEnd && Column("end") > dayStart)
                    .fetchAll(conn)

                let seconds = blocks.reduce(0.0) { total, block in
                    let clippedStart = max(block.start, dayStart)
                    let clippedEnd = min(block.end, dayEnd)
                    return total + max(0, clippedEnd.timeIntervalSince(clippedStart))
                }
                if seconds > 0 {
                    totals.append(ProjectDayTotal(project: project, hours: seconds / 3600))
                }
            }
            return totals
        }
    }

    /// Today's blocks for a single project, most recent first — used to
    /// offer "resume this one" when starting a timer on a project that
    /// already has entries today, instead of always creating a new block.
    public static func todaysBlocks(db: AppDatabase, projectId: UUID, day: Date = .now, calendar: Calendar = .current) throws -> [Block] {
        let (dayStart, dayEnd) = dayBounds(for: day, calendar: calendar)

        return try db.dbQueue.read { conn in
            try Block
                .filter(Column("projectId") == projectId)
                .filter(Column("start") < dayEnd && Column("end") > dayStart)
                .order(Column("start").desc)
                .fetchAll(conn)
        }
    }

    private static func dayBounds(for day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}
