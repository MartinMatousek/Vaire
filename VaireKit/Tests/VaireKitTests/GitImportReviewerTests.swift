import Foundation
import Testing
@testable import VaireKit

@Test func candidatesAreScopedToTheGivenWeek() {
    let iso = ISO8601DateFormatter()
    let weekStart = iso.date(from: "2026-08-24T00:00:00Z")!
    let commits = [
        GitCommit(sha: "a", date: iso.date(from: "2026-08-20T08:00:00Z")!, subject: "before the week"),
        GitCommit(sha: "b", date: iso.date(from: "2026-08-25T08:00:00Z")!, subject: "in the week"),
        GitCommit(sha: "c", date: iso.date(from: "2026-09-02T08:00:00Z")!, subject: "after the week"),
    ]

    let candidates = GitImportReviewer.candidates(from: commits, weekStart: weekStart)

    #expect(candidates.count == 1)
    #expect(candidates[0].note == "in the week")
}

@Test func candidateNoteJoinsCommitSubjects() {
    let iso = ISO8601DateFormatter()
    let weekStart = iso.date(from: "2026-08-24T00:00:00Z")!
    let commits = [
        GitCommit(sha: "a", date: iso.date(from: "2026-08-25T08:00:00Z")!, subject: "Fix bug"),
        GitCommit(sha: "b", date: iso.date(from: "2026-08-25T08:05:00Z")!, subject: "Add test"),
    ]

    let candidates = GitImportReviewer.candidates(from: commits, weekStart: weekStart)

    #expect(candidates.count == 1)
    #expect(candidates[0].note == "Fix bug; Add test")
}

@Test func commitOnlyWritesAcceptedCandidates() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let weekStart = Date(timeIntervalSince1970: 0)
    let candidates = [
        GitImportCandidate(start: weekStart, end: weekStart.addingTimeInterval(1800), note: "keep me", included: true),
        GitImportCandidate(start: weekStart.addingTimeInterval(3600), end: weekStart.addingTimeInterval(5400), note: "discard me", included: false),
    ]

    try GitImportReviewer.commit(db: db, projectId: project.id, candidates: candidates, weekStart: weekStart, replacingExisting: false)

    let blocks = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(blocks.count == 1)
    #expect(blocks[0].note == "keep me")
    #expect(blocks[0].isManual == true)
    #expect(blocks[0].source == .gitCommit)
}

@Test func commitReplacingExistingOnlyTouchesGitCommitSourcedBlocks() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let weekStart = Date(timeIntervalSince1970: 0)

    let oldGitBlock = Block(projectId: project.id, start: weekStart, end: weekStart.addingTimeInterval(1800), source: .gitCommit, isManual: true)
    let claudeBlock = Block(projectId: project.id, start: weekStart.addingTimeInterval(2000), end: weekStart.addingTimeInterval(3000), source: .claudeSession, isManual: false)
    try db.dbQueue.write {
        try oldGitBlock.insert($0)
        try claudeBlock.insert($0)
    }

    let newCandidates = [
        GitImportCandidate(start: weekStart, end: weekStart.addingTimeInterval(1800), note: "updated", included: true),
    ]

    try GitImportReviewer.commit(db: db, projectId: project.id, candidates: newCandidates, weekStart: weekStart, replacingExisting: true)

    let blocks = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(blocks.count == 2)
    #expect(blocks.contains { $0.id == claudeBlock.id })
    #expect(blocks.contains { $0.note == "updated" })
    #expect(!blocks.contains { $0.id == oldGitBlock.id })
}

@Test func commitWithNoAcceptedCandidatesAndNotReplacingDoesNothing() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let weekStart = Date(timeIntervalSince1970: 0)
    let candidates = [
        GitImportCandidate(start: weekStart, end: weekStart.addingTimeInterval(1800), note: "discarded", included: false),
    ]

    try GitImportReviewer.commit(db: db, projectId: project.id, candidates: candidates, weekStart: weekStart, replacingExisting: false)

    let blocks = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(blocks.isEmpty)
}
