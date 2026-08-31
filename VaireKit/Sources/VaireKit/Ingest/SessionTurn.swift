import Foundation

public struct SessionTurn: Equatable, Sendable {
    public let timestamp: Date
    public let cwd: String?
    public let gitBranch: String?

    public init(timestamp: Date, cwd: String?, gitBranch: String?) {
        self.timestamp = timestamp
        self.cwd = cwd
        self.gitBranch = gitBranch
    }
}
