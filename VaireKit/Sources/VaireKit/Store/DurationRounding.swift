public enum DurationRounding {
    /// Rounds a raw minute count up to the nearest 15-minute slot,
    /// cascading into hours (e.g. 118 -> 2h00, not 1h120).
    public static func roundedUp(totalMinutes: Int) -> (hours: Int, minutes: Int) {
        let rounded = ((totalMinutes + 14) / 15) * 15
        return (rounded / 60, rounded % 60)
    }
}
