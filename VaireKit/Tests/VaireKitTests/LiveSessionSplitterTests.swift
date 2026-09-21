import Testing
@testable import VaireKit

@Test func countedHoursIsElapsedScaledByTargetOverADay() {
    #expect(LiveSessionSplitter.countedHours(elapsedHours: 24, targetHours: 8) == 8)
    #expect(LiveSessionSplitter.countedHours(elapsedHours: 12, targetHours: 8) == 4)
    #expect(LiveSessionSplitter.countedHours(elapsedHours: 46, targetHours: 8) == 46.0 / 24 * 8)
}

@Test func countedHoursFloorsNegativeElapsedToZero() {
    #expect(LiveSessionSplitter.countedHours(elapsedHours: -1, targetHours: 8) == 0)
}

@Test func underADayReturnsOneScaledSegment() {
    // 3h real elapsed -> 3/24*8 = 1h counted
    let segments = LiveSessionSplitter.segments(elapsedHours: 3, targetHours: 8, minHours: 0.25)
    #expect(segments == [LiveSessionSegment(hours: 1, dayIndex: 0, dayCount: 1)])
}

@Test func exactlyOneDayReturnsOneSegmentAtTargetHours() {
    // 24h real elapsed -> exactly targetHours (8h) counted
    let segments = LiveSessionSplitter.segments(elapsedHours: 24, targetHours: 8, minHours: 0.25)
    #expect(segments == [LiveSessionSegment(hours: 8, dayIndex: 0, dayCount: 1)])
}

@Test func fortySixHoursSplitsIntoTwoDays() {
    // 46h real elapsed -> 46/24*8 ~= 15h20m counted -> 8h + 7h20m
    let segments = LiveSessionSplitter.segments(elapsedHours: 46, targetHours: 8, minHours: 0.25)
    #expect(segments.count == 2)
    #expect(segments[0] == LiveSessionSegment(hours: 8, dayIndex: 0, dayCount: 2))
    let expectedSecond = 46.0 / 24 * 8 - 8
    #expect(abs(segments[1].hours - expectedSecond) < 0.0001)
    #expect(segments[1].dayIndex == 1)
    #expect(segments[1].dayCount == 2)
}

@Test func minHoursFloorAppliesOnlyToFirstSegment() {
    let segments = LiveSessionSplitter.segments(elapsedHours: 0.01, targetHours: 8, minHours: 0.25)
    #expect(segments == [LiveSessionSegment(hours: 0.25, dayIndex: 0, dayCount: 1)])
}

@Test func zeroElapsedFloorsToMinHours() {
    let segments = LiveSessionSplitter.segments(elapsedHours: 0, targetHours: 8, minHours: 0.25)
    #expect(segments == [LiveSessionSegment(hours: 0.25, dayIndex: 0, dayCount: 1)])
}

@Test func negativeElapsedFloorsToMinHours() {
    let segments = LiveSessionSplitter.segments(elapsedHours: -1, targetHours: 8, minHours: 0.25)
    #expect(segments == [LiveSessionSegment(hours: 0.25, dayIndex: 0, dayCount: 1)])
}
