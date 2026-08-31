import SwiftUI

extension Notification.Name {
    static let vaireDataChanged = Notification.Name("com.martinmatousek.vaire.dataChanged.local")
}

@main
struct VaireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
