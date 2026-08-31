import SwiftUI

/// Hours/minutes entry with both a direct numeric TextField and Stepper
/// arrows on the same value, so a precise time can be typed or nudged.
struct HoursMinutesField: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("h", value: $hours, format: .number)
                    .frame(width: 32)
                    .multilineTextAlignment(.trailing)
                Text("h")
                Stepper("", value: $hours, in: 0...23)
                    .labelsHidden()
            }

            HStack(spacing: 4) {
                TextField("m", value: $minutes, format: .number)
                    .frame(width: 32)
                    .multilineTextAlignment(.trailing)
                Text("m")
                Stepper("", value: $minutes, in: 0...59, step: 5)
                    .labelsHidden()
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
