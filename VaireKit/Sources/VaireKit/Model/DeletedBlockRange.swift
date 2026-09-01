import Foundation
import GRDB

/// A tombstone marking a time range the user explicitly deleted for a
/// project, so ReimportGuard.reconcile knows not to re-derive a block
/// there from the source transcript on a later live reimport.
public struct DeletedBlockRange: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var projectId: UUID
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), projectId: UUID, start: Date, end: Date) {
        self.id = id
        self.projectId = projectId
        self.start = start
        self.end = end
    }

    public static let databaseTableName = "deletedBlockRange"
}
