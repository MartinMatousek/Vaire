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
                Button(Strings.finishDayDone) { dismiss() }
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
        .onAppear(perform: load)
    }

    private func suggestionCard(_ suggestion: FinishSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kindLabel(suggestion))
                .font(.caption).bold()

            Picker(Strings.gitImportProjectLabel, selection: $projectIdDraft) {
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }

            Text(Strings.activityDescriptionLabel).font(.caption)
            TextField(Strings.whatDidYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(2...4)

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

    private func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            status = try DayFinisher.status(db: AppEnvironment.db, day: day, targetHours: targetHours)

            var commitsByProject: [UUID: [GitCommit]] = [:]
            for project in projects {
                let author = (try? gitConfigValue(key: "user.email", repoPath: project.path)) ?? ""
                guard !author.isEmpty else { continue }
                let since = Calendar.current.startOfDay(for: day)
                if let commits = try? GitImporter.fetchCommits(repoPath: project.path, author: author, since: since) {
                    commitsByProject[project.id] = commits
                }
            }

            suggestions = try DayFinisher.suggestions(
                db: AppEnvironment.db,
                day: day,
                commitsByProject: commitsByProject,
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
