import Foundation

/// Single source of truth for rendering an hours value as "Xh Ym", used by
/// the app, widget, and CLI so a stored duration reads the same everywhere
/// a human sees it — regardless of unit used to store or edit it.
public enum DurationFormatter {
    /// Formats `hours` (a decimal number of hours, possibly negative) as
    /// "Xh Ym". Negative values keep the sign on the whole label rather
    /// than splitting it across the hour and minute components, so -0.2
    /// renders as "-0h 12m" rather than the nonsensical "-0h -12m".
    public static func hoursMinutes(_ hours: Double) -> String {
        let sign = hours < 0 ? "-" : ""
        let totalMinutes = Int((abs(hours) * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(sign)\(h)h \(m)m"
    }
}
