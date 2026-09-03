import SwiftUI
import VaireKit

/// Wraps `FinishDayView` per day from `WeekFinisher.daysNeedingReview`, with
/// a header strip showing hours and a done/current marker per day.
struct FinishWeekView: View {
    let weekStart: Date
    let projects: [Project]
    let targetHours: Double
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var days: [DayStatus] = []
    @State private var dayIndex = 0
    @State private var completedDayIndices: Set<Int> = []

    private var currentDay: DayStatus? {
        guard dayIndex < days.count else { return nil }
        return days[dayIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.finishWeekTitle)
                .font(.headline)

            if !days.isEmpty {
                weekHeaderStrip
            }

            if let currentDay {
                FinishDayView(
                    day: currentDay.day,
                    projects: projects,
                    targetHours: targetHours,
                    onChanged: onChanged
                )
                .id(currentDay.day)

                HStack {
                    Button(Strings.finishWeekBack) { goBack() }
                        .disabled(dayIndex == 0)
                    Spacer()
                    Button(Strings.finishWeekSkipDay) { goNext() }
                    Button(Strings.finishWeekNextDay) { goNext() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(Strings.finishWeekAllCaughtUp)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(Strings.finishDayDone) { dismiss() }
                }
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private var weekHeaderStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    Text(day.day, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                    Text(DurationFormatter.hoursMinutes(day.loggedHours))
                        .font(.system(size: 9))
                        .foregroundStyle(marker(for: index))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func marker(for index: Int) -> Color {
        if completedDayIndices.contains(index) { return .green }
        if index == dayIndex { return .accentColor }
        return .secondary
    }

    private func load() {
        days = (try? WeekFinisher.daysNeedingReview(db: AppEnvironment.db, weekStart: weekStart, targetHours: targetHours)) ?? []
        dayIndex = 0
    }

    private func goNext() {
        completedDayIndices.insert(dayIndex)
        if dayIndex + 1 < days.count {
            dayIndex += 1
        } else {
            dayIndex = days.count
        }
    }

    private func goBack() {
        guard dayIndex > 0 else { return }
        dayIndex -= 1
    }
}
