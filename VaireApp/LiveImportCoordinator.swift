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

        let watcher = ClaudeProjectsWatcher { [weak self] changedPath in
            Task { @MainActor in
                self?.reimport(sessionFilePath: changedPath)
            }
        }
        watcher.start(watching: claudeProjectsDir.path)
        self.watcher = watcher
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
