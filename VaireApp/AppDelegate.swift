import AppKit
import CoreServices
import WidgetKit
import VaireKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // MenuBarExtra has no WindowGroup scene for SwiftUI's onOpenURL to
        // attach to, so vaire:// URLs (used by the Claude Code hooks to
        // open the real edit sheet instead of an AppleScript prompt) are
        // handled via the lower-level Apple Event this delegate can see.
        // 'GURL' fourCC — Foundation/AppKit don't re-export the Carbon
        // kInternetEventClass/kAEGetURLEvent constants on this SDK, but the
        // event class and ID are both this well-known code.
        let gurlEventCode: AEEventClass = 0x4755524C
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: gurlEventCode,
            andEventID: gurlEventCode
        )

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

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let components = URLComponents(string: urlString),
              components.scheme == "vaire" else {
            NSLog("Vaire: handleGetURL received an unparseable or non-vaire:// event")
            return
        }

        switch components.host {
        case "edit-block":
            guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let blockId = UUID(uuidString: idString) else { return }
            EditBlockWindowController.shared.presentEditor(forBlockId: blockId)
        case "start-session":
            guard let sessionId = components.queryItems?.first(where: { $0.name == "session" })?.value,
                  let cwd = components.queryItems?.first(where: { $0.name == "cwd" })?.value else {
                NSLog("Vaire: start-session missing session or cwd query item")
                return
            }
            StartSessionWindowController.shared.presentEditor(sessionId: sessionId, cwd: cwd)
        default:
            NSLog("Vaire: unknown vaire:// host \(components.host ?? "nil")")
        }
    }
}
