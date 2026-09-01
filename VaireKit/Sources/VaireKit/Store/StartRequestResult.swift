import Foundation

/// Outcome of a `vaire://start-session` request, written by the app as
/// JSON so a shell hook (no SQLite client, but has `jq`) can read it back.
public struct StartRequestResult: Codable {
    public enum Outcome: String, Codable {
        case started
        case declined
    }

    public let sessionId: String
    public let outcome: Outcome
    public let note: String?
    public let estimateMinutes: Int?

    public init(sessionId: String, outcome: Outcome, note: String? = nil, estimateMinutes: Int? = nil) {
        self.sessionId = sessionId
        self.outcome = outcome
        self.note = note
        self.estimateMinutes = estimateMinutes
    }
}
