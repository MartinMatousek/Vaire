import Foundation
import Testing
@testable import VaireKit

@Test func resolveFallsBackToDefaultWhenConfiguredIsNil() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    #expect(VaireUploadDirectorySetting.resolve(configured: nil, defaultDirectory: defaultDirectory) == defaultDirectory)
}

@Test func resolveFallsBackToDefaultWhenConfiguredIsEmpty() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    #expect(VaireUploadDirectorySetting.resolve(configured: "", defaultDirectory: defaultDirectory) == defaultDirectory)
}

@Test func resolveFallsBackToDefaultWhenConfiguredIsWhitespaceOnly() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    #expect(VaireUploadDirectorySetting.resolve(configured: "   \n\t", defaultDirectory: defaultDirectory) == defaultDirectory)
}

@Test func resolveUsesConfiguredAbsolutePath() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    let configured = "/Users/someone/work/Vaire/VaireUpload"
    #expect(VaireUploadDirectorySetting.resolve(configured: configured, defaultDirectory: defaultDirectory) == URL(fileURLWithPath: configured))
}

@Test func resolveTrimsSurroundingWhitespace() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    let configured = "  /Users/someone/work/Vaire/VaireUpload  \n"
    #expect(VaireUploadDirectorySetting.resolve(configured: configured, defaultDirectory: defaultDirectory) == URL(fileURLWithPath: "/Users/someone/work/Vaire/VaireUpload"))
}

@Test func resolveExpandsTildeUnderHomeDirectory() {
    let defaultDirectory = URL(fileURLWithPath: "/repo/VaireUpload")
    let resolved = VaireUploadDirectorySetting.resolve(configured: "~/projects/Vaire/VaireUpload", defaultDirectory: defaultDirectory)
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(resolved.path.hasPrefix(home.path))
    #expect(resolved.path.hasSuffix("/projects/Vaire/VaireUpload"))
}
