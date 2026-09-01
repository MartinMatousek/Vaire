import Testing
import Foundation
@testable import VaireKit

@Test func startedOutcomeRoundTripsAllFields() throws {
    let result = StartRequestResult(sessionId: "abc-123", outcome: .started, note: "fixing the CLI", estimateMinutes: 90)
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(StartRequestResult.self, from: data)
    #expect(decoded.sessionId == "abc-123")
    #expect(decoded.outcome == .started)
    #expect(decoded.note == "fixing the CLI")
    #expect(decoded.estimateMinutes == 90)
}

@Test func declinedOutcomeHasNilFields() throws {
    let result = StartRequestResult(sessionId: "abc-123", outcome: .declined)
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(StartRequestResult.self, from: data)
    #expect(decoded.outcome == .declined)
    #expect(decoded.note == nil)
    #expect(decoded.estimateMinutes == nil)
}

@Test func startResultPathIsStablePerSessionId() throws {
    let sessionId = "session-\(UUID().uuidString)"
    let first = try SharedStorage.startResultPath(forSessionId: sessionId)
    let second = try SharedStorage.startResultPath(forSessionId: sessionId)
    #expect(first == second)
    #expect(first.hasSuffix("\(sessionId).json"))
}

@Test func startResultPathDiffersPerSessionId() throws {
    let a = try SharedStorage.startResultPath(forSessionId: "session-\(UUID().uuidString)")
    let b = try SharedStorage.startResultPath(forSessionId: "session-\(UUID().uuidString)")
    #expect(a != b)
}
