import Foundation

/// The user's choice of whether Vaire should autofill the Trask/Keycloak
/// login via 1Password, and which item to use. File-based like
/// `AppLanguage`, not a DB table — this is a single global setting, and the
/// two halves (enabled flag, chosen item) are read/written independently so
/// disabling autofill doesn't forget which item was chosen (re-enabling
/// remembers it). The item is referenced by its immutable 1Password UUID,
/// never its title, so renaming the item in 1Password.app doesn't break the
/// pairing.
public struct OnePasswordSetting: Equatable, Sendable {
    public var isEnabled: Bool
    public var itemId: String?

    public init(isEnabled: Bool = false, itemId: String? = nil) {
        self.isEnabled = isEnabled
        self.itemId = itemId
    }

    public static func current() -> OnePasswordSetting {
        guard let path = try? SharedStorage.onePasswordSettingPath(),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return OnePasswordSetting()
        }
        let lines = raw.components(separatedBy: "\n")
        let isEnabled = lines.first == "enabled"
        let itemId = lines.count > 1 ? lines[1] : nil
        return OnePasswordSetting(isEnabled: isEnabled, itemId: (itemId?.isEmpty ?? true) ? nil : itemId)
    }

    public static func set(_ setting: OnePasswordSetting) throws {
        let path = try SharedStorage.onePasswordSettingPath()
        let contents = "\(setting.isEnabled ? "enabled" : "disabled")\n\(setting.itemId ?? "")"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
