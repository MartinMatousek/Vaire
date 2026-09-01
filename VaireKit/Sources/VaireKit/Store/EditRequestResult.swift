import Foundation

/// Outcome of a `vaire://edit-block` request, written by the app as JSON so
/// a shell hook (no SQLite client, but has `jq`) can read it back.
public struct EditRequestResult: Codable {
    public enum Outcome: String, Codable {
        case saved
        case discarded
        case resumed
        case cancelled
        case notFound
    }

    public let blockId: UUID
    public let outcome: Outcome
    public let durationMinutes: Int?
    public let note: String?
    public let estimateMinutes: Int?

    public init(blockId: UUID, outcome: Outcome, durationMinutes: Int? = nil, note: String? = nil, estimateMinutes: Int? = nil) {
        self.blockId = blockId
        self.outcome = outcome
        self.durationMinutes = durationMinutes
        self.note = note
        self.estimateMinutes = estimateMinutes
    }
}
