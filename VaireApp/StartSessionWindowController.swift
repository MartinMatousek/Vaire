import AppKit
import SwiftUI
import VaireKit

/// Presents `StartSessionEditorView` in a standalone window for a
/// `vaire://start-session?session=<id>&cwd=<path>` URL, so a Claude Code
/// SessionStart hook can get the app's real note+estimate form instead of
/// a sequence of AppleScript yes/no prompts. The hook waits on the JSON
/// file this writes via `SharedStorage.startResultPath`.
@MainActor
final class StartSessionWindowController: NSObject, NSWindowDelegate {
    static let shared = StartSessionWindowController()

    private var window: NSWindow?
    private var currentSessionId: String?
    private var finished = false

    func presentEditor(sessionId: String, cwd: String) {
        window?.close()
        currentSessionId = sessionId
        finished = false

        // is-hooks-enabled (checked by the hook before opening this URL)
        // implies a project row already exists for this cwd.
        let project = try? Project.find(byPath: cwd, db: AppEnvironment.db)
        let projectName = project?.name ?? cwd

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.logTimeFor(projectName)
        window.contentView = NSHostingView(rootView: StartSessionEditorView(projectName: projectName) { [weak self] outcome in
            self?.finish(sessionId: sessionId, outcome: outcome)
        })
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(sessionId: String, outcome: StartSessionOutcome) {
        finished = true
        let result: StartRequestResult
        switch outcome {
        case .started(let note, let estimateMinutes):
            result = StartRequestResult(sessionId: sessionId, outcome: .started, note: note, estimateMinutes: estimateMinutes)
        case .declined:
            result = StartRequestResult(sessionId: sessionId, outcome: .declined)
        }
        writeResult(result)
        window?.close()
    }

    private func writeResult(_ result: StartRequestResult) {
        guard let path = try? SharedStorage.startResultPath(forSessionId: result.sessionId),
              let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished, let currentSessionId else { return }
        writeResult(StartRequestResult(sessionId: currentSessionId, outcome: .declined))
    }
}
