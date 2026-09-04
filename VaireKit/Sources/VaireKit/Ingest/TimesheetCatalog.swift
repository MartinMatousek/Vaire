import Foundation
import GRDB

/// One entry in the parsed output of `VaireUpload/src/scrapeCatalog.mjs` —
/// an external timesheet project label paired with its scraped task labels.
public struct TimesheetScrapedProject: Equatable, Sendable {
    public let label: String
    public let taskLabels: [String]

    public init(label: String, taskLabels: [String]) {
        self.label = label
        self.taskLabels = taskLabels
    }
}

/// What a fresh scrape changed relative to what was already cached, so the
/// UI can tell the user what happened rather than silently swallowing it.
public struct TimesheetCatalogDiff: Equatable, Sendable {
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

/// A Vaire project's pairing to the external timesheet pointing at a project
/// or task that no longer exists (or is no longer active) in the cached
/// catalog.
public enum TimesheetPairingIssue: Equatable, Sendable {
    case projectInactiveOrMissing
    case defaultTaskInactiveOrMissing
}

public enum TimesheetCatalogError: Error {
    /// The project label in `timesheetProject.id` has no trailing token to
    /// use as a stable id — see `projectId(fromLabel:)`.
    case unparsableProjectLabel(String)
}

public enum TimesheetCatalog {
    /// Derives a stable id for a timesheet project from its scraped label.
    /// Real labels look like "ČEZ Prodej - Produkty a KVK - FY27 - ET97" —
    /// confirmed live that the client/fiscal-year prefix changes yearly but
    /// the trailing token (here "ET97") stays put, so that token is the id;
    /// the rest of the label is stored only for display.
    public static func projectId(fromLabel label: String) throws -> String {
        guard let lastComponent = label.split(separator: "-").last else {
            throw TimesheetCatalogError.unparsableProjectLabel(label)
        }
        let trimmed = lastComponent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TimesheetCatalogError.unparsableProjectLabel(label)
        }
        return trimmed
    }

    /// Upserts the freshly scraped catalog into
    /// `timesheetProject`/`timesheetTask`, deactivating any row that used to
    /// be active but is missing from this scrape (never deletes — a Vaire
    /// project may already be paired to that row, and deleting it would
    /// silently orphan the pairing instead of surfacing it via
    /// `validatePairing`). Reactivates a row that reappears in a later
    /// scrape after having been deactivated.
    @discardableResult
    public static func refresh(db: AppDatabase, scraped: [TimesheetScrapedProject]) throws -> TimesheetCatalogDiff {
        try db.dbQueue.write { conn in
            let existingProjects = try TimesheetProject.fetchAll(conn)
            let existingProjectsById = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.id, $0) })
            let existingTasks = try TimesheetTask.fetchAll(conn)
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
                var project = existingProjectsById[projectId] ?? TimesheetProject(id: projectId, label: entry.label)
                project.label = entry.label
                project.active = true
                try project.save(conn)

                for taskLabel in entry.taskLabels {
                    let taskId = TimesheetTask.makeId(timesheetProjectId: projectId, label: taskLabel)
                    seenTaskIds.insert(taskId)

                    if existingTasksById[taskId] == nil {
                        newTaskLabels.append(taskLabel)
                    }
                    var task = existingTasksById[taskId]
                        ?? TimesheetTask(id: taskId, timesheetProjectId: projectId, label: taskLabel)
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

            return TimesheetCatalogDiff(
                newProjectLabels: newProjectLabels,
                newTaskLabels: newTaskLabels,
                deactivatedProjectLabels: deactivatedProjectLabels,
                deactivatedTaskLabels: deactivatedTaskLabels
            )
        }
    }

    /// Checks whether a Vaire project's timesheet pairing still points at an
    /// active project and (if set) an active default task. Returns nil when
    /// the pairing is sound or the project has no timesheet pairing at all
    /// — "not paired yet" is a valid, unremarkable state, distinct from
    /// "was paired, now stale."
    public static func validatePairing(db: AppDatabase, project: Project) throws -> TimesheetPairingIssue? {
        guard let timesheetProjectId = project.timesheetProjectId else { return nil }

        return try db.dbQueue.read { conn in
            guard let timesheetProject = try TimesheetProject.fetchOne(conn, key: timesheetProjectId), timesheetProject.active else {
                return .projectInactiveOrMissing
            }

            if let defaultTimesheetTaskId = project.defaultTimesheetTaskId {
                guard let task = try TimesheetTask.fetchOne(conn, key: defaultTimesheetTaskId), task.active else {
                    return .defaultTaskInactiveOrMissing
                }
            }

            return nil
        }
    }
}
