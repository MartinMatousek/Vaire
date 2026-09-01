import Testing
@testable import VaireKit

@Test func zeroHoursFormatsAsZero() {
    #expect(DurationFormatter.hoursMinutes(0) == "0h 0m")
}

@Test func subMinuteHoursRoundsToNearestMinute() {
    #expect(DurationFormatter.hoursMinutes(0.1) == "0h 6m")
}

@Test func exactHourHasZeroMinutes() {
    #expect(DurationFormatter.hoursMinutes(2.0) == "2h 0m")
}

@Test func negativeHoursKeepsSignOnWholeLabel() {
    #expect(DurationFormatter.hoursMinutes(-0.2) == "-0h 12m")
}

@Test func hoursOverADayAreNotWrapped() {
    #expect(DurationFormatter.hoursMinutes(25.5) == "25h 30m")
}
