import Foundation

public enum ClaudeSessionImporter {
    private struct RawEntry: Decodable {
        let type: String
        let timestamp: String?
        let cwd: String?
        let gitBranch: String?
        let isSidechain: Bool?
    }

    private static let timestampsWithTurns: Set<String> = ["user", "assistant"]

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Streams a Claude Code session JSONL file line-by-line and extracts
    /// only the fields needed for time tracking. Never loads message content
    /// or toolUseResult — those may contain source code and credentials.
    public static func parseTurns(contentsOf url: URL) throws -> [SessionTurn] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var turns: [SessionTurn] = []
        var buffer = Data()
        let decoder = JSONDecoder()

        while true {
            let chunk = try handle.read(upToCount: 1 << 16) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                if let turn = Self.parseLine(lineData, decoder: decoder) {
                    turns.append(turn)
                }
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
            }
        }

        if !buffer.isEmpty, let turn = Self.parseLine(buffer, decoder: decoder) {
            turns.append(turn)
        }

        return turns
    }

    private static func parseLine(_ lineData: Data, decoder: JSONDecoder) -> SessionTurn? {
        guard !lineData.isEmpty,
              let entry = try? decoder.decode(RawEntry.self, from: lineData) else {
            return nil
        }
        guard timestampsWithTurns.contains(entry.type) else { return nil }
        guard entry.isSidechain != true else { return nil }
        guard let timestampString = entry.timestamp,
              let timestamp = isoFormatter.date(from: timestampString) else {
            return nil
        }

        return SessionTurn(timestamp: timestamp, cwd: entry.cwd, gitBranch: entry.gitBranch)
    }
}
