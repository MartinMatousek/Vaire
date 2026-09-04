import CryptoKit
import Foundation
import GRDB

/// A task under a `TimesheetProject`, scraped from that project's Task
/// dropdown. Unlike projects, tasks carry no visible stable code in the
/// timesheet's UI, so `id` is a deterministic hash of (timesheetProjectId,
/// label) rather than a natural key — sufficient to upsert by identity
/// across re-scrapes as long as the label itself doesn't change. `active`
/// follows the same convention as `TimesheetProject.active`.
public struct TimesheetTask: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var timesheetProjectId: String
    public var label: String
    public var active: Bool

    public init(id: String, timesheetProjectId: String, label: String, active: Bool = true) {
        self.id = id
        self.timesheetProjectId = timesheetProjectId
        self.label = label
        self.active = active
    }

    public static let databaseTableName = "timesheetTask"

    /// Deterministic id derived from the project id and task label, so the
    /// same (project, task) pair always resolves to the same row across
    /// re-scrapes without the external timesheet ever exposing a real task
    /// identifier. Uses SHA256 rather than `Hasher` — `Hasher`'s output is
    /// randomized per process launch and would mint a new id for the same
    /// label every time the app restarts.
    public static func makeId(timesheetProjectId: String, label: String) -> String {
        let combined = "\(timesheetProjectId)::\(label)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
