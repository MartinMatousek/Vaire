import AppKit
import SwiftUI
import VaireKit

@MainActor
final class WeekWindowController {
    static let shared = WeekWindowController()

    private var window: NSWindow?
    private let windowUndoManager = UndoManager()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // The window is reused (isReleasedWhenClosed = false), so
            // SwiftUI's .onAppear never fires again on a re-show — only
            // AppKit's window visibility changed, not the view's presence
            // in the hierarchy. Without this, reopening the window after
            // it was closed could show data as stale as whenever it was
            // last shown, until some unrelated write happened to post this
            // same notification (confirmed live: repeatedly clicking
            // other buttons eventually forced a refresh by accident).
            // WeekView already listens for this to reload.
            NotificationCenter.default.post(name: .vaireDataChanged, object: nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.weekWindowTitle
        let hostedView = WeekView().environment(\.weekUndoManager, windowUndoManager)
        window.contentView = NSHostingView(rootView: hostedView)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Confirmed live: a per-day button gated by
        // `.disabled(allProjectsSorted.isEmpty)` can be silently inert on
        // the very first click after launch — the window becomes
        // interactive before WeekView's own .onAppear(perform: reload)
        // has populated `projects`. Post the same notification the reused-
        // window path above already relies on, so WeekView reloads
        // deterministically rather than racing its own .onAppear.
        NotificationCenter.default.post(name: .vaireDataChanged, object: nil)
    }
}
