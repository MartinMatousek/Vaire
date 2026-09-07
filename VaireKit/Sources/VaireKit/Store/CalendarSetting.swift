import Foundation

/// Whether Vaire should import meetings from the user's calendar during Finish
/// Day, and which calendar to read them from. File-based like
/// `OnePasswordSetting`, not a DB row — a single global preference. Defaults
/// to disabled with `MeetingImporter.defaultCalendarTitle` as the calendar
/// name so an existing install without this file keeps working as before.
public struct CalendarSetting: Equatable, Sendable {
    public var isEnabled: Bool
    public var calendarName: String

    public init(isEnabled: Bool = false, calendarName: String = MeetingImporter.defaultCalendarTitle) {
        self.isEnabled = isEnabled
        self.calendarName = calendarName
    }

    public static func current() -> CalendarSetting {
        guard let path = try? SharedStorage.calendarSettingPath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return CalendarSetting()
        }
        let lines = raw.components(separatedBy: "\n")
        let isEnabled = lines.first == "enabled"
        let calendarName = lines.count > 1 ? lines[1] : ""
        return CalendarSetting(
            isEnabled: isEnabled,
            calendarName: calendarName.isEmpty ? MeetingImporter.defaultCalendarTitle : calendarName
        )
    }

    public static func set(_ setting: CalendarSetting) throws {
        let path = try SharedStorage.calendarSettingPath()
        let contents = "\(setting.isEnabled ? "enabled" : "disabled")\n\(setting.calendarName)"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
