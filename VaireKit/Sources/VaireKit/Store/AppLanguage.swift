import Foundation

public enum AppLanguage: String, Sendable {
    case cs
    case en

    /// English is the default for anyone without a saved preference,
    /// including existing installs upgrading from before this setting
    /// existed — the app itself is meant to read as an English-first
    /// project now, with Czech as an explicit opt-in via Settings.
    public static let `default`: AppLanguage = .en

    public static func current() -> AppLanguage {
        guard let path = try? SharedStorage.languagePath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .default
        }
        return AppLanguage(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .default
    }

    public static func set(_ language: AppLanguage) throws {
        let path = try SharedStorage.languagePath()
        try language.rawValue.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
