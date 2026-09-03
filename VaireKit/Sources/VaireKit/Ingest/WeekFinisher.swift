import Foundation

public enum WeekFinisher {
    /// The days of the week starting at `weekStart` that still need
    /// attention: any weekday not yet at target, plus a weekend day only if
    /// it already has some logged time (mirrors `WeekView.dayColumn`'s
    /// `isWorkday` check — an empty weekend day is never "behind").
    public static func daysNeedingReview(
        db: AppDatabase,
        weekStart: Date,
        targetHours: Double = 8,
        calendar: Calendar = .current
    ) throws -> [DayStatus] {
        var results: [DayStatus] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let status = try DayFinisher.status(db: db, day: date, targetHours: targetHours, calendar: calendar)
            guard !status.isComplete else { continue }

            let isWorkday = !calendar.isDateInWeekend(date)
            guard isWorkday || status.loggedHours > 0 else { continue }

            results.append(status)
        }
        return results
    }
}
