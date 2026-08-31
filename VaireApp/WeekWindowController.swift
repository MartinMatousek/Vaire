import AppKit
import SwiftUI

@MainActor
final class WeekWindowController {
    static let shared = WeekWindowController()

    private var window: NSWindow?
    private let windowUndoManager = UndoManager()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vaire — Týden"
        let hostedView = WeekView().environment(\.weekUndoManager, windowUndoManager)
        window.contentView = NSHostingView(rootView: hostedView)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
