import Foundation
import GRDB

public struct Block: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var projectId: UUID
    public var start: Date
    public var end: Date
    public var source: Source
    public var note: String?
    public var isManual: Bool
    public var confidence: Double
    public var estimatedHoursWithoutAI: Double?
    public var traskTaskId: String?

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        start: Date,
        end: Date,
        source: Source,
        note: String? = nil,
        isManual: Bool = false,
        confidence: Double = 1.0,
        estimatedHoursWithoutAI: Double? = nil,
        traskTaskId: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.start = start
        self.end = end
        self.source = source
        self.note = note
        self.isManual = isManual
        self.confidence = confidence
        self.estimatedHoursWithoutAI = estimatedHoursWithoutAI
        self.traskTaskId = traskTaskId
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public static let databaseTableName = "block"
}
