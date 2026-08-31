import Foundation
import GRDB

public enum ManDayCalculator {
    public static func manDays(hours: Double, hoursPerDay: Double) -> Double {
        guard hoursPerDay > 0 else { return 0 }
        return hours / hoursPerDay
    }

    public static func hours(manDays: Double, hoursPerDay: Double) -> Double {
        manDays * hoursPerDay
    }

    /// Total man-days worked on a project across all recorded blocks.
    public static func totalManDays(db: AppDatabase, project: Project) throws -> Double {
        let totalHours = try db.dbQueue.read { conn in
            try Block
                .filter(Column("projectId") == project.id)
                .fetchAll(conn)
                .reduce(0.0) { $0 + $1.duration / 3600 }
        }
        return manDays(hours: totalHours, hoursPerDay: project.mdHoursPerDay)
    }
}
