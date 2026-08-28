import Foundation

public struct Block: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var projectId: UUID
    public var start: Date
    public var end: Date
    public var source: Source
    public var note: String?
    public var isManual: Bool
    public var confidence: Double

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        start: Date,
        end: Date,
        source: Source,
        note: String? = nil,
        isManual: Bool = false,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.projectId = projectId
        self.start = start
        self.end = end
        self.source = source
        self.note = note
        self.isManual = isManual
        self.confidence = confidence
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}
