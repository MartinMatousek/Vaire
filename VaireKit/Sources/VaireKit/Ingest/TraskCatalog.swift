import Foundation
import GRDB

/// One entry in the parsed output of `VaireUpload/src/scrapeCatalog.mjs` —
/// a Trask project label paired with its scraped task labels.
public struct TraskScrapedProject: Equatable, Sendable {
    public let label: String
    public let taskLabels: [String]

    public init(label: String, taskLabels: [String]) {
        self.label = label
        self.taskLabels = taskLabels
    }
}

/// What a fresh scrape changed relative to what was already cached, so the
/// UI can tell the user what happened rather than silently swallowing it.
public struct TraskCatalogDiff: Equatable, Sendable {
    public let newProjectLabels: [String]
    public let newTaskLabels: [String]
    public let deactivatedProjectLabels: [String]
    public let deactivatedTaskLabels: [String]

    public init(
        newProjectLabels: [String] = [],
        newTaskLabels: [String] = [],
        deactivatedProjectLabels: [String] = [],
        deactivatedTaskLabels: [String] = []
    ) {
        self.newProjectLabels = newProjectLabels
        self.newTaskLabels = newTaskLabels
        self.deactivatedProjectLabels = deactivatedProjectLabels
        self.deactivatedTaskLabels = deactivatedTaskLabels
    }
}

/// A Vaire project's pairing to Trask pointing at a project or task that no
/// longer exists (or is no longer active) in the cached catalog.
public enum TraskPairingIssue: Equatable, Sendable {
    case projectInactiveOrMissing
    case defaultTaskInactiveOrMissing
}

public enum TraskCatalogError: Error {
    /// The project label in `traskProject.id` has no trailing token to use
    /// as a stable id — see `projectId(fromLabel:)`.
    case unparsableProjectLabel(String)
}

public enum TraskCatalog {
    /// Derives a stable id for a Trask project from its scraped label. Real
    /// Trask labels look like "ČEZ Prodej - Produkty a KVK - FY27 - ET97" —
    /// confirmed live that the client/fiscal-year prefix changes yearly but
    /// the trailing token (here "ET97") stays put, so that token is the id;
    /// the rest of the label is stored only for display.
    public static func projectId(fromLabel label: String) throws -> String {
        guard let lastComponent = label.split(separator: "-").last else {
            throw TraskCatalogError.unparsableProjectLabel(label)
        }
        let trimmed = lastComponent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TraskCatalogError.unparsableProjectLabel(label)
        }
        return trimmed
    }

    /// Upserts the freshly scraped catalog into `traskProject`/`traskTask`,
    /// deactivating any row that used to be active but is missing from this
    /// scrape (never deletes — a Vaire project may already be paired to
    /// that row, and deleting it would silently orphan the pairing instead
    /// of surfacing it via `validatePairing`). Reactivates a row that
    /// reappears in a later scrape after having been deactivated.
    @discardableResult
    public static func refresh(db: AppDatabase, scraped: [TraskScrapedProject]) throws -> TraskCatalogDiff {
        try db.dbQueue.write { conn in
            let existingProjects = try TraskProject.fetchAll(conn)
            let existingProjectsById = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.id, $0) })
            let existingTasks = try TraskTask.fetchAll(conn)
            let existingTasksById = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })

            var seenProjectIds: Set<String> = []
            var seenTaskIds: Set<String> = []
            var newProjectLabels: [String] = []
            var newTaskLabels: [String] = []

            for entry in scraped {
                let projectId = try projectId(fromLabel: entry.label)
                seenProjectIds.insert(projectId)

                if existingProjectsById[projectId] == nil {
                    newProjectLabels.append(entry.label)
                }
                var project = existingProjectsById[projectId] ?? TraskProject(id: projectId, label: entry.label)
                project.label = entry.label
                project.active = true
                try project.save(conn)

                for taskLabel in entry.taskLabels {
                    let taskId = TraskTask.makeId(traskProjectId: projectId, label: taskLabel)
                    seenTaskIds.insert(taskId)

                    if existingTasksById[taskId] == nil {
                        newTaskLabels.append(taskLabel)
                    }
                    var task = existingTasksById[taskId]
                        ?? TraskTask(id: taskId, traskProjectId: projectId, label: taskLabel)
                    task.label = taskLabel
                    task.active = true
                    try task.save(conn)
                }
            }

            var deactivatedProjectLabels: [String] = []
            for project in existingProjects where project.active && !seenProjectIds.contains(project.id) {
                var updated = project
                updated.active = false
                try updated.save(conn)
                deactivatedProjectLabels.append(project.label)
            }

            var deactivatedTaskLabels: [String] = []
            for task in existingTasks where task.active && !seenTaskIds.contains(task.id) {
                var updated = task
                updated.active = false
                try updated.save(conn)
                deactivatedTaskLabels.append(task.label)
            }

            return TraskCatalogDiff(
                newProjectLabels: newProjectLabels,
                newTaskLabels: newTaskLabels,
                deactivatedProjectLabels: deactivatedProjectLabels,
                deactivatedTaskLabels: deactivatedTaskLabels
            )
        }
    }

    /// Checks whether a Vaire project's Trask pairing still points at an
    /// active project and (if set) an active default task. Returns nil when
    /// the pairing is sound or the project has no Trask pairing at all —
    /// "not paired yet" is a valid, unremarkable state, distinct from "was
    /// paired, now stale."
    public static func validatePairing(db: AppDatabase, project: Project) throws -> TraskPairingIssue? {
        guard let traskProjectId = project.traskProjectId else { return nil }

        return try db.dbQueue.read { conn in
            guard let traskProject = try TraskProject.fetchOne(conn, key: traskProjectId), traskProject.active else {
                return .projectInactiveOrMissing
            }

            if let defaultTraskTaskId = project.defaultTraskTaskId {
                guard let task = try TraskTask.fetchOne(conn, key: defaultTraskTaskId), task.active else {
                    return .defaultTaskInactiveOrMissing
                }
            }

            return nil
        }
    }
}
