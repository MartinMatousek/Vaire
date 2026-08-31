import Foundation

public struct SessionizedBlock: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let cwd: String?
    public let gitBranch: String?

    public init(start: Date, end: Date, cwd: String?, gitBranch: String?) {
        self.start = start
        self.end = end
        self.cwd = cwd
        self.gitBranch = gitBranch
    }
}

public enum SessionizeEngine {
    /// Splits a sequence of session turns into contiguous work blocks.
    /// A new block starts whenever the gap between two consecutive turns
    /// exceeds `idleGap`. Each block's end is padded by `tailPadding` to
    /// account for time spent reading the last response.
    ///
    /// cwd/gitBranch for a block are taken from its last turn, since that
    /// reflects where the work most recently was.
    public static func sessionize(
        turns: [SessionTurn],
        idleGap: TimeInterval = 15 * 60,
        tailPadding: TimeInterval = 3 * 60
    ) -> [SessionizedBlock] {
        guard !turns.isEmpty else { return [] }

        let sorted = turns.sorted { $0.timestamp < $1.timestamp }

        var blocks: [SessionizedBlock] = []
        var groupStart = sorted[0].timestamp
        var groupLast = sorted[0]

        for turn in sorted.dropFirst() {
            let gap = turn.timestamp.timeIntervalSince(groupLast.timestamp)
            if gap > idleGap {
                blocks.append(SessionizedBlock(
                    start: groupStart,
                    end: groupLast.timestamp.addingTimeInterval(tailPadding),
                    cwd: groupLast.cwd,
                    gitBranch: groupLast.gitBranch
                ))
                groupStart = turn.timestamp
            }
            groupLast = turn
        }

        blocks.append(SessionizedBlock(
            start: groupStart,
            end: groupLast.timestamp.addingTimeInterval(tailPadding),
            cwd: groupLast.cwd,
            gitBranch: groupLast.gitBranch
        ))

        return blocks
    }
}
