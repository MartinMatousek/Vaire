import Foundation

public enum BranchTaskMapper {
    /// Extracts a likely ticket/task identifier from a git branch name.
    /// Recognizes two common conventions:
    ///   - Jira-style: `feature/PROJ-123-short-desc` -> "PROJ-123"
    ///   - Prefix-style: `feat/CR_Forecast_Lists` -> "CR_Forecast_Lists"
    /// Returns nil when the branch name doesn't contain a recognizable
    /// task identifier (e.g. "main", "develop").
    public static func extractTaskId(fromBranch branch: String) -> String? {
        guard !branch.isEmpty else { return nil }

        let withoutPrefix = branch.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch
        guard withoutPrefix != branch || branch.contains("/") else {
            // No slash at all — a bare branch name like "main" or "develop"
            // isn't a task reference.
            return nil
        }

        if let jiraMatch = withoutPrefix.range(of: #"^[A-Z][A-Z0-9]+-\d+"#, options: .regularExpression) {
            return String(withoutPrefix[jiraMatch])
        }

        let ignoredBranches: Set<String> = ["main", "master", "develop", "development", "staging", "release"]
        guard !ignoredBranches.contains(withoutPrefix.lowercased()) else { return nil }

        return withoutPrefix.isEmpty ? nil : withoutPrefix
    }
}
