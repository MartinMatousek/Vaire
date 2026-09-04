import Foundation

public struct GitCommit: Equatable, Sendable {
    public let sha: String
    public let date: Date
    public let subject: String

    public init(sha: String, date: Date, subject: String) {
        self.sha = sha
        self.date = date
        self.subject = subject
    }
}

public enum GitImporterError: Error {
    case processFailed(exitCode: Int32, stderr: String)
}

/// Reads a git config value (e.g. "user.email") for a repository, used to
/// scope commit imports to commits authored by the current user.
public func gitConfigValue(key: String, repoPath: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repoPath, "config", key]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

public protocol CommitLogRunning: Sendable {
    func run(repoPath: String, author: String, since: Date, until: Date?) throws -> String
}

public struct GitCommandLineRunner: CommitLogRunning {
    public init() {}

    public func run(repoPath: String, author: String, since: Date, until: Date?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

        let isoFormatter = ISO8601DateFormatter()
        var arguments = [
            "-C", repoPath,
            "log",
            "--author=\(author)",
            "--since=\(isoFormatter.string(from: since))"
        ]
        if let until {
            arguments.append("--until=\(isoFormatter.string(from: until))")
        }
        arguments.append("--format=%H|%aI|%s")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData, encoding: .utf8) ?? ""
            throw GitImporterError.processFailed(exitCode: process.terminationStatus, stderr: message)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}

public enum GitImporter {
    /// Parses `git log --format=%H|%aI|%s` output into commits.
    public static func parseCommits(logOutput: String) -> [GitCommit] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()

        var commits: [GitCommit] = []
        for line in logOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let sha = String(parts[0])
            let dateString = String(parts[1])
            let subject = String(parts[2])

            guard let date = isoFormatter.date(from: dateString) ?? isoFormatterNoFraction.date(from: dateString) else {
                continue
            }
            commits.append(GitCommit(sha: sha, date: date, subject: subject))
        }
        return commits
    }

    public static func fetchCommits(
        repoPath: String,
        author: String,
        since: Date,
        until: Date? = nil,
        runner: CommitLogRunning = GitCommandLineRunner()
    ) throws -> [GitCommit] {
        let output = try runner.run(repoPath: repoPath, author: author, since: since, until: until)
        return parseCommits(logOutput: output)
    }

    /// Groups commits into blocks: commits closer together than `idleGap`
    /// merge into the same block. Each block's start is the earliest
    /// commit's timestamp minus `preCommitLead`, estimating the work that
    /// preceded it; the end is the latest commit's timestamp in the group.
    public static func blocks(
        from commits: [GitCommit],
        idleGap: TimeInterval = 15 * 60,
        preCommitLead: TimeInterval = 20 * 60
    ) -> [SessionizedBlock] {
        guard !commits.isEmpty else { return [] }

        let sorted = commits.sorted { $0.date < $1.date }
        var groups: [[GitCommit]] = [[sorted[0]]]

        for commit in sorted.dropFirst() {
            let lastGroupEnd = groups[groups.count - 1].last!.date
            if commit.date.timeIntervalSince(lastGroupEnd) > idleGap {
                groups.append([commit])
            } else {
                groups[groups.count - 1].append(commit)
            }
        }

        return groups.map { group in
            let start = group.first!.date.addingTimeInterval(-preCommitLead)
            let end = group.last!.date
            return SessionizedBlock(start: start, end: end, cwd: nil, gitBranch: nil)
        }
    }

    /// A sessionized block paired with the commit subjects that produced
    /// it, so a review UI can show the user what work the block represents
    /// before it's written — plain `blocks(from:)` throws that context away.
    public struct CandidateWithCommits: Equatable, Sendable {
        public let block: SessionizedBlock
        public let commits: [GitCommit]

        public var suggestedNote: String {
            commits.map(\.subject).joined(separator: "; ")
        }
    }

    /// Whether `range` overlaps any existing block for `projectId` — used to
    /// drop a commit-derived candidate that would duplicate time already
    /// logged for that project, without touching other projects' blocks.
    public static func overlapsExistingBlock(_ range: (start: Date, end: Date), projectId: UUID, blocks: [Block]) -> Bool {
        blocks.contains { block in
            block.projectId == projectId && block.start < range.end && block.end > range.start
        }
    }

    public static func candidatesWithCommits(
        from commits: [GitCommit],
        idleGap: TimeInterval = 15 * 60,
        preCommitLead: TimeInterval = 20 * 60
    ) -> [CandidateWithCommits] {
        guard !commits.isEmpty else { return [] }

        let sorted = commits.sorted { $0.date < $1.date }
        var groups: [[GitCommit]] = [[sorted[0]]]

        for commit in sorted.dropFirst() {
            let lastGroupEnd = groups[groups.count - 1].last!.date
            if commit.date.timeIntervalSince(lastGroupEnd) > idleGap {
                groups.append([commit])
            } else {
                groups[groups.count - 1].append(commit)
            }
        }

        return groups.map { group in
            let start = group.first!.date.addingTimeInterval(-preCommitLead)
            let end = group.last!.date
            let block = SessionizedBlock(start: start, end: end, cwd: nil, gitBranch: nil)
            return CandidateWithCommits(block: block, commits: group)
        }
    }
}
