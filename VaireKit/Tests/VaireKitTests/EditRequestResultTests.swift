import Testing
import Foundation
@testable import VaireKit

@Test func savedOutcomeRoundTripsAllFields() throws {
    let result = EditRequestResult(
        blockId: UUID(),
        outcome: .saved,
        durationMinutes: 90,
        note: "fixed login bug",
        estimateMinutes: 120
    )
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(EditRequestResult.self, from: data)
    #expect(decoded.blockId == result.blockId)
    #expect(decoded.outcome == .saved)
    #expect(decoded.durationMinutes == 90)
    #expect(decoded.note == "fixed login bug")
    #expect(decoded.estimateMinutes == 120)
}

@Test func discardedOutcomeHasNilFields() throws {
    let result = EditRequestResult(blockId: UUID(), outcome: .discarded)
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(EditRequestResult.self, from: data)
    #expect(decoded.outcome == .discarded)
    #expect(decoded.durationMinutes == nil)
    #expect(decoded.note == nil)
    #expect(decoded.estimateMinutes == nil)
}

@Test func editResultPathIsStablePerBlockId() throws {
    let id = UUID()
    let first = try SharedStorage.editResultPath(forBlockId: id)
    let second = try SharedStorage.editResultPath(forBlockId: id)
    #expect(first == second)
    #expect(first.hasSuffix("\(id.uuidString).json"))
}

@Test func editResultPathDiffersPerBlockId() throws {
    let a = try SharedStorage.editResultPath(forBlockId: UUID())
    let b = try SharedStorage.editResultPath(forBlockId: UUID())
    #expect(a != b)
}
