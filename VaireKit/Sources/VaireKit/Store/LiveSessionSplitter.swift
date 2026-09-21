import Foundation

/// One day-column's share of a still-running session.
public struct LiveSessionSegment: Equatable, Sendable {
    public let hours: Double
    public let dayIndex: Int
    public let dayCount: Int

    public init(hours: Double, dayIndex: Int, dayCount: Int) {
        self.hours = hours
        self.dayIndex = dayIndex
        self.dayCount = dayCount
    }
}

/// Splits a still-running session's elapsed hours into per-day-column
/// portions capped at `targetHours` each, so a session left running
/// across real wall-clock days doesn't balloon a single column (or, via
/// WeekView's `gridHours`, the whole week's ruler) to match its raw
/// elapsed time.
///
/// Every real 24h the session has been open only counts as `targetHours`
/// of work — e.g. a session left running for 46h counts as
/// 46/24 * 8 ≈ 15h20m, not 46h — since a session sitting open overnight
/// or over a weekend was never actually worked the whole time it was
/// open. That counted total is then split into `targetHours`-sized
/// segments across day columns, matching the day columns' existing
/// "stacked accumulated length" layout (they are not a literal 24h
/// clock, so this split has no notion of which segment falls on which
/// literal calendar day — WeekView places segment N in the Nth column
/// after the session's start day). It is presentational only — nothing
/// here is persisted, and it intentionally disagrees with
/// `DailySummary`, which clips a stopped `Block`'s real start/end
/// against actual day boundaries.
public enum LiveSessionSplitter {
    /// - Parameters:
    ///   - elapsedHours: real wall-clock time since the session started.
    ///   - targetHours: max hours to show in a single column, and also
    ///     the hours counted per full real 24h elapsed (the day's 8h
    ///     work target elsewhere in WeekView).
    ///   - minHours: floor applied only to the first segment, so a
    ///     just-started session still renders as one visible sliver
    ///     instead of nothing.
    public static func segments(elapsedHours: Double, targetHours: Double, minHours: Double) -> [LiveSessionSegment] {
        guard targetHours > 0 else {
            return [LiveSessionSegment(hours: max(elapsedHours, minHours), dayIndex: 0, dayCount: 1)]
        }

        let clamped = max(countedHours(elapsedHours: elapsedHours, targetHours: targetHours), minHours)
        let dayCount = max(1, Int((clamped / targetHours).rounded(.up)))

        return (0..<dayCount).map { index in
            let remaining = clamped - Double(index) * targetHours
            let hours = min(targetHours, remaining)
            return LiveSessionSegment(hours: hours, dayIndex: index, dayCount: dayCount)
        }
    }

    /// The compressed total (`elapsedHours / 24 * targetHours`) that
    /// `segments` sums to — exposed so the multi-day label can show the
    /// same "what's actually being counted" number as the segments
    /// themselves, rather than raw wall-clock elapsed time.
    public static func countedHours(elapsedHours: Double, targetHours: Double) -> Double {
        max(elapsedHours, 0) / 24 * targetHours
    }
}
