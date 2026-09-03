import SwiftUI
import VaireKit

/// Uploads a day (or several days, for a week) of logged blocks to Trask.
/// Deliberately semi-automatic: `TraskScraper.fillEntry` fills one Trask
/// form and stops before Save — the user reviews it in their own Chrome
/// window and clicks Save themselves. This view's job is sequencing which
/// block comes next and surfacing failures, never detecting or performing
/// the actual submit.
struct UploadFlowView: View {
    let blocksToUpload: [Block]
    let projects: [UUID: Project]

    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case checkingPairings
        case needsRepairing([Project])
        case preparingChrome
        case chromeNotReady(String)
        case uploading
        case done
    }

    @State private var stage: Stage = .checkingPairings
    @State private var currentIndex = 0
    @State private var fillError: String?
    @State private var isFilling = false

    private var currentBlock: Block? {
        guard currentIndex < blocksToUpload.count else { return nil }
        return blocksToUpload[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch stage {
            case .checkingPairings, .preparingChrome:
                ProgressView()

            case .needsRepairing(let staleProjects):
                Text(Strings.uploadNeedsRepairing)
                    .font(.headline)
                ForEach(staleProjects) { project in
                    Text(project.name).font(.callout)
                }
                HStack {
                    Spacer()
                    Button(Strings.cancel) { dismiss() }
                    Button(Strings.uploadOpenSettings) {
                        SettingsWindowController.shared.show()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }

            case .chromeNotReady(let message):
                Text(message)
                    .font(.callout)
                HStack {
                    Spacer()
                    Button(Strings.cancel) { dismiss() }
                    Button(Strings.uploadOpenSettings) {
                        SettingsWindowController.shared.show()
                        dismiss()
                    }
                    Button(Strings.uploadNext) { prepareChrome() }
                        .keyboardShortcut(.defaultAction)
                }

            case .uploading:
                uploadingBody

            case .done:
                Text(Strings.uploadComplete)
                    .font(.headline)
                HStack {
                    Spacer()
                    Button(Strings.finishDayDone) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear(perform: checkPairings)
    }

    private var uploadingBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.uploadEntryProgress(current: currentIndex + 1, total: blocksToUpload.count))
                .font(.headline)

            if let block = currentBlock {
                Text(projects[block.projectId]?.name ?? "?")
                    .font(.callout).bold()
                Text(DurationFormatter.hoursMinutes(block.duration / 3600))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = block.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }

            if isFilling {
                ProgressView()
            } else if let fillError {
                Text(Strings.uploadFillFailed(fillError))
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(Strings.uploadEntryFilled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(Strings.uploadCancel) { dismiss() }
                    .foregroundStyle(.red)
                Spacer()
                Button(Strings.uploadSkipEntry) { advance() }
                    .disabled(isFilling)
                Button(Strings.uploadNext) { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isFilling || fillError != nil)
            }
        }
    }

    private func checkPairings() {
        let involvedProjects = Set(blocksToUpload.map(\.projectId)).compactMap { projects[$0] }
        let staleProjects = involvedProjects.filter { project in
            (try? TraskCatalog.validatePairing(db: AppEnvironment.db, project: project)) != nil
        }

        if !staleProjects.isEmpty {
            stage = .needsRepairing(staleProjects.sorted { $0.name < $1.name })
        } else {
            prepareChrome()
        }
    }

    /// Launches the debug Chrome profile if needed and attempts login (via
    /// 1Password if enabled) before the first fill — rather than only
    /// discovering a missing/logged-out Chrome once the first entry's fill
    /// fails partway through, which would look identical to a per-entry
    /// fill error. Never attempts to clear 2FA itself.
    private func prepareChrome() {
        stage = .preparingChrome
        Task {
            do {
                let status = try await TraskScraper.ensureReady()
                await MainActor.run {
                    switch status {
                    case .ready:
                        beginUpload()
                    case .awaitingTwoFactor:
                        stage = .chromeNotReady(Strings.uploadAwaiting2FA)
                    case .loginRequired:
                        stage = .chromeNotReady(Strings.uploadLoginRequired)
                    }
                }
            } catch {
                await MainActor.run {
                    stage = .chromeNotReady(Strings.uploadEnsureReadyFailed(error.localizedDescription))
                }
            }
        }
    }

    private func beginUpload() {
        stage = .uploading
        fillCurrentEntry()
    }

    private func advance() {
        currentIndex += 1
        if currentIndex >= blocksToUpload.count {
            stage = .done
        } else {
            fillCurrentEntry()
        }
    }

    private func fillCurrentEntry() {
        guard let block = currentBlock, let project = projects[block.projectId] else {
            advance()
            return
        }

        fillError = nil
        isFilling = true

        Task {
            do {
                let entryJSON = try makeEntryJSON(block: block, project: project)
                try await TraskScraper.fillEntry(entryJSON: entryJSON)
                await MainActor.run { isFilling = false }
            } catch {
                await MainActor.run {
                    isFilling = false
                    fillError = error.localizedDescription
                }
            }
        }
    }

    private func makeEntryJSON(block: Block, project: Project) throws -> String {
        guard let traskProject = try traskProjectLabel(for: project) else {
            throw TraskScraperError.malformedOutput
        }
        let taskId = block.traskTaskId ?? project.defaultTraskTaskId
        let taskLabel = try taskId.flatMap { try traskTaskLabel(id: $0) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current // match Calendar.current's day boundary used everywhere else
        let totalMinutes = Int((block.duration / 60).rounded())

        let payload: [String: Any] = [
            "projectLabel": traskProject,
            "taskLabel": taskLabel ?? "",
            "dateISO": dateFormatter.string(from: block.start),
            "hours": totalMinutes / 60,
            "minutes": totalMinutes % 60,
            "description": block.note ?? "",
            "remoteWork": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func traskProjectLabel(for project: Project) throws -> String? {
        guard let traskProjectId = project.traskProjectId else { return nil }
        return try AppEnvironment.db.dbQueue.read { conn in
            try TraskProject.fetchOne(conn, key: traskProjectId)?.label
        }
    }

    private func traskTaskLabel(id: String) throws -> String? {
        try AppEnvironment.db.dbQueue.read { conn in
            try TraskTask.fetchOne(conn, key: id)?.label
        }
    }
}
