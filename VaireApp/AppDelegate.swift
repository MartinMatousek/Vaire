import AppKit
import WidgetKit
import VaireKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        StatusBarController.shared.start()
        LiveImportCoordinator.shared.start()
        DailyReviewScheduler.shared.start()

        // The CLI (used by Claude Code hooks) has no app bundle context and
        // can't call WidgetCenter itself, so it posts a Darwin notification
        // after every write. Relay it into a widget reload and an
        // in-process notification the status bar icon observes for an
        // immediate refresh instead of waiting on its own poll interval.
        DataChangeNotifier.observe {
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .vaireDataChanged, object: nil)
        }
    }
}
