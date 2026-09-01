import SwiftUI
import WidgetKit
import VaireKit

/// Outcome of editing a just-stopped block, reported upward so a caller
/// (the in-popover flow, or a standalone window driven by a hook) can react
/// without this view knowing who's hosting it.
enum StoppedBlockOutcome {
    case saved(durationMinutes: Int, note: String, estimateMinutes: Int?)
    case discarded
    case resumed
}

/// Shared editor for a just-stopped block: note, measured duration
/// (HoursMinutesField), and an optional estimate-without-AI
/// (HoursMinutesField). Used both by the popover shown right after
/// stopping a timer in the menu and by a standalone window opened via the
/// `vaire://edit-block` URL scheme, so the two surfaces stay pixel-identical.
struct StoppedBlockEditorView: View {
    let block: Block
    let showsContinue: Bool
    let onFinish: (StoppedBlockOutcome) -> Void

    @State private var noteDraft: String
    @State private var hoursDraft: Int
    @State private var minutesDraft: Int
    @State private var estimateHoursDraft: Int
    @State private var estimateMinutesDraft: Int
    @State private var hasEstimateDraft: Bool

    init(block: Block, showsContinue: Bool = true, onFinish: @escaping (StoppedBlockOutcome) -> Void) {
        self.block = block
        self.showsContinue = showsContinue
        self.onFinish = onFinish

        _noteDraft = State(initialValue: block.note ?? "")
        let measured = HoursMinutesField.roundedUp(totalMinutes: Int(block.duration / 60))
        _hoursDraft = State(initialValue: measured.hours)
        _minutesDraft = State(initialValue: measured.minutes)
        if let estimate = block.estimatedHoursWithoutAI {
            let estimateRounded = HoursMinutesField.roundedUp(totalMinutes: Int((estimate * 60).rounded()))
            _estimateHoursDraft = State(initialValue: estimateRounded.hours)
            _estimateMinutesDraft = State(initialValue: estimateRounded.minutes)
            _hasEstimateDraft = State(initialValue: true)
        } else {
            _estimateHoursDraft = State(initialValue: 0)
            _estimateMinutesDraft = State(initialValue: 0)
            _hasEstimateDraft = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.editTimeAndDescription).font(.caption).bold()

            Text(Strings.measuredOnTimer(DurationFormatter.hoursMinutes(block.duration / 3600)))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HoursMinutesField(hours: $hoursDraft, minutes: $minutesDraft)

            TextField(Strings.whatDidYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 240)

            Toggle(Strings.estimateWithoutAI, isOn: $hasEstimateDraft)
                .font(.caption)
            if hasEstimateDraft {
                HoursMinutesField(hours: $estimateHoursDraft, minutes: $estimateMinutesDraft)
                let editedHours = Double(hoursDraft) + Double(minutesDraft) / 60
                let estimateHours = Double(estimateHoursDraft) + Double(estimateMinutesDraft) / 60
                if estimateHours < editedHours {
                    Text(Strings.estimateLowerThanMeasured)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button(Strings.discard) { discard() }
                if showsContinue {
                    Button(Strings.`continue`) { resume() }
                }
                Button(Strings.save) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func save() {
        let duration = HoursMinutesField.roundedUp(totalMinutes: hoursDraft * 60 + minutesDraft)
        let durationMinutes = duration.hours * 60 + duration.minutes
        let newEnd = block.start.addingTimeInterval(Double(durationMinutes * 60))
        let estimateMinutes: Int? = {
            guard hasEstimateDraft else { return nil }
            let rounded = HoursMinutesField.roundedUp(totalMinutes: estimateHoursDraft * 60 + estimateMinutesDraft)
            return rounded.hours * 60 + rounded.minutes
        }()
        do {
            _ = try BlockEditor.setTimes(db: AppEnvironment.db, blockId: block.id, start: block.start, end: newEnd)
            _ = try BlockEditor.setNote(db: AppEnvironment.db, blockId: block.id, note: noteDraft)
            let newEstimate: Double? = estimateMinutes.map { Double($0) / 60 }
            if newEstimate != block.estimatedHoursWithoutAI {
                _ = try BlockEditor.setEstimate(db: AppEnvironment.db, blockId: block.id, hours: newEstimate)
            }
        } catch {
            // Block was already persisted by stop(); a failed correction
            // just means the raw times/no note stand — not worth surfacing
            // a menu-bar error for.
        }
        refreshAfterChange()
        onFinish(.saved(durationMinutes: durationMinutes, note: noteDraft, estimateMinutes: estimateMinutes))
    }

    private func discard() {
        try? BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
        refreshAfterChange()
        DataChangeNotifier.post()
        onFinish(.discarded)
    }

    private func resume() {
        do {
            try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
        } catch {
            // Nothing to resume onto if the delete fails — leave the
            // stopped block as-is rather than double-track it.
            return
        }
        AppEnvironment.timer.resume(projectId: block.projectId, from: block.start, note: block.note)
        refreshAfterChange()
        onFinish(.resumed)
    }

    private func refreshAfterChange() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
