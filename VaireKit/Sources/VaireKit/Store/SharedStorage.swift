import Foundation

public enum SharedStorageError: Error {
    case containerUnavailable
}

public enum SharedStorage {
    /// Path to the shared SQLite database under the user's Application
    /// Support directory, so the main app, the widget extension, and the
    /// CLI all read and write the same data instead of maintaining
    /// separate copies. Deliberately not an App Group container: App
    /// Groups require a provisioning-profile-backed signing identity, which
    /// only works on machines registered to the same Apple Developer team —
    /// a plain per-user directory works ad-hoc-signed on any Mac. Throws
    /// instead of crashing when the directory can't be created — callers
    /// should fall back to an empty/placeholder state rather than take the
    /// whole preview or widget host down with them.
    public static func databasePath() throws -> String {
        try directory().appendingPathComponent("vaire.sqlite").path
    }

    /// Path to the plain-text file holding the UI language ("cs" or "en").
    /// Not part of the SQLite store because hook scripts (bash, no SQLite
    /// client) need to read it too, to pick which language to show their
    /// AppleScript dialogs in.
    public static func languagePath() throws -> String {
        try directory().appendingPathComponent("language").path
    }

    /// Path to the plain-text file holding the 1Password timesheet-login
    /// setting ("enabled\n<item-uuid-or-empty>"). File-based rather than a
    /// DB row since it's a single global preference, same reasoning as
    /// languagePath — and so it stays legible/editable without a SQLite
    /// client if something ever needs to reset it by hand.
    public static func onePasswordSettingPath() throws -> String {
        try directory().appendingPathComponent("onePasswordSetting").path
    }

    /// Path to the plain-text file holding the configured timesheet root
    /// URL (e.g. "https://my.trask.cz/"). Empty/missing until the user sets
    /// it in Settings — Vaire has no built-in default, since the timesheet
    /// it talks to is specific to the user's own organization.
    public static func timesheetURLPath() throws -> String {
        try directory().appendingPathComponent("timesheetURL").path
    }

    /// Path to the JSON result file for one `vaire://edit-block` request,
    /// one file per block id so a stale/timed-out request from a previous
    /// run can't be misread as the current one's answer. Written by the
    /// app on Save/Discard/Continue/window-close, polled by the hook that
    /// opened the URL.
    public static func editResultPath(forBlockId id: UUID) throws -> String {
        let directory = try directory().appendingPathComponent("edit-results", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(id.uuidString).json").path
    }

    /// Path to the JSON result file for one `vaire://start-session` request,
    /// one file per Claude Code session id, mirroring `editResultPath`.
    public static func startResultPath(forSessionId sessionId: String) throws -> String {
        let directory = try directory().appendingPathComponent("start-results", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(sessionId).json").path
    }

    private static func directory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SharedStorageError.containerUnavailable
        }
        let directory = appSupport.appendingPathComponent("Vaire", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
