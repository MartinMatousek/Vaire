import SwiftUI
import TimeKeeperKit

@main
struct TimeKeeperApp: App {
    var body: some Scene {
        MenuBarExtra("TimeKeeper", systemImage: "clock") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
