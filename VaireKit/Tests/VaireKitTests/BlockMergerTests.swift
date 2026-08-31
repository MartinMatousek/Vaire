import Foundation
import Testing
@testable import VaireKit

private func date(_ isoString: String) -> Date {
    ISO8601DateFormatter().date(from: isoString)!
}

@Test func emptyInputProducesNoMergedBlocks() {
    #expect(BlockMerger.merge([]).isEmpty)
}

@Test func overlappingBlocksSameProjectMergeIntoOne() {
    let projectId = UUID()
    let candidates = [
        CandidateBlock(projectId: projectId, start: date("2026-08-21T08:00:00Z"), end: date("2026-08-21T09:00:00Z"), source: .claudeSession, evidenceRefs: ["session-1"]),
        CandidateBlock(projectId: projectId, start: date("2026-08-21T08:30:00Z"), end: date("2026-08-21T08:45:00Z"), source: .gitCommit, evidenceRefs: ["commit-1"]),
    ]
    let merged = BlockMerger.merge(candidates)

    #expect(merged.count == 1)
    #expect(merged[0].start == date("2026-08-21T08:00:00Z"))
    #expect(merged[0].end == date("2026-08-21T09:00:00Z"))
    #expect(Set(merged[0].sources) == [.claudeSession, .gitCommit])
    #expect(Set(merged[0].evidenceRefs) == ["session-1", "commit-1"])
}

@Test func nonOverlappingBlocksSameProjectStaySeparate() {
    let projectId = UUID()
    let candidates = [
        CandidateBlock(projectId: projectId, start: date("2026-08-21T08:00:00Z"), end: date("2026-08-21T09:00:00Z"), source: .claudeSession),
        CandidateBlock(projectId: projectId, start: date("2026-08-21T11:00:00Z"), end: date("2026-08-21T12:00:00Z"), source: .claudeSession),
    ]
    let merged = BlockMerger.merge(candidates)
    #expect(merged.count == 2)
}

@Test func overlappingBlocksDifferentProjectsStaySeparateButFlagged() {
    let projectA = UUID()
    let projectB = UUID()
    let candidates = [
        CandidateBlock(projectId: projectA, start: date("2026-08-21T08:00:00Z"), end: date("2026-08-21T09:00:00Z"), source: .claudeSession),
        CandidateBlock(projectId: projectB, start: date("2026-08-21T08:30:00Z"), end: date("2026-08-21T09:30:00Z"), source: .claudeSession),
    ]
    let merged = BlockMerger.merge(candidates)

    #expect(merged.count == 2)
    #expect(merged.allSatisfy { $0.overlapsOtherProject })
}

@Test func nonOverlappingBlocksDifferentProjectsAreNotFlagged() {
    let projectA = UUID()
    let projectB = UUID()
    let candidates = [
        CandidateBlock(projectId: projectA, start: date("2026-08-21T08:00:00Z"), end: date("2026-08-21T09:00:00Z"), source: .claudeSession),
        CandidateBlock(projectId: projectB, start: date("2026-08-21T10:00:00Z"), end: date("2026-08-21T11:00:00Z"), source: .claudeSession),
    ]
    let merged = BlockMerger.merge(candidates)
    #expect(merged.allSatisfy { !$0.overlapsOtherProject })
}

@Test func totalMergedDurationNeverExceedsUnionOfInputs() {
    // Regression guard for the core correctness property: merging must never
    // inflate total tracked time beyond what the wall-clock union covers.
    let projectId = UUID()
    let candidates = [
        CandidateBlock(projectId: projectId, start: date("2026-08-21T08:00:00Z"), end: date("2026-08-21T10:00:00Z"), source: .claudeSession),
        CandidateBlock(projectId: projectId, start: date("2026-08-21T09:00:00Z"), end: date("2026-08-21T11:00:00Z"), source: .gitCommit),
    ]
    let merged = BlockMerger.merge(candidates)

    let totalSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
    #expect(totalSeconds == 3 * 3600) // 08:00-11:00 union, not 2h + 2h = 4h
}
