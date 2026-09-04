import SwiftUI
import WidgetKit
import VaireKit

/// Step-by-step wizard over a day's `FinishSuggestion`s: one suggestion per
/// screen, Skip / Add & next. Each Add writes immediately via
/// `DayFinisher.apply`, so an interrupted flow keeps whatever was already
/// confirmed instead of losing it.
struct FinishDayView: View {
    let day: Date
    let projects: [Project]
    let targetHours: Double
    let onChanged: () -> Void
    /// Called instead of a plain dismiss when Done is pressed and the day
    /// has reached target — lets the caller chain straight into Upload
    /// rather than making the user close this sheet and click Upload
    /// again themselves.
    var onCompleteAndUpload: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var status: DayStatus?
    @State private var suggestions: [FinishSuggestion] = []
    @State private var currentIndex = 0
    @State private var hoursDraft = 0
    @State private var minutesDraft = 0
    @State private var noteDraft = ""
    @State private var projectIdDraft: UUID?
    @State private var isLoading = true

    private var currentSuggestion: FinishSuggestion? {
        guard currentIndex < suggestions.count else { return nil }
        return suggestions[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.finishDay)
                .font(.headline)

            if let status {
                Text(Strings.finishDayHeader(logged: DurationFormatter.hoursMinutes(status.loggedHours), target: DurationFormatter.hoursMinutes(status.targetHours)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Strings.finishDayRemaining(DurationFormatter.hoursMinutes(status.gapHours)))
                    .font(.subheadline)
                    .foregroundStyle(status.isComplete ? .green : .primary)
            }

            if isLoading {
                ProgressView()
            } else if status?.isComplete == true {
                Text(Strings.finishDayComplete)
                    .foregroundStyle(.secondary)
            } else if let suggestion = currentSuggestion {
                suggestionCard(suggestion)
            } else {
                Text(Strings.finishDayNoMoreSuggestions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                suggestionCard(manualFallback())
            }

            HStack {
                Spacer()
                Button(Strings.finishDayDone) {
                    if status?.isComplete == true, let onCompleteAndUpload {
                        dismiss()
                        onCompleteAndUpload()
                    } else {
                        dismiss()
                    }
                }
                if currentSuggestion != nil, status?.isComplete != true {
                    Button(Strings.finishDaySkip) { advance() }
                    Button(Strings.finishDayAddAndNext) { addAndAdvance() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(projectIdDraft == nil)
                }
            }
        }
        .padding()
        .frame(width: 420)
        .task { await load() }
    }

    /// `.prolong` only ever extends an existing block's end time —
    /// `DayFinisher.apply` doesn't read `suggestion.projectId` or
    /// `suggestion.note` for that case at all (confirmed in
    /// DayFinisher.swift), so showing the Project picker and Note field
    /// for it invited exactly the confusion this form used to cause: a
    /// note typed while a prolong suggestion was on screen silently went
    /// nowhere. Only the duration control does anything for a prolong.
    private func suggestionCard(_ suggestion: FinishSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kindLabel(suggestion))
                .font(.subheadline).bold()

            switch suggestion.kind {
            case .prolong(_, let currentStart, let currentEnd):
                Text(Strings.finishDayProlongExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(currentStart.formatted(date: .omitted, time: .shortened))–\(currentEnd.formatted(date: .omitted, time: .shortened)) · \(DurationFormatter.hoursMinutes(currentEnd.timeIntervalSince(currentStart) / 3600))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !suggestion.note.isEmpty {
                    Text(suggestion.note)
                        .font(.caption)
                }

            case .gitCommit, .manual, .meeting:
                Picker(Strings.gitImportProjectLabel, selection: $projectIdDraft) {
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Text(Strings.activityDescriptionLabel).font(.caption)
                TextField(Strings.whatDidYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                    .lineLimit(2...4)
            }

            Text(Strings.timeLabel).font(.caption)
            HoursMinutesField(hours: $hoursDraft, minutes: $minutesDraft)
        }
    }

    private func kindLabel(_ suggestion: FinishSuggestion) -> String {
        switch suggestion.kind {
        case .gitCommit:
            return Strings.finishDaySuggestionGitCommit
        case .prolong:
            let projectName = projects.first(where: { $0.id == suggestion.projectId })?.name ?? "?"
            return Strings.finishDaySuggestionProlong(projectName)
        case .meeting(_, let title):
            return Strings.finishDaySuggestionMeeting(title)
        case .manual:
            return Strings.finishDaySuggestionManual
        }
    }

    private func manualFallback() -> FinishSuggestion {
        let gapMinutes = Int(((status?.gapHours ?? 0) * 60).rounded())
        return FinishSuggestion(
            kind: .manual,
            projectId: projectIdDraft ?? projects.first?.id ?? UUID(),
            start: status.map { Calendar.current.startOfDay(for: $0.day) } ?? day,
            durationMinutes: gapMinutes,
            note: ""
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            status = try DayFinisher.status(db: AppEnvironment.db, day: day, targetHours: targetHours)

            var commitsByProject: [UUID: [GitCommit]] = [:]
            for project in projects {
                let author = (try? gitConfigValue(key: "user.email", repoPath: project.path)) ?? ""
                guard !author.isEmpty else { continue }
                let since = Calendar.current.startOfDay(for: day)
                let until = Calendar.current.date(byAdding: .day, value: 1, to: since) ?? since
                if let commits = try? GitImporter.fetchCommits(repoPath: project.path, author: author, since: since, until: until) {
                    commitsByProject[project.id] = commits
                }
            }

            let meetings = (try? await MeetingImporter.fetchMeetings(
                day: day,
                calendarTitles: MeetingImporter.workCalendarTitles
            )) ?? []

            suggestions = try DayFinisher.suggestions(
                db: AppEnvironment.db,
                day: day,
                commitsByProject: commitsByProject,
                meetings: meetings,
                defaultMeetingProjectId: projects.first?.id,
                targetHours: targetHours
            )
            currentIndex = 0
            loadDraft(from: currentSuggestion)
        } catch {
            suggestions = []
        }
    }

    private func loadDraft(from suggestion: FinishSuggestion?) {
        guard let suggestion else {
            let fallback = manualFallback()
            projectIdDraft = fallback.projectId
            noteDraft = ""
            let rounded = DurationRounding.roundedUp(totalMinutes: fallback.durationMinutes)
            hoursDraft = rounded.hours
            minutesDraft = rounded.minutes
            return
        }
        projectIdDraft = suggestion.projectId
        noteDraft = suggestion.note
        let rounded = DurationRounding.roundedUp(totalMinutes: suggestion.durationMinutes)
        hoursDraft = rounded.hours
        minutesDraft = rounded.minutes
    }

    private func advance() {
        currentIndex += 1
        loadDraft(from: currentSuggestion)
    }

    private func addAndAdvance() {
        guard let projectIdDraft else { return }
        let base = currentSuggestion ?? manualFallback()
        var toApply = base
        toApply.projectId = projectIdDraft
        toApply.note = noteDraft
        toApply.durationMinutes = hoursDraft * 60 + minutesDraft

        guard toApply.durationMinutes > 0 else {
            advance()
            return
        }

        do {
            _ = try DayFinisher.apply(db: AppEnvironment.db, suggestion: toApply)
            DataChangeNotifier.post()
            WidgetCenter.shared.reloadAllTimelines()
            onChanged()
            status = try DayFinisher.status(db: AppEnvironment.db, day: day, targetHours: targetHours)
            if status?.isComplete != true {
                advance()
            }
        } catch {
            advance()
        }
    }
}
