import SwiftUI
import TimeKeeperKit

/// Menu bar icon that fills in green as the day's logged hours approach the
/// daily target — the same idea as the app icon's ring, just dynamic.
///
/// Deliberately avoids SwiftUI materials like `.quaternary` (used by the
/// shared DayProgressRing): those resolve against a rendering context that
/// MenuBarExtra's label doesn't always provide the same way a normal window
/// does, and materials rendering as fully transparent was the likely cause
/// of the icon being invisible.
struct MenuBarIconView: View {
    @State private var hoursWorked: Double = 0

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let lineWidth: CGFloat = 2.5
    private let targetHours: Double = 8

    private var progress: Double {
        targetHours > 0 ? hoursWorked / targetHours : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.35), lineWidth: lineWidth)

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
        .frame(width: 16, height: 16)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .timeKeeperDataChanged)) { _ in refresh() }
    }

    private func refresh() {
        let timerHours = AppEnvironment.timer.runningStarts.keys.reduce(0.0) {
            $0 + AppEnvironment.timer.elapsed(projectId: $1) / 3600
        }
        let loggedHours = (try? DailySummary.totalHours(db: AppEnvironment.db, day: .now)) ?? 0
        hoursWorked = loggedHours + timerHours
    }
}
