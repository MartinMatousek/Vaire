import Foundation

/// The user-configured path to a local clone's `VaireUpload/` folder.
/// File-based like `TimesheetURLSetting` — a single global preference, not
/// a DB row. Exists because the Homebrew cask ships only Vaire.app: the
/// Node/Playwright scripts under `VaireUpload/` live in the source repo and
/// aren't bundled into the app, so `TimesheetScraper`'s compile-time
/// `#filePath` fallback resolves to whichever machine built the app — the
/// original author's, not the installing user's. Users running from a
/// local Xcode/source build need not touch this at all: an unset value
/// falls back to the `#filePath`-derived location, which is correct there.
public enum VaireUploadDirectorySetting {
    public static func current() -> String? {
        guard let path = try? SharedStorage.vaireUploadDirectoryPath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func set(_ path: String?) throws {
        let filePath = try SharedStorage.vaireUploadDirectoryPath()
        try (path ?? "").write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Pure resolution so the logic is testable without touching disk:
    /// the configured path (trimmed, tilde-expanded) when non-blank,
    /// otherwise `defaultDirectory` (the `#filePath`-derived location).
    public static func resolve(configured: String?, defaultDirectory: URL) -> URL {
        guard let configured else { return defaultDirectory }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultDirectory }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    public static func resolvedDirectory(defaultDirectory: URL) -> URL {
        resolve(configured: current(), defaultDirectory: defaultDirectory)
    }
}
