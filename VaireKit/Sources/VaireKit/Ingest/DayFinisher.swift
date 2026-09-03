import Foundation
import GRDB

public struct FinishSuggestion: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case gitCommit(shas: [String], suggestedNote: String)
        case prolong(blockId: UUID, currentEnd: Date)
        case manual
    }

    public let id: UUID
    public let kind: Kind
    public var projectId: UUID
    public var start: Date
    public var durationMinutes: Int
    public var note: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        projectId: UUID,
        start: Date,
        durationMinutes: Int,
        note: String
    ) {
        self.id = id
        self.kind = kind
        self.projectId = projectId
        self.start = start
        self.durationMinutes = durationMinutes
        self.note = note
    }
}

public struct DayStatus: Equatable, Sendable {
    public let day: Date
    public let loggedHours: Double
    public let targetHours: Double

    public var gapHours: Double { max(0, targetHours - loggedHours) }
    public var isComplete: Bool { loggedHours >= targetHours }

    public init(day: Date, loggedHours: Double, targetHours: Double) {
        self.day = day
        self.loggedHours = loggedHours
        self.targetHours = targetHours
    }
}

public enum DayFinisher {
    public static func status(db: AppDatabase, day: Date, targetHours: Double = 8, calendar: Calendar = .current) throws -> DayStatus {
        let loggedHours = try DailySummary.totalHours(db: db, day: day, calendar: calendar)
        return DayStatus(day: day, loggedHours: loggedHours, targetHours: targetHours)
    }

    /// Builds the ordered list of gap-filling suggestions for `day`:
    /// unlogged git commits first (per project, already filtered to
    /// commits not overlapping an existing block), then prolonging the
    /// day's most recent blocks, then a manual entry as the always-present
    /// fallback. `commitsByProject` is fetched by the caller (a subprocess
    /// call to git) so this stays pure and testable.
    public static func suggestions(
        db: AppDatabase,
        day: Date,
        commitsByProject: [UUID: [GitCommit]],
        targetHours: Double = 8,
        calendar: Calendar = .current
    ) throws -> [FinishSuggestion] {
        let (dayStart, dayEnd) = dayBounds(for: day, calendar: calendar)
        let allBlocks = try db.dbQueue.read { try Block.fetchAll($0) }
        let dayBlocks = allBlocks.filter { $0.start < dayEnd && $0.end > dayStart }

        var suggestions: [FinishSuggestion] = []

        for (projectId, commits) in commitsByProject {
            let dayCommits = commits.filter { $0.date >= dayStart && $0.date < dayEnd }
            let candidates = GitImporter.candidatesWithCommits(from: dayCommits)
            for candidate in candidates {
                let range = (start: candidate.block.start, end: candidate.block.end)
                guard !GitImporter.overlapsExistingBlock(range, projectId: projectId, blocks: allBlocks) else { continue }
                let totalMinutes = Int(candidate.block.end.timeIntervalSince(candidate.block.start) / 60)
                let rounded = DurationRounding.roundedUp(totalMinutes: totalMinutes)
                suggestions.append(FinishSuggestion(
                    kind: .gitCommit(shas: candidate.commits.map(\.sha), suggestedNote: candidate.suggestedNote),
                    projectId: projectId,
                    start: candidate.block.start,
                    durationMinutes: rounded.hours * 60 + rounded.minutes,
                    note: candidate.suggestedNote
                ))
            }
        }

        let mostRecentFirst = dayBlocks.sorted { $0.start > $1.start }
        for block in mostRecentFirst {
            suggestions.append(FinishSuggestion(
                kind: .prolong(blockId: block.id, currentEnd: block.end),
                projectId: block.projectId,
                start: block.end,
                durationMinutes: 0,
                note: block.note ?? ""
            ))
        }

        let defaultProjectId = mostUsedProjectId(in: dayBlocks) ?? commitsByProject.keys.first
        if let defaultProjectId {
            suggestions.append(FinishSuggestion(
                kind: .manual,
                projectId: defaultProjectId,
                start: dayBlocks.map(\.end).max() ?? dayStart,
                durationMinutes: 0,
                note: ""
            ))
        }

        return suggestions
    }

    /// Applies one suggestion: inserts a manual block for `.gitCommit`/
    /// `.manual`, or extends an existing block's end for `.prolong`. All
    /// durations are snapped to 15 minutes before writing. Every write is
    /// marked manual — by the time a suggestion reaches here, the user has
    /// individually reviewed and confirmed it, so a later reimport must
    /// never silently overwrite it.
    @discardableResult
    public static func apply(db: AppDatabase, suggestion: FinishSuggestion) throws -> Block {
        let rounded = DurationRounding.roundedUp(totalMinutes: suggestion.durationMinutes)
        let durationSeconds = TimeInterval(rounded.hours * 3600 + rounded.minutes * 60)

        switch suggestion.kind {
        case .gitCommit:
            let block = Block(
                projectId: suggestion.projectId,
                start: suggestion.start,
                end: suggestion.start.addingTimeInterval(durationSeconds),
                source: .gitCommit,
                note: suggestion.note.isEmpty ? nil : suggestion.note,
                isManual: true
            )
            try db.dbQueue.write { try block.insert($0) }
            return block

        case .prolong(let blockId, let currentEnd):
            guard let existing = try db.dbQueue.read({ try Block.fetchOne($0, key: blockId) }) else {
                throw BlockEditorError.blockNotFound
            }
            let newEnd = currentEnd.addingTimeInterval(durationSeconds)
            return try BlockEditor.setTimes(db: db, blockId: blockId, start: existing.start, end: newEnd)

        case .manual:
            let block = Block(
                projectId: suggestion.projectId,
                start: suggestion.start,
                end: suggestion.start.addingTimeInterval(durationSeconds),
                source: .manual,
                note: suggestion.note.isEmpty ? nil : suggestion.note,
                isManual: true
            )
            try db.dbQueue.write { try block.insert($0) }
            return block
        }
    }

    private static func mostUsedProjectId(in blocks: [Block]) -> UUID? {
        let totals = Dictionary(grouping: blocks, by: \.projectId)
            .mapValues { $0.reduce(0.0) { $0 + $1.duration } }
        return totals.max { $0.value < $1.value }?.key
    }

    private static func dayBounds(for day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}
