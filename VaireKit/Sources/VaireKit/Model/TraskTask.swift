import CryptoKit
import Foundation
import GRDB

/// A task under a `TraskProject`, scraped from that project's Task
/// dropdown. Unlike projects, tasks carry no visible stable code in Trask's
/// UI, so `id` is a deterministic hash of (traskProjectId, label) rather
/// than a natural key — sufficient to upsert by identity across re-scrapes
/// as long as the label itself doesn't change. `active` follows the same
/// convention as `TraskProject.active`.
public struct TraskTask: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var traskProjectId: String
    public var label: String
    public var active: Bool

    public init(id: String, traskProjectId: String, label: String, active: Bool = true) {
        self.id = id
        self.traskProjectId = traskProjectId
        self.label = label
        self.active = active
    }

    public static let databaseTableName = "traskTask"

    /// Deterministic id derived from the project id and task label, so the
    /// same (project, task) pair always resolves to the same row across
    /// re-scrapes without Trask ever exposing a real task identifier. Uses
    /// SHA256 rather than `Hasher` — `Hasher`'s output is randomized per
    /// process launch and would mint a new id for the same label every
    /// time the app restarts.
    public static func makeId(traskProjectId: String, label: String) -> String {
        let combined = "\(traskProjectId)::\(label)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
