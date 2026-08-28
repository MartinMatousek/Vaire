import Foundation
import Testing
@testable import TimeKeeperKit

@Test func parsesCommitLogLines() {
    let log = """
    a1b2c3|2026-08-21T08:00:00+02:00|Fix batch update
    d4e5f6|2026-08-21T08:15:00+02:00|Add tests
    """
    let commits = GitImporter.parseCommits(logOutput: log)

    #expect(commits.count == 2)
    #expect(commits[0].sha == "a1b2c3")
    #expect(commits[0].subject == "Fix batch update")
    #expect(commits[1].subject == "Add tests")
}

@Test func skipsMalformedLines() {
    let log = """
    a1b2c3|2026-08-21T08:00:00+02:00|Fix batch update
    not-a-valid-line
    """
    let commits = GitImporter.parseCommits(logOutput: log)
    #expect(commits.count == 1)
}

@Test func commitsWithinIdleGapFormOneBlock() {
    let iso = ISO8601DateFormatter()
    let commits = [
        GitCommit(sha: "a", date: iso.date(from: "2026-08-21T08:00:00Z")!, subject: "a"),
        GitCommit(sha: "b", date: iso.date(from: "2026-08-21T08:10:00Z")!, subject: "b"),
    ]
    let blocks = GitImporter.blocks(from: commits, idleGap: 15 * 60, preCommitLead: 0)

    #expect(blocks.count == 1)
    #expect(blocks[0].start == commits[0].date)
    #expect(blocks[0].end == commits[1].date)
}

@Test func distantCommitsFormSeparateBlocks() {
    let iso = ISO8601DateFormatter()
    let commits = [
        GitCommit(sha: "a", date: iso.date(from: "2026-08-21T08:00:00Z")!, subject: "a"),
        GitCommit(sha: "b", date: iso.date(from: "2026-08-21T11:00:00Z")!, subject: "b"),
    ]
    let blocks = GitImporter.blocks(from: commits, idleGap: 15 * 60, preCommitLead: 0)
    #expect(blocks.count == 2)
}

@Test func preCommitLeadExtendsBlockStart() {
    let iso = ISO8601DateFormatter()
    let commits = [GitCommit(sha: "a", date: iso.date(from: "2026-08-21T08:00:00Z")!, subject: "a")]
    let blocks = GitImporter.blocks(from: commits, preCommitLead: 1200)

    #expect(blocks[0].start == commits[0].date.addingTimeInterval(-1200))
    #expect(blocks[0].end == commits[0].date)
}
