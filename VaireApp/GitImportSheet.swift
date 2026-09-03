import SwiftUI
import WidgetKit
import VaireKit

/// Review sheet for importing git commits as time blocks. Unlike the old
/// one-click import, nothing gets written until the user hits Import — each
/// candidate block can be retimed, renamed, or discarded first, and the
/// import is always scoped to one displayed week rather than a fixed
/// lookback window.
struct GitImportSheet: View {
    let weekStart: Date
    let projects: [Project]
    let onImported: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedProjectId: UUID?
    @State private var candidates: [GitImportCandidate] = []
    @State private var replaceExisting = true
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var resultMessage: String?
    @State private var didImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.gitImportSheetTitle)
                .font(.headline)

            Picker(Strings.gitImportProjectLabel, selection: $selectedProjectId) {
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .onChange(of: selectedProjectId) { _, _ in loadCommits() }

            if isLoading {
                Text(Strings.gitImportLoading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if candidates.isEmpty {
                Text(Strings.gitImportNoCommits)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List($candidates) { $candidate in
                    candidateRow($candidate)
                }
                .frame(minHeight: 200, maxHeight: 320)

                Text(Strings.gitImportCandidateCount(candidates.filter(\.included).count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(Strings.gitImportReplaceExisting, isOn: $replaceExisting)
                .font(.caption)

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if didImport {
                    Button(Strings.close) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(Strings.cancel) { dismiss() }
                    Button(Strings.gitImportCommit) { commit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedProjectId == nil || candidates.filter(\.included).isEmpty)
                }
            }
        }
        .padding()
        .frame(width: 520)
        .onAppear {
            selectedProjectId = projects.first?.id
            loadCommits()
        }
    }

    private func candidateRow(_ candidate: Binding<GitImportCandidate>) -> some View {
        HStack(alignment: .top) {
            Toggle(Strings.gitImportInclude, isOn: candidate.included)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                TextField(Strings.activityDescriptionLabel, text: candidate.note, axis: .vertical)
                    .lineLimit(2...4)
                    .disabled(!candidate.wrappedValue.included)

                HStack {
                    Text(startLabel(candidate.wrappedValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HoursMinutesField(hours: durationHoursBinding(candidate), minutes: durationMinutesBinding(candidate))
                }
                .disabled(!candidate.wrappedValue.included)
            }
            .opacity(candidate.wrappedValue.included ? 1 : 0.4)
        }
        .padding(.vertical, 4)
    }

    private func startLabel(_ candidate: GitImportCandidate) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: candidate.start)
    }

    /// Duration editing (like everywhere else in the app) instead of
    /// separate start/end clock-time pickers — start stays fixed at the
    /// commit-derived time, and editing hours/minutes here moves `end`
    /// only.
    private func durationHoursBinding(_ candidate: Binding<GitImportCandidate>) -> Binding<Int> {
        Binding(
            get: { Int(candidate.wrappedValue.end.timeIntervalSince(candidate.wrappedValue.start) / 3600) },
            set: { newHours in
                let minutes = Int(candidate.wrappedValue.end.timeIntervalSince(candidate.wrappedValue.start) / 60) % 60
                candidate.wrappedValue.end = candidate.wrappedValue.start.addingTimeInterval(TimeInterval(newHours * 3600 + minutes * 60))
            }
        )
    }

    private func durationMinutesBinding(_ candidate: Binding<GitImportCandidate>) -> Binding<Int> {
        Binding(
            get: { Int(candidate.wrappedValue.end.timeIntervalSince(candidate.wrappedValue.start) / 60) % 60 },
            set: { newMinutes in
                let hours = Int(candidate.wrappedValue.end.timeIntervalSince(candidate.wrappedValue.start) / 3600)
                candidate.wrappedValue.end = candidate.wrappedValue.start.addingTimeInterval(TimeInterval(hours * 3600 + newMinutes * 60))
            }
        )
    }

    private func loadCommits() {
        guard let selectedProjectId, let project = projects.first(where: { $0.id == selectedProjectId }) else { return }

        isLoading = true
        loadError = nil
        resultMessage = nil
        candidates = []

        do {
            let author = try gitConfigValue(key: "user.email", repoPath: project.path)
            let since = weekStart.addingTimeInterval(-1) // fetchCommits' --since is exclusive-ish at the boundary; back off a second so the week's first commit isn't dropped
            let commits = try GitImporter.fetchCommits(repoPath: project.path, author: author, since: since)
            candidates = GitImportReviewer.candidates(from: commits, weekStart: weekStart)
        } catch {
            loadError = Strings.gitImportFailed(error.localizedDescription)
        }

        isLoading = false
    }

    private func commit() {
        guard let selectedProjectId else { return }
        let roundedCandidates = candidates.map { candidate -> GitImportCandidate in
            var candidate = candidate
            let totalMinutes = Int(candidate.end.timeIntervalSince(candidate.start) / 60)
            let rounded = HoursMinutesField.roundedUp(totalMinutes: totalMinutes)
            candidate.end = candidate.start.addingTimeInterval(TimeInterval((rounded.hours * 60 + rounded.minutes) * 60))
            return candidate
        }
        do {
            try GitImportReviewer.commit(
                db: AppEnvironment.db,
                projectId: selectedProjectId,
                candidates: roundedCandidates,
                weekStart: weekStart,
                replacingExisting: replaceExisting
            )
            resultMessage = Strings.gitImportSuccess(candidates.filter(\.included).count)
            didImport = true
            WidgetCenter.shared.reloadAllTimelines()
            DataChangeNotifier.post()
            onImported()
        } catch {
            loadError = Strings.gitImportFailed(error.localizedDescription)
        }
    }
}
