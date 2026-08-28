import Foundation

public enum SharedStorage {
    public static let appGroupIdentifier = "group.com.martinmatousek.timekeeper"

    /// Path to the shared SQLite database inside the App Group container,
    /// so the main app and the widget extension read and write the same
    /// data instead of maintaining separate copies.
    public static func databasePath() -> String {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            fatalError("App Group container '\(appGroupIdentifier)' is unavailable — check entitlements.")
        }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return containerURL.appendingPathComponent("timekeeper.sqlite").path
    }
}
