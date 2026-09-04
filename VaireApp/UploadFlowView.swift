import AppKit
import SwiftUI
import VaireKit

/// Uploads a day (or several days, for a week) of logged blocks to the
/// external timesheet. Fully automatic: `session.fillEntry` fills one
/// timesheet form and clicks Save, this view auto-advances to the next
/// block on success and only stops to show a Retry/Skip choice on failure.
/// One `TimesheetUploadSession` (a single long-lived Node/Playwright
/// process) serves the whole batch — see its doc comment for why.
/// Duplicate protection is the one-time batch check in `beginUpload()`
/// (`isDuplicate`), not anything per-entry — see its doc comment for why.
///
/// History: reverted to semi-automatic (2026-09-04) after a
/// fully-automatic version created real duplicate entries in the user's
/// live timesheet. Re-enabled (2026-09-04) after live full upload+Save
/// cycles, including re-runs over already-uploaded weeks, showed no
/// duplicates with the existing batch dedup — see fillEntry.mjs's header
/// for the same note.
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
    @State private var session = TimesheetUploadSession()
    @State private var currentIndex = 0
    @State private var fillError: String?
    @State private var isFilling = false
    @State private var duplicateSkippedCount = 0
    /// Populated once in `beginUpload()`, before the fill loop starts —
    /// never re-checked per entry and never updated as entries fill
    /// (checked only against what the timesheet had *before* this upload
    /// began, so two real, separate same-day sessions on the same
    /// project+task aren't mistaken for duplicates of each other —
    /// confirmed live that checking within-batch entries caused exactly
    /// that false positive). A date not present as a key means it wasn't in
    /// the timesheet's visible week when checked — no dedup guarantee for
    /// it.
    @State private var existingEntriesByDate: [String: [TimesheetScraper.ExistingEntry]] = [:]

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
                if duplicateSkippedCount > 0 {
                    Text(Strings.uploadDuplicatesSkipped(duplicateSkippedCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onDisappear {
            // Backstop for every dismissal path (Cancel button, Done
            // button, window closed directly) — `session.stop()` is
            // idempotent, so this is safe even when a call site above
            // already stopped it explicitly.
            Task { await session.stop() }
        }
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
            }

            HStack {
                Button(Strings.uploadCancel) { dismiss() }
                    .foregroundStyle(.red)
                Spacer()
                if fillError != nil {
                    Button(Strings.uploadSkipEntry) { advance() }
                    Button(Strings.uploadRetry) { fillCurrentEntry() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func checkPairings() {
        let involvedProjects = Set(blocksToUpload.map(\.projectId)).compactMap { projects[$0] }
        let staleProjects = involvedProjects.filter { project in
            (try? TimesheetCatalog.validatePairing(db: AppEnvironment.db, project: project)) != nil
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
        let onePasswordItemId: String? = {
            let setting = OnePasswordSetting.current()
            return setting.isEnabled ? setting.itemId : nil
        }()
        Task {
            do {
                let status = try await session.start(onePasswordItemId: onePasswordItemId)
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
                await session.stop()
                await MainActor.run {
                    stage = .chromeNotReady(Strings.uploadEnsureReadyFailed(error.localizedDescription))
                }
            }
        }
    }

    private func beginUpload() {
        stage = .uploading
        Task {
            // Best-effort: a failure here shouldn't block the upload, just
            // means duplicates won't be auto-skipped this run.
            let existing = (try? await session.checkExistingEntries()) ?? [:]
            await MainActor.run {
                existingEntriesByDate = existing
                fillCurrentEntry()
            }
        }
    }

    private func advance() {
        currentIndex += 1
        if currentIndex >= blocksToUpload.count {
            stage = .done
            Task { await session.stop() }
            // Chrome holds focus through the fill/Save loop (that's where
            // the actual clicks happen) — bring Vaire's window back to
            // front so the done screen is actually seen once the batch
            // finishes.
            WeekWindowController.shared.show()
        } else {
            fillCurrentEntry()
        }
    }

    /// Auto-skips (no fill, no Chrome interaction) a block whose
    /// project+note+date exactly matches something the timesheet already
    /// had *before* this upload began — see `existingEntriesByDate`'s doc
    /// comment for why the check is against that one-time snapshot only.
    /// Matches on note, not task: confirmed live the timesheet's calendar
    /// view (the only source this check has) shows "Project | Note", never the
    /// task category — an earlier version compared against task and
    /// produced systematic false negatives (every real duplicate's task
    /// category compared against the other entry's note text and never
    /// matched).
    private func isDuplicate(block: Block, project: Project) -> Bool {
        guard let (_, dateISO, projectLabel, note) = try? makeEntryComponents(block: block, project: project) else {
            return false
        }
        let existing = existingEntriesByDate[dateISO] ?? []
        // A timesheet project label here can be a suffix of the full dropdown
        // label (e.g. "Produkty a KVK - FY27 - ET97" vs. "ČEZ Prodej -
        // Produkty a KVK - FY27 - ET97"), confirmed live, so match with
        // .hasSuffix, not exact equality.
        return existing.contains { projectLabel.hasSuffix($0.projectLabel) && $0.note == note }
    }

    private func fillCurrentEntry() {
        guard let block = currentBlock, let project = projects[block.projectId] else {
            advance()
            return
        }

        if isDuplicate(block: block, project: project) {
            duplicateSkippedCount += 1
            advance()
            return
        }

        fillError = nil
        isFilling = true

        Task {
            do {
                let (payload, _, _, _) = try makeEntryComponents(block: block, project: project)
                try await session.fillEntry(payload: payload)
                await MainActor.run {
                    isFilling = false
                    advance()
                }
            } catch {
                await MainActor.run {
                    isFilling = false
                    fillError = error.localizedDescription
                }
            }
        }
    }

    /// Looks up the timesheet project/task labels, note, and dateISO for
    /// `block`, shared by `isDuplicate` (which only needs project+note)
    /// and `fillCurrentEntry` (which needs the full payload) so the DB
    /// lookups happen once per call site rather than being duplicated.
    private func makeEntryComponents(block: Block, project: Project) throws -> (payload: [String: Any], dateISO: String, projectLabel: String, note: String) {
        guard let timesheetProject = try timesheetProjectLabel(for: project) else {
            throw TimesheetScraperError.malformedOutput
        }
        let taskId = block.timesheetTaskId ?? project.defaultTimesheetTaskId
        let taskLabel = try taskId.flatMap { try timesheetTaskLabel(id: $0) } ?? ""
        let note = block.note ?? ""

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current // match Calendar.current's day boundary used everywhere else
        let dateISO = dateFormatter.string(from: block.start)
        let totalMinutes = Int((block.duration / 60).rounded())

        let payload: [String: Any] = [
            "projectLabel": timesheetProject,
            "taskLabel": taskLabel,
            "dateISO": dateISO,
            "hours": totalMinutes / 60,
            "minutes": totalMinutes % 60,
            "description": note,
            "remoteWork": false,
        ]
        return (payload, dateISO, timesheetProject, note)
    }

    private func timesheetProjectLabel(for project: Project) throws -> String? {
        guard let timesheetProjectId = project.timesheetProjectId else { return nil }
        return try AppEnvironment.db.dbQueue.read { conn in
            try TimesheetProject.fetchOne(conn, key: timesheetProjectId)?.label
        }
    }

    private func timesheetTaskLabel(id: String) throws -> String? {
        try AppEnvironment.db.dbQueue.read { conn in
            try TimesheetTask.fetchOne(conn, key: id)?.label
        }
    }
}
