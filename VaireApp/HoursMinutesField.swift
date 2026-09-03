import SwiftUI
import VaireKit

/// Hours/minutes entry with both a direct numeric TextField and Stepper
/// arrows on the same value, so a precise time can be typed or nudged.
struct HoursMinutesField: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField(Strings.hoursAbbrev, value: $hours, format: .number)
                    .frame(width: 32)
                    .multilineTextAlignment(.trailing)
                Text(Strings.hoursAbbrev)
                Stepper("", value: $hours, in: 0...23)
                    .labelsHidden()
            }

            HStack(spacing: 4) {
                TextField(Strings.minutesAbbrev, value: $minutes, format: .number)
                    .frame(width: 32)
                    .multilineTextAlignment(.trailing)
                Text(Strings.minutesAbbrev)
                minutesStepperButtons
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    /// Hand-rolled up/down buttons instead of `Stepper` — SwiftUI's
    /// `Stepper(value:in:step:)` calls the binding's setter twice per
    /// click on the increment side (a platform quirk, not reproducible on
    /// decrement), which double-applies the 15-minute snap. Plain buttons
    /// give a guaranteed single call per click.
    private var minutesStepperButtons: some View {
        VStack(spacing: 0) {
            Button { stepMinutes(up: true) } label: {
                Image(systemName: "chevron.up")
            }
            Button { stepMinutes(up: false) } label: {
                Image(systemName: "chevron.down")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 9))
    }

    /// Moves minutes by 15: from an exact 15-multiple, a plain +/-15; from
    /// an off-grid value (e.g. free-typed 31), snaps to the nearest 15 in
    /// that direction instead. Carries into/out of hours at the 0/60
    /// boundary and clamps at 0h00.
    private func stepMinutes(up: Bool) {
        let total = hours * 60 + minutes
        let newTotal: Int
        if total % 15 == 0 {
            newTotal = total + (up ? 15 : -15)
        } else {
            newTotal = up ? ((total / 15) + 1) * 15 : (total / 15) * 15
        }
        let clamped = max(0, newTotal)
        hours = clamped / 60
        minutes = clamped % 60
    }

    /// Rounds a raw minute count up to the nearest 15-minute slot,
    /// cascading into hours (e.g. 118 -> 2h00, not 1h120). Used to snap a
    /// draft to the grid on save, and when seeding drafts from a measured
    /// duration. Forwards to VaireKit so non-UI code (DayFinisher) can snap
    /// durations without depending on the app target.
    static func roundedUp(totalMinutes: Int) -> (hours: Int, minutes: Int) {
        DurationRounding.roundedUp(totalMinutes: totalMinutes)
    }
}
