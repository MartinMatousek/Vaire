import Testing
@testable import TimeKeeperKit

@Test func extractsJiraStyleTaskId() {
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "feature/PROJ-123-short-desc") == "PROJ-123")
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "bugfix/KVK-42") == "KVK-42")
}

@Test func extractsPrefixStyleTaskId() {
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "feat/CR_Forecast_Lists") == "CR_Forecast_Lists")
}

@Test func returnsNilForBareBranchNames() {
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "main") == nil)
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "develop") == nil)
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "") == nil)
}

@Test func returnsNilForKnownLongLivedBranchesWithPrefix() {
    #expect(BranchTaskMapper.extractTaskId(fromBranch: "origin/main") == nil)
}
