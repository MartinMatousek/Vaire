import Foundation
import WidgetKit
import VaireKit

@MainActor
final class LiveImportCoordinator {
    static let shared = LiveImportCoordinator()

    private var watcher: ClaudeProjectsWatcher?

    func start() {
        let claudeProjectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: claudeProjectsDir.path) else { return }

        // FSEventStream only reports events from the moment it starts
        // (kFSEventStreamEventIdSinceNow) — a session file that was already
        // being written before this launch (e.g. Vaire restarted mid-day)
        // won't trigger a reimport until it's next appended to, so today's
        // hours read as 0h 0m until that happens. Reimport every session
        // file already on disk once up front so a restart doesn't lose
        // already-logged time.
        reimportAllExisting(in: claudeProjectsDir)

        let watcher = ClaudeProjectsWatcher { [weak self] changedPath in
            Task { @MainActor in
                self?.reimport(sessionFilePath: changedPath)
            }
        }
        watcher.start(watching: claudeProjectsDir.path)
        self.watcher = watcher
    }

    private func reimportAllExisting(in directory: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            reimport(sessionFilePath: url.path)
        }
    }

    private func reimport(sessionFilePath: String) {
        let sessionId = URL(fileURLWithPath: sessionFilePath).deletingPathExtension().lastPathComponent
        guard let declined = try? AgentSessionRecorder.isDeclined(db: AppEnvironment.db, sessionId: sessionId),
              !declined else { return }

        guard let turns = try? ClaudeSessionImporter.parseTurns(contentsOf: URL(fileURLWithPath: sessionFilePath)),
              let cwd = turns.last?.cwd else { return }

        guard let project = try? Project.find(byPath: cwd, db: AppEnvironment.db), project.hooksEnabled else { return }

        let sessionizedBlocks = SessionizeEngine.sessionize(turns: turns)
        let candidates = sessionizedBlocks.map {
            CandidateBlock(projectId: project.id, start: $0.start, end: $0.end, source: .claudeSession)
        }
        let merged = BlockMerger.merge(candidates)
        try? ReimportGuard.reconcile(db: AppEnvironment.db, projectId: project.id, candidates: merged)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
