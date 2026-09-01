import AppKit
import SwiftUI
import VaireKit
import GRDB

/// Presents `StoppedBlockEditorView` in a standalone window for a block
/// named by a `vaire://edit-block?id=<uuid>` URL, so a Claude Code hook can
/// get the app's real edit form instead of an AppleScript text prompt. The
/// hook waits on the JSON file this writes via `SharedStorage.editResultPath`.
@MainActor
final class EditBlockWindowController: NSObject, NSWindowDelegate {
    static let shared = EditBlockWindowController()

    private var window: NSWindow?
    private var currentBlockId: UUID?
    private var finished = false

    func presentEditor(forBlockId id: UUID) {
        window?.close()
        currentBlockId = id
        finished = false

        let block = try? AppEnvironment.db.dbQueue.read { try Block.fetchOne($0, key: id) }
        guard let block else {
            writeResult(EditRequestResult(blockId: id, outcome: .notFound))
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.editTimeAndDescription
        window.contentView = NSHostingView(rootView: StoppedBlockEditorView(block: block, showsContinue: false) { [weak self] outcome in
            self?.finish(blockId: id, outcome: outcome)
        })
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(blockId: UUID, outcome: StoppedBlockOutcome) {
        finished = true
        let result: EditRequestResult
        switch outcome {
        case .saved(let durationMinutes, let note, let estimateMinutes):
            result = EditRequestResult(blockId: blockId, outcome: .saved, durationMinutes: durationMinutes, note: note, estimateMinutes: estimateMinutes)
        case .discarded:
            result = EditRequestResult(blockId: blockId, outcome: .discarded)
        case .resumed:
            result = EditRequestResult(blockId: blockId, outcome: .resumed)
        }
        writeResult(result)
        window?.close()
    }

    private func writeResult(_ result: EditRequestResult) {
        guard let path = try? SharedStorage.editResultPath(forBlockId: result.blockId),
              let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished, let currentBlockId else { return }
        writeResult(EditRequestResult(blockId: currentBlockId, outcome: .cancelled))
    }
}
