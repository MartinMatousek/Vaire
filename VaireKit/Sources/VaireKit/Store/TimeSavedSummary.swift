import Foundation
import GRDB

public struct TimeSavedEntry: Equatable, Sendable {
    public let block: Block
    public let project: Project
    public let actualHours: Double
    public let estimatedHours: Double
    public var savedHours: Double { estimatedHours - actualHours }
}

public struct TimeSavedWeekSummary: Sendable {
    public let entries: [TimeSavedEntry]
    public var totalActualHours: Double { entries.reduce(0) { $0 + $1.actualHours } }
    public var totalEstimatedHours: Double { entries.reduce(0) { $0 + $1.estimatedHours } }
    public var totalSavedHours: Double { totalEstimatedHours - totalActualHours }
}

public enum TimeSavedSummary {
    /// All blocks with a recorded "estimated without AI" value, in the
    /// week containing `day`. Only blocks Claude itself estimated show up
    /// here — manual entries never have this field, so they're excluded
    /// rather than shown with a misleading zero saved.
    public static func weekSummary(db: AppDatabase, day: Date = .now, calendar: Calendar = .current) throws -> TimeSavedWeekSummary {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: day) else {
            return TimeSavedWeekSummary(entries: [])
        }

        return try db.dbQueue.read { conn in
            let blocks = try Block
                .filter(Column("estimatedHoursWithoutAI") != nil)
                .filter(Column("start") < weekInterval.end && Column("end") > weekInterval.start)
                .order(Column("start").desc)
                .fetchAll(conn)

            let projectsById = Dictionary(
                uniqueKeysWithValues: try Project.fetchAll(conn).map { ($0.id, $0) }
            )

            let entries = blocks.compactMap { block -> TimeSavedEntry? in
                guard let estimate = block.estimatedHoursWithoutAI,
                      let project = projectsById[block.projectId] else { return nil }
                return TimeSavedEntry(
                    block: block,
                    project: project,
                    actualHours: block.duration / 3600,
                    estimatedHours: estimate
                )
            }

            return TimeSavedWeekSummary(entries: entries)
        }
    }
}
