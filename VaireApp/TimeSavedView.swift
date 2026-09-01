import SwiftUI
import VaireKit

struct TimeSavedView: View {
    let weekStart: Date
    @State private var summary: TimeSavedWeekSummary?
    @State private var editingEntry: TimeSavedEntry?
    @State private var estimateHoursDraft: Int = 0
    @State private var estimateMinutesDraft: Int = 0

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let formatter = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(weekStart.formatted(formatter)) – \(weekEnd.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.timeSavedTitle(weekRangeLabel))
                .font(.headline)

            if let summary, !summary.entries.isEmpty {
                totalsRow(summary)
                Divider()
                List(summary.entries, id: \.block.id) { entry in
                    entryRow(entry)
                }
            } else {
                Text(Strings.noEstimatesThisWeek)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(width: 480, height: 420)
        .onAppear(perform: reload)
        .onChange(of: weekStart) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .vaireDataChanged)) { _ in
            reload()
        }
    }

    private func totalsRow(_ summary: TimeSavedWeekSummary) -> some View {
        HStack(spacing: 20) {
            statTile(label: Strings.estimateWithoutAI, value: hoursLabel(summary.totalEstimatedHours))
            statTile(label: Strings.actualTime, value: hoursLabel(summary.totalActualHours))
            statTile(
                label: Strings.saved,
                value: hoursLabel(summary.totalSavedHours),
                color: summary.totalSavedHours < 0 ? .red : .green
            )
        }
    }

    private func statTile(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3).bold().foregroundStyle(color)
        }
    }

    private func entryRow(_ entry: TimeSavedEntry) -> some View {
        let overEstimate = entry.savedHours < 0

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.project.name).font(.callout).bold()
                Spacer()
                Text("\(overEstimate ? "" : "+")\(hoursLabel(entry.savedHours))")
                    .font(.callout)
                    .foregroundStyle(overEstimate ? .red : .green)
            }
            if let note = entry.block.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(Strings.actualVsEstimate(actual: hoursLabel(entry.actualHours), estimate: hoursLabel(entry.estimatedHours)))
                .font(.caption2)
                .foregroundStyle(overEstimate ? .red : .secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button(Strings.editEstimate) { beginEditingEstimate(entry) }
        }
        .popover(isPresented: Binding(
            get: { editingEntry?.block.id == entry.block.id },
            set: { if !$0 { editingEntry = nil } }
        )) {
            estimateEditor(for: entry)
        }
    }

    private func estimateEditor(for entry: TimeSavedEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.estimateWithoutAIHours).font(.caption).bold()
            HoursMinutesField(hours: $estimateHoursDraft, minutes: $estimateMinutesDraft)
            HStack {
                Spacer()
                Button(Strings.cancel) { editingEntry = nil }
                Button(Strings.save) { saveEstimateEdit(for: entry) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func beginEditingEstimate(_ entry: TimeSavedEntry) {
        let estimateRounded = HoursMinutesField.roundedUp(totalMinutes: Int((entry.estimatedHours * 60).rounded()))
        estimateHoursDraft = estimateRounded.hours
        estimateMinutesDraft = estimateRounded.minutes
        editingEntry = entry
    }

    private func saveEstimateEdit(for entry: TimeSavedEntry) {
        let rounded = HoursMinutesField.roundedUp(totalMinutes: estimateHoursDraft * 60 + estimateMinutesDraft)
        let hours = Double(rounded.hours * 60 + rounded.minutes) / 60
        _ = try? BlockEditor.setEstimate(db: AppEnvironment.db, blockId: entry.block.id, hours: hours)
        reload()
        editingEntry = nil
    }

    private func hoursLabel(_ hours: Double) -> String {
        DurationFormatter.hoursMinutes(hours)
    }

    private func reload() {
        summary = try? TimeSavedSummary.weekSummary(db: AppEnvironment.db, day: weekStart)
    }
}

#Preview {
    TimeSavedView(weekStart: .now)
}
