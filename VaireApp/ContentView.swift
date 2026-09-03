import SwiftUI
import WidgetKit
import VaireKit
import GRDB

struct ContentView: View {
    @State private var timer = AppEnvironment.timer
    @State private var projects: [Project] = []
    @State private var todayHours: Double = 0
    @State private var tick = 0
    @State private var startingProjectId: UUID?
    @State private var todaysBlocksForStartingProject: [Block] = []
    @State private var resumeSelection: UUID? // nil = "new entry"
    @State private var stoppedBlock: Block?
    @State private var noteDraft: String = ""
    @State private var estimateHoursDraft: Int = 0
    @State private var estimateMinutesDraft: Int = 0
    @State private var showingFinishDay = false

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            DayProgressRing(hoursWorked: todayHours + runningHoursAcrossAllProjects, targetHours: 8)
                .frame(width: 72, height: 72)

            Text(formattedTotal)
                .font(.headline)

            if projects.isEmpty {
                Text(Strings.noProjects)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(projects) { project in
                        projectRow(project)
                    }
                }
            }

            Divider()

            Button(Strings.finishDay) {
                showingFinishDay = true
            }
            .buttonStyle(.link)
            .disabled(projects.isEmpty)
            .sheet(isPresented: $showingFinishDay) {
                FinishDayView(day: .now, projects: projects, targetHours: 8, onChanged: reload)
            }

            Button(Strings.week) {
                WeekWindowController.shared.show()
            }
            .buttonStyle(.link)

            Button(Strings.settings) {
                openSettings()
            }
            .buttonStyle(.link)

            Button(Strings.quit) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(width: 260)
        .onAppear(perform: reload)
        .onReceive(refreshTimer) { _ in
            tick += 1
            refreshTodayHours()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaireDataChanged)) { _ in
            reload()
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name)
                    .font(.callout)
                if timer.isRunning(projectId: project.id) {
                    Text(elapsedLabel(project))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(timer.isRunning(projectId: project.id) ? Strings.stop : Strings.start) {
                handleTap(for: project.id)
            }
            .popover(isPresented: Binding(
                get: { startingProjectId == project.id },
                set: { if !$0 { startingProjectId = nil } }
            )) {
                noteEditorBeforeStart(projectId: project.id)
            }
            .popover(isPresented: Binding(
                get: { stoppedBlock?.projectId == project.id },
                set: { if !$0 { stoppedBlock = nil } }
            )) {
                if let stoppedBlock, stoppedBlock.projectId == project.id {
                    StoppedBlockEditorView(block: stoppedBlock) { _ in
                        self.stoppedBlock = nil
                        refreshTodayHours()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
            Button(Strings.unfollow) {
                unfollow(project)
            }
            .buttonStyle(.link)
            .foregroundStyle(.secondary)
            .disabled(timer.isRunning(projectId: project.id))
        }
    }

    private func elapsedLabel(_ project: Project) -> String {
        DurationFormatter.hoursMinutes(timer.elapsed(projectId: project.id) / 3600)
    }

    private var runningHoursAcrossAllProjects: Double {
        projects.reduce(0.0) { $0 + timer.elapsed(projectId: $1.id) / 3600 }
    }

    private var formattedTotal: String {
        let hours = todayHours + runningHoursAcrossAllProjects
        return "\(DurationFormatter.hoursMinutes(hours)) / 8h"
    }

    private func noteEditorBeforeStart(projectId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !todaysBlocksForStartingProject.isEmpty {
                Text(Strings.resumeTodaysEntry).font(.caption).bold()
                Picker("", selection: $resumeSelection) {
                    Text(Strings.newEntry).tag(UUID?.none)
                    ForEach(todaysBlocksForStartingProject) { block in
                        Text(resumeOptionLabel(block)).tag(Optional(block.id))
                    }
                }
                .labelsHidden()
                .onChange(of: resumeSelection) { _, newValue in
                    if let block = todaysBlocksForStartingProject.first(where: { $0.id == newValue }) {
                        noteDraft = block.note ?? ""
                    }
                }
            }

            Text(Strings.activityDescription).font(.caption).bold()
            TextField(Strings.whatWillYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)

            if resumeSelection == nil {
                Text(Strings.effortEstimateHours).font(.caption)
                HoursMinutesField(hours: $estimateHoursDraft, minutes: $estimateMinutesDraft)
            }

            HStack {
                Spacer()
                if resumeSelection == nil {
                    Button(Strings.withoutNote) { startTimer(for: projectId, note: nil, estimate: nil) }
                }
                Button(resumeSelection == nil ? Strings.start : Strings.resume) {
                    if let blockId = resumeSelection,
                       let block = todaysBlocksForStartingProject.first(where: { $0.id == blockId }) {
                        resumeTimer(for: block)
                        startingProjectId = nil
                    } else {
                        let rounded = HoursMinutesField.roundedUp(totalMinutes: estimateHoursDraft * 60 + estimateMinutesDraft)
                        let estimateHours = Double(rounded.hours * 60 + rounded.minutes) / 60
                        startTimer(for: projectId, note: noteDraft, estimate: estimateHours > 0 ? estimateHours : nil)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func resumeOptionLabel(_ block: Block) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeLabel = timeFormatter.string(from: block.start)
        let durationLabel = DurationFormatter.hoursMinutes(block.duration / 3600)
        if let note = block.note, !note.isEmpty {
            return "\(timeLabel) (\(durationLabel)) — \(note)"
        }
        return "\(timeLabel) (\(durationLabel))"
    }

    private func handleTap(for projectId: UUID) {
        if timer.isRunning(projectId: projectId) {
            stopTimer(for: projectId)
        } else {
            noteDraft = ""
            estimateHoursDraft = 0
            estimateMinutesDraft = 0
            resumeSelection = nil
            todaysBlocksForStartingProject = (try? DailySummary.todaysBlocks(db: AppEnvironment.db, projectId: projectId)) ?? []
            startingProjectId = projectId
        }
    }

    private func startTimer(for projectId: UUID, note: String?, estimate: Double?) {
        timer.start(projectId: projectId, note: note, estimatedHours: estimate)
        startingProjectId = nil
    }

    private func stopTimer(for projectId: UUID) {
        let block = try? timer.stop(projectId: projectId)
        refreshTodayHours()
        WidgetCenter.shared.reloadAllTimelines()
        if let block {
            stoppedBlock = block
        }
    }

    private func resumeTimer(for block: Block) {
        do {
            try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
        } catch {
            // Nothing to resume onto if the delete fails — leave the
            // earlier block as-is rather than double-track it.
            return
        }
        timer.resume(projectId: block.projectId, from: block.start, note: block.note)
        refreshTodayHours()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func unfollow(_ project: Project) {
        var updated = project
        updated.hooksEnabled = false
        try? AppEnvironment.db.dbQueue.write { try updated.update($0) }
        reload()
        DataChangeNotifier.post()
    }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read {
            try Project.filter(Column("hooksEnabled") == true).fetchAll($0)
        }) ?? []
        refreshTodayHours()
    }

    private func refreshTodayHours() {
        todayHours = (try? DailySummary.totalHours(db: AppEnvironment.db, day: .now)) ?? 0
    }

    private func openSettings() {
        SettingsWindowController.shared.show()
    }
}

#Preview {
    ContentView()
}
