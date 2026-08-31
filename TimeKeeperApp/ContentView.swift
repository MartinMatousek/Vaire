import SwiftUI
import WidgetKit
import TimeKeeperKit

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
    @State private var hoursDraft: Int = 0
    @State private var minutesDraft: Int = 0

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            DayProgressRing(hoursWorked: todayHours + runningHoursAcrossAllProjects, targetHours: 8)
                .frame(width: 72, height: 72)

            Text(formattedTotal)
                .font(.headline)

            if projects.isEmpty {
                Text("Žádné projekty. Přidej je v nastavení.")
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

            Button("Týden…") {
                WeekWindowController.shared.show()
            }
            .buttonStyle(.link)

            Button("Nastavení…") {
                openSettings()
            }
            .buttonStyle(.link)

            Button("Ukončit") {
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
            Button(timer.isRunning(projectId: project.id) ? "Stop" : "Start") {
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
                editorAfterStop
            }
        }
    }

    private func elapsedLabel(_ project: Project) -> String {
        let hours = timer.elapsed(projectId: project.id) / 3600
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var runningHoursAcrossAllProjects: Double {
        projects.reduce(0.0) { $0 + timer.elapsed(projectId: $1.id) / 3600 }
    }

    private var formattedTotal: String {
        let hours = todayHours + runningHoursAcrossAllProjects
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m / 8h"
    }

    private func noteEditorBeforeStart(projectId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !todaysBlocksForStartingProject.isEmpty {
                Text("Navázat na dnešní záznam?").font(.caption).bold()
                Picker("", selection: $resumeSelection) {
                    Text("Nový záznam").tag(UUID?.none)
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

            Text("Popis aktivity (než zapomeneš)").font(.caption).bold()
            TextField("Co budeš dělat…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)
            HStack {
                Spacer()
                if resumeSelection == nil {
                    Button("Bez poznámky") { startTimer(for: projectId, note: nil) }
                }
                Button(resumeSelection == nil ? "Start" : "Navázat") {
                    if let blockId = resumeSelection,
                       let block = todaysBlocksForStartingProject.first(where: { $0.id == blockId }) {
                        resumeTimer(for: block)
                        startingProjectId = nil
                    } else {
                        startTimer(for: projectId, note: noteDraft)
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
        let hours = block.duration / 3600
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        let timeLabel = timeFormatter.string(from: block.start)
        let durationLabel = "\(h)h \(m)m"
        if let note = block.note, !note.isEmpty {
            return "\(timeLabel) (\(durationLabel)) — \(note)"
        }
        return "\(timeLabel) (\(durationLabel))"
    }

    private var editorAfterStop: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uprav čas a popis").font(.caption).bold()

            if let stoppedBlock {
                Text("Naměřeno na timeru: \(realElapsedLabel(stoppedBlock))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HoursMinutesField(hours: $hoursDraft, minutes: $minutesDraft)

            TextField("Co jsi dělal…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 240)

            HStack {
                Spacer()
                Button("Zahodit") { stoppedBlock = nil }
                if let stoppedBlock {
                    Button("Pokračovat") { resumeTimer(for: stoppedBlock) }
                }
                Button("Uložit") { saveStoppedBlock() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func realElapsedLabel(_ block: Block) -> String {
        let hours = block.duration / 3600
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private func handleTap(for projectId: UUID) {
        if timer.isRunning(projectId: projectId) {
            stopTimer(for: projectId)
        } else {
            noteDraft = ""
            resumeSelection = nil
            todaysBlocksForStartingProject = (try? DailySummary.todaysBlocks(db: AppEnvironment.db, projectId: projectId)) ?? []
            startingProjectId = projectId
        }
    }

    private func startTimer(for projectId: UUID, note: String?) {
        timer.start(projectId: projectId, note: note)
        startingProjectId = nil
    }

    private func stopTimer(for projectId: UUID) {
        let block = try? timer.stop(projectId: projectId)
        refreshTodayHours()
        WidgetCenter.shared.reloadAllTimelines()
        if let block {
            noteDraft = block.note ?? ""
            let totalMinutes = Int(block.duration / 60)
            hoursDraft = totalMinutes / 60
            minutesDraft = totalMinutes % 60
            stoppedBlock = block
        }
    }

    private func saveStoppedBlock() {
        guard let block = stoppedBlock else { return }
        let newEnd = block.start.addingTimeInterval(Double(hoursDraft * 3600 + minutesDraft * 60))
        do {
            _ = try BlockEditor.setTimes(db: AppEnvironment.db, blockId: block.id, start: block.start, end: newEnd)
            _ = try BlockEditor.setNote(db: AppEnvironment.db, blockId: block.id, note: noteDraft)
        } catch {
            // Block was already persisted by stop(); a failed correction
            // just means the raw times/no note stand — not worth surfacing
            // a menu-bar error for.
        }
        stoppedBlock = nil
        refreshTodayHours()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resumeTimer(for block: Block) {
        do {
            try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
        } catch {
            // Nothing to resume onto if the delete fails — leave the
            // stopped block as-is rather than double-track it.
            return
        }
        timer.resume(projectId: block.projectId, from: block.start, note: block.note)
        stoppedBlock = nil
        refreshTodayHours()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
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
