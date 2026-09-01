import Foundation
import Testing
@testable import VaireKit

@Test func reimportReplacesOnlyNonManualBlocksInRange() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let autoBlock = Block(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 3600),
        source: .claudeSession,
        isManual: false
    )
    let manualBlock = Block(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 3600),
        end: Date(timeIntervalSince1970: 7200),
        source: .claudeSession,
        isManual: true
    )
    try db.dbQueue.write {
        try autoBlock.insert($0)
        try manualBlock.insert($0)
    }

    let newCandidate = MergedBlock(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 5400),
        sources: [.claudeSession],
        evidenceRefs: [],
        overlapsOtherProject: false
    )
    try ReimportGuard.reconcile(db: db, projectId: project.id, candidates: [newCandidate])

    let remaining = try db.dbQueue.read { try Block.fetchAll($0) }

    // The old auto block is gone (superseded by the new import), the manual
    // block survived untouched, and the new auto block was inserted.
    #expect(remaining.count == 2)
    #expect(remaining.contains { $0.id == manualBlock.id && $0.start == manualBlock.start })
    #expect(remaining.contains { !$0.isManual && $0.start == newCandidate.start && $0.end == newCandidate.end })
    #expect(!remaining.contains { $0.id == autoBlock.id })
}

@Test func deletedBlockDoesNotReappearOnReimport() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let strayBlock = Block(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 180),
        source: .claudeSession,
        isManual: false
    )
    try db.dbQueue.write { try strayBlock.insert($0) }

    try BlockEditor.delete(db: db, blockId: strayBlock.id)

    // Same transcript reimported again (e.g. a later live-import fires for
    // the same session file) produces the same candidate — it must not
    // come back after being explicitly deleted.
    let sameCandidateAgain = MergedBlock(
        projectId: project.id,
        start: strayBlock.start,
        end: strayBlock.end,
        sources: [.claudeSession],
        evidenceRefs: [],
        overlapsOtherProject: false
    )
    try ReimportGuard.reconcile(db: db, projectId: project.id, candidates: [sameCandidateAgain])

    let remaining = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(remaining.isEmpty)
}

@Test func reimportWithNoCandidatesLeavesExistingBlocksUntouched() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "p", path: "/tmp/p")
    try db.dbQueue.write { try project.insert($0) }

    let block = Block(projectId: project.id, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), source: .claudeSession, isManual: false)
    try db.dbQueue.write { try block.insert($0) }

    try ReimportGuard.reconcile(db: db, projectId: project.id, candidates: [])

    let remaining = try db.dbQueue.read { try Block.fetchAll($0) }
    #expect(remaining.count == 1)
}
