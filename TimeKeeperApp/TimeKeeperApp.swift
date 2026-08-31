import SwiftUI

extension Notification.Name {
    static let timeKeeperDataChanged = Notification.Name("com.martinmatousek.timekeeper.dataChanged.local")
}

@main
struct TimeKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
