import SwiftUI
import VaireKit

/// Outcome of the start-of-session note+estimate form, reported upward so
/// a hook-driven window can turn it into a `vaire start-session` call
/// (this view never writes to the DB itself — starting a session also
/// needs to record the Claude Code session_id, which only the hook knows).
enum StartSessionOutcome {
    case started(note: String, estimateMinutes: Int?)
    case declined
}

/// Shared editor for starting a new tracked session: which project, an
/// optional note, and an optional estimate-without-AI. Used by a
/// standalone window opened via the `vaire://start-session` URL scheme so
/// a Claude Code SessionStart hook can offer the app's real form instead
/// of a sequence of AppleScript yes/no prompts.
struct StartSessionEditorView: View {
    let projectName: String
    let onFinish: (StartSessionOutcome) -> Void

    @State private var noteDraft: String = ""
    @State private var estimateHoursDraft: Int = 0
    @State private var estimateMinutesDraft: Int = 0
    @State private var hasEstimateDraft: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.logTimeFor(projectName)).font(.caption).bold()

            Text(Strings.activityDescription).font(.caption).bold()
            TextField(Strings.whatWillYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 240)

            Toggle(Strings.estimateWithoutAI, isOn: $hasEstimateDraft)
                .font(.caption)
            if hasEstimateDraft {
                HoursMinutesField(hours: $estimateHoursDraft, minutes: $estimateMinutesDraft)
            }

            HStack {
                Spacer()
                Button(Strings.dontLog) { onFinish(.declined) }
                Button(Strings.start) { start(note: noteDraft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func start(note: String) {
        let estimateMinutes: Int? = {
            guard hasEstimateDraft else { return nil }
            let rounded = HoursMinutesField.roundedUp(totalMinutes: estimateHoursDraft * 60 + estimateMinutesDraft)
            return rounded.hours * 60 + rounded.minutes
        }()
        onFinish(.started(note: note, estimateMinutes: estimateMinutes))
    }
}
