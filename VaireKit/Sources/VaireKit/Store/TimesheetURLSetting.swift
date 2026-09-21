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
        return normalize(raw)
    }

    public static func set(_ url: String?) throws {
        let path = try SharedStorage.timesheetURLPath()
        try (normalize(url) ?? "").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Pure normalization so the logic is testable without touching disk.
    /// Confirmed live: the stored setting had been saved as a bare host
    /// ("my.trask.cz", no scheme) — `URL(string:)` on every downstream
    /// consumer (Swift and the VaireUpload Node scripts alike) either fails
    /// to parse it or silently treats it as non-matching, so the upload flow
    /// could never find or open the configured timesheet tab. Normalizing
    /// on both read and write repairs an already-bad value in place (the
    /// user never has to notice or re-type it) and stops a new bad value
    /// from ever being written.
    ///
    /// Trims whitespace; blank -> nil. A value with no scheme gets
    /// "https://" prepended (the common case: someone types just the host).
    /// An existing "http://"/"https://" scheme is left alone — http is not
    /// upgraded, since an internal-only timesheet might not have TLS. Any
    /// other scheme (or anything that still doesn't parse to a URL with a
    /// host afterward) is rejected as nil rather than guessed at.
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            candidate = trimmed
        } else if trimmed.contains("://") {
            // Some other scheme (ftp://, vaire://, ...) — not a usable
            // timesheet URL.
            return nil
        } else {
            candidate = "https://" + trimmed
        }

        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
    }
}
