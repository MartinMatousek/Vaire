import Foundation

/// The user-configured root URL of their external timesheet (e.g.
/// "https://my.trask.cz/"). File-based like `AppLanguage`/`OnePasswordSetting`
/// — a single global preference, not a DB row. Deliberately has no built-in
/// default: the timesheet is specific to the user's own organization, so
/// shipping one real organization's URL as a fallback would just be this
/// codebase's branding by another name. Upload/scrape/settings flows treat
/// an empty value as "not configured yet" and prompt the user to set it.
public enum TimesheetURLSetting {
    public static func current() -> String? {
        guard let path = try? SharedStorage.timesheetURLPath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func set(_ url: String?) throws {
        let path = try SharedStorage.timesheetURLPath()
        try (url ?? "").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
