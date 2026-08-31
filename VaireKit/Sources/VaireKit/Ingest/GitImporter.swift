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

public protocol CommitLogRunning: Sendable {
    func run(repoPath: String, author: String, since: Date) throws -> String
}

public struct GitCommandLineRunner: CommitLogRunning {
    public init() {}

    public func run(repoPath: String, author: String, since: Date) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

        let isoFormatter = ISO8601DateFormatter()
        process.arguments = [
            "-C", repoPath,
            "log",
            "--author=\(author)",
            "--since=\(isoFormatter.string(from: since))",
            "--format=%H|%aI|%s"
        ]

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
        runner: CommitLogRunning = GitCommandLineRunner()
    ) throws -> [GitCommit] {
        let output = try runner.run(repoPath: repoPath, author: author, since: since)
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
}
