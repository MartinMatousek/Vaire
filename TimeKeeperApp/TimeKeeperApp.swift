import SwiftUI
import TimeKeeperKit

@main
struct TimeKeeperApp: App {
    init() {
        LiveImportCoordinator.shared.start()
        DailyReviewScheduler.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("TimeKeeper", systemImage: "clock") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
