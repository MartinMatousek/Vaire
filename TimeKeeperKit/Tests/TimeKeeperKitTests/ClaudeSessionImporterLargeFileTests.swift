import Foundation
import Testing
@testable import TimeKeeperKit

@Test func streamsLargeFileWithoutLoadingItWhole() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    defer { try? FileManager.default.removeItem(at: url) }

    // Simulate a large session file with an embedded toolUseResult blob per
    // line, mirroring the multi-MB outliers seen in real transcripts. If the
    // importer ever switches to loading the whole file into memory, this
    // fixture (tens of MB) is large enough for that regression to be
    // noticeable in CI resource usage even though this test only asserts on
    // correctness, not peak memory.
    let handle = FileManager.default.createFile(atPath: url.path, contents: nil)
    #expect(handle)
    let fileHandle = try FileHandle(forWritingTo: url)
    defer { try? fileHandle.close() }

    let bigPayload = String(repeating: "x", count: 4096)
    var baseline = DateComponents()
    baseline.year = 2026
    baseline.month = 8
    baseline.day = 21
    baseline.hour = 8
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(from: baseline)!

    for i in 0..<20_000 {
        let ts = start.addingTimeInterval(Double(i) * 2)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line: String
        if i % 5 == 0 {
            line = #"{"type":"user","timestamp":"\#(iso.string(from: ts))","cwd":"/tmp/big","gitBranch":"main","toolUseResult":"\#(bigPayload)"}\#n"#
        } else {
            line = #"{"type":"assistant","timestamp":"\#(iso.string(from: ts))","cwd":"/tmp/big","gitBranch":"main","toolUseResult":"\#(bigPayload)"}\#n"#
        }
        try fileHandle.write(contentsOf: Data(line.utf8))
    }
    try fileHandle.close()

    let turns = try ClaudeSessionImporter.parseTurns(contentsOf: url)
    #expect(turns.count == 20_000)
}
