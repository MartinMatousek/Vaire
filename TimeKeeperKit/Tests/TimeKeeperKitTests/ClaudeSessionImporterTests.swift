import Foundation
import Testing
@testable import TimeKeeperKit

@Test func parsesOnlyUserAndAssistantTurnsWithTimestamp() throws {
    let url = Bundle.module.url(forResource: "session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let turns = try ClaudeSessionImporter.parseTurns(contentsOf: url)

    // 4 valid turns: isSidechain entry and the timestampless "mode" sidecar are dropped.
    #expect(turns.count == 4)
    #expect(turns.allSatisfy { $0.cwd == "/Users/martinmatousek/IdeaProjects/kvk-fe" })
}

@Test func ignoresSidechainTurns() throws {
    let url = Bundle.module.url(forResource: "session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let turns = try ClaudeSessionImporter.parseTurns(contentsOf: url)

    let sidechainTimestamp = ISO8601DateFormatter().date(from: "2026-08-21T08:05:00Z")!
    #expect(!turns.contains { abs($0.timestamp.timeIntervalSince(sidechainTimestamp)) < 1 })
}

@Test func handlesFileWithoutTrailingNewline() throws {
    let noTrailingNewline = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let content = #"{"type":"user","timestamp":"2026-08-21T08:00:00.000Z","cwd":"/tmp/x","gitBranch":"main"}"#
    try content.write(to: noTrailingNewline, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: noTrailingNewline) }

    let turns = try ClaudeSessionImporter.parseTurns(contentsOf: noTrailingNewline)
    #expect(turns.count == 1)
}
