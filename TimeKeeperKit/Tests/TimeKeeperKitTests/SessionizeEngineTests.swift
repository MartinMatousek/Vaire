import Foundation
import Testing
@testable import TimeKeeperKit

private func turn(_ isoString: String, cwd: String = "/tmp/proj", branch: String = "main") -> SessionTurn {
    SessionTurn(timestamp: ISO8601DateFormatter().date(from: isoString)!, cwd: cwd, gitBranch: branch)
}

@Test func emptyInputProducesNoBlocks() {
    #expect(SessionizeEngine.sessionize(turns: []).isEmpty)
}

@Test func turnsWithinGapFormOneBlock() {
    let turns = [
        turn("2026-08-21T08:00:00Z"),
        turn("2026-08-21T08:05:00Z"),
        turn("2026-08-21T08:10:00Z"),
    ]
    let blocks = SessionizeEngine.sessionize(turns: turns, idleGap: 15 * 60, tailPadding: 0)

    #expect(blocks.count == 1)
    #expect(blocks[0].start == turns[0].timestamp)
    #expect(blocks[0].end == turns[2].timestamp)
}

@Test func gapLargerThanIdleGapSplitsIntoTwoBlocks() {
    let turns = [
        turn("2026-08-21T08:00:00Z"),
        turn("2026-08-21T08:10:00Z"),
        turn("2026-08-21T09:30:00Z"), // 80 min gap from previous turn
        turn("2026-08-21T09:35:00Z"),
    ]
    let blocks = SessionizeEngine.sessionize(turns: turns, idleGap: 15 * 60, tailPadding: 0)

    #expect(blocks.count == 2)
    #expect(blocks[0].end == turns[1].timestamp)
    #expect(blocks[1].start == turns[2].timestamp)
    #expect(blocks[1].end == turns[3].timestamp)
}

@Test func tailPaddingExtendsBlockEnd() {
    let turns = [turn("2026-08-21T08:00:00Z"), turn("2026-08-21T08:05:00Z")]
    let blocks = SessionizeEngine.sessionize(turns: turns, idleGap: 15 * 60, tailPadding: 180)

    #expect(blocks[0].end == turns[1].timestamp.addingTimeInterval(180))
}

@Test func unsortedInputIsSortedBeforeSessionizing() {
    let turns = [
        turn("2026-08-21T08:10:00Z"),
        turn("2026-08-21T08:00:00Z"),
    ]
    let blocks = SessionizeEngine.sessionize(turns: turns, idleGap: 15 * 60, tailPadding: 0)

    #expect(blocks.count == 1)
    #expect(blocks[0].start == ISO8601DateFormatter().date(from: "2026-08-21T08:00:00Z")!)
}
