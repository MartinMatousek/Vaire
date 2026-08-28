import Foundation

public enum SharedStorageError: Error {
    case containerUnavailable
}

public enum SharedStorage {
    public static let appGroupIdentifier = "group.com.martinmatousek.timekeeper"

    /// Path to the shared SQLite database inside the App Group container,
    /// so the main app and the widget extension read and write the same
    /// data instead of maintaining separate copies. Throws instead of
    /// crashing when the container isn't mounted yet (e.g. Xcode's widget
    /// preview host runs before entitlements are fully resolved) — callers
    /// should fall back to an empty/placeholder state rather than take the
    /// whole preview or widget host down with them.
    public static func databasePath() throws -> String {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedStorageError.containerUnavailable
        }
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return containerURL.appendingPathComponent("timekeeper.sqlite").path
    }
}
