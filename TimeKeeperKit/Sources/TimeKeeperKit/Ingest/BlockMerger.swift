import Foundation

public struct CandidateBlock: Equatable, Sendable {
    public let projectId: UUID
    public let start: Date
    public let end: Date
    public let source: Source
    public let evidenceRefs: [String]

    public init(projectId: UUID, start: Date, end: Date, source: Source, evidenceRefs: [String] = []) {
        self.projectId = projectId
        self.start = start
        self.end = end
        self.source = source
        self.evidenceRefs = evidenceRefs
    }
}

public struct MergedBlock: Equatable, Sendable {
    public let projectId: UUID
    public let start: Date
    public let end: Date
    public let sources: [Source]
    public let evidenceRefs: [String]
    public let overlapsOtherProject: Bool
}

public enum BlockMerger {
    /// Merges candidate blocks from multiple ingestion sources. Blocks from
    /// the SAME project that overlap in time are unioned into one block
    /// (you can't double-count time spent in one project just because two
    /// sources both observed it). Blocks from DIFFERENT projects that overlap
    /// are kept separate but flagged via `overlapsOtherProject`, since you
    /// can't really work on two things at once — a human has to resolve
    /// which one actually happened.
    public static func merge(_ candidates: [CandidateBlock]) -> [MergedBlock] {
        guard !candidates.isEmpty else { return [] }

        let byProject = Dictionary(grouping: candidates, by: \.projectId)

        var mergedPerProject: [UUID: [MergedBlock]] = [:]
        for (projectId, blocks) in byProject {
            mergedPerProject[projectId] = mergeSameProject(blocks)
        }

        let allMerged = mergedPerProject.values.flatMap { $0 }.sorted { $0.start < $1.start }

        return allMerged.map { block in
            let overlapsOther = allMerged.contains { other in
                other.projectId(differentFrom: block) &&
                    other.start < block.end && other.end > block.start
            }
            return MergedBlock(
                projectId: block.projectId,
                start: block.start,
                end: block.end,
                sources: block.sources,
                evidenceRefs: block.evidenceRefs,
                overlapsOtherProject: overlapsOther
            )
        }
    }

    private static func mergeSameProject(_ blocks: [CandidateBlock]) -> [MergedBlock] {
        let sorted = blocks.sorted { $0.start < $1.start }

        var result: [MergedBlock] = []
        var currentProjectId = sorted[0].projectId
        var currentStart = sorted[0].start
        var currentEnd = sorted[0].end
        var currentSources: [Source] = [sorted[0].source]
        var currentEvidence = sorted[0].evidenceRefs

        for candidate in sorted.dropFirst() {
            if candidate.start <= currentEnd {
                currentEnd = max(currentEnd, candidate.end)
                if !currentSources.contains(candidate.source) {
                    currentSources.append(candidate.source)
                }
                currentEvidence.append(contentsOf: candidate.evidenceRefs)
            } else {
                result.append(MergedBlock(
                    projectId: currentProjectId,
                    start: currentStart,
                    end: currentEnd,
                    sources: currentSources,
                    evidenceRefs: currentEvidence,
                    overlapsOtherProject: false
                ))
                currentProjectId = candidate.projectId
                currentStart = candidate.start
                currentEnd = candidate.end
                currentSources = [candidate.source]
                currentEvidence = candidate.evidenceRefs
            }
        }

        result.append(MergedBlock(
            projectId: currentProjectId,
            start: currentStart,
            end: currentEnd,
            sources: currentSources,
            evidenceRefs: currentEvidence,
            overlapsOtherProject: false
        ))

        return result
    }
}

private extension MergedBlock {
    func projectId(differentFrom other: MergedBlock) -> Bool {
        projectId != other.projectId
    }
}
