import Foundation
import GRDB

public struct Evidence: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public enum Kind: String, Codable, Sendable {
        case claudeSessionId
        case commitSha
        case fileEdit
    }

    public var id: UUID
    public var blockId: UUID
    public var kind: Kind
    public var refId: String
    public var payloadJSON: String?

    public init(
        id: UUID = UUID(),
        blockId: UUID,
        kind: Kind,
        refId: String,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.blockId = blockId
        self.kind = kind
        self.refId = refId
        self.payloadJSON = payloadJSON
    }

    public static let databaseTableName = "evidence"
}
