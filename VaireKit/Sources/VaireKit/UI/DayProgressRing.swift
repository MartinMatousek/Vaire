import SwiftUI

public struct DayProgressRing: View {
    private let progress: Double
    private let lineWidth: CGFloat

    public init(hoursWorked: Double, targetHours: Double, lineWidth: CGFloat = 6) {
        self.progress = targetHours > 0 ? hoursWorked / targetHours : 0
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(Color.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

#Preview("Under target") {
    DayProgressRing(hoursWorked: 4, targetHours: 8)
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Over target") {
    DayProgressRing(hoursWorked: 10, targetHours: 8)
        .frame(width: 120, height: 120)
        .padding()
}
