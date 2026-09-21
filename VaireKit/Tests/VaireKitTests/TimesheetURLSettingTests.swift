import Foundation
import Testing
@testable import VaireKit

@Test func normalizeReturnsNilForNil() {
    #expect(TimesheetURLSetting.normalize(nil) == nil)
}

@Test func normalizeReturnsNilForEmpty() {
    #expect(TimesheetURLSetting.normalize("") == nil)
}

@Test func normalizeReturnsNilForWhitespaceOnly() {
    #expect(TimesheetURLSetting.normalize("   \n\t") == nil)
}

@Test func normalizePrependsHttpsToBareHost() {
    // The actual bug confirmed live: the stored setting had been saved as
    // "my.trask.cz" with no scheme, which every downstream URL parser
    // either rejected or silently failed to match.
    #expect(TimesheetURLSetting.normalize("my.trask.cz") == "https://my.trask.cz")
}

@Test func normalizeLeavesHttpsURLUnchanged() {
    #expect(TimesheetURLSetting.normalize("https://my.trask.cz") == "https://my.trask.cz")
}

@Test func normalizePreservesHttpRatherThanUpgrading() {
    #expect(TimesheetURLSetting.normalize("http://internal.example") == "http://internal.example")
}

@Test func normalizeTrimsSurroundingWhitespace() {
    #expect(TimesheetURLSetting.normalize("  my.trask.cz  \n") == "https://my.trask.cz")
}

@Test func normalizeRejectsOtherSchemes() {
    #expect(TimesheetURLSetting.normalize("ftp://example.com") == nil)
    #expect(TimesheetURLSetting.normalize("vaire://example.com") == nil)
}

@Test func normalizePreservesPath() {
    #expect(TimesheetURLSetting.normalize("my.trask.cz/timesheet") == "https://my.trask.cz/timesheet")
}
