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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SharedStorageError.containerUnavailable
        }
        let directory = appSupport.appendingPathComponent("Vaire", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vaire.sqlite").path
    }
}
