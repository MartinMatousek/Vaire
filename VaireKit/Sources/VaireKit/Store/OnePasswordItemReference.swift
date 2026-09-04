import Foundation

/// The user's choice of whether Vaire should autofill the Trask/Keycloak
/// login via 1Password, and which item to use. File-based like
/// `AppLanguage`, not a DB table — this is a single global setting, and the
/// two halves (enabled flag, chosen item) are read/written independently so
/// disabling autofill doesn't forget which item was chosen (re-enabling
/// remembers it). The item is referenced by its immutable 1Password UUID,
/// never its title, for pairing — `itemTitle` below is only a cached label
/// for display, so it may go stale after a rename in 1Password.app; it's
/// re-resolved whenever the picker itself is opened. Caching it here avoids
/// calling `op` (and its biometric/Automation prompt) just to show Settings.
public struct OnePasswordSetting: Equatable, Sendable {
    public var isEnabled: Bool
    public var itemId: String?
    public var itemTitle: String?

    public init(isEnabled: Bool = false, itemId: String? = nil, itemTitle: String? = nil) {
        self.isEnabled = isEnabled
        self.itemId = itemId
        self.itemTitle = itemTitle
    }

    public static func current() -> OnePasswordSetting {
        guard let path = try? SharedStorage.onePasswordSettingPath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return OnePasswordSetting()
        }
        let lines = raw.components(separatedBy: "\n")
        let isEnabled = lines.first == "enabled"
        let itemId = lines.count > 1 ? lines[1] : nil
        let itemTitle = lines.count > 2 ? lines[2] : nil
        return OnePasswordSetting(
            isEnabled: isEnabled,
            itemId: (itemId?.isEmpty ?? true) ? nil : itemId,
            itemTitle: (itemTitle?.isEmpty ?? true) ? nil : itemTitle
        )
    }

    public static func set(_ setting: OnePasswordSetting) throws {
        let path = try SharedStorage.onePasswordSettingPath()
        let contents = "\(setting.isEnabled ? "enabled" : "disabled")\n\(setting.itemId ?? "")\n\(setting.itemTitle ?? "")"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
