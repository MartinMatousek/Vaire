import SwiftUI
import WidgetKit
import TimeKeeperKit

struct ContentView: View {
    @State private var timer = AppEnvironment.timer
    @State private var projects: [Project] = []
    @State private var todayHours: Double = 0
    @State private var tick = 0
    @State private var justStoppedBlock: Block?
    @State private var noteDraft: String = ""

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
                toggleTimer(for: project.id)
            }
            .popover(isPresented: Binding(
                get: { justStoppedBlock?.projectId == project.id },
                set: { if !$0 { justStoppedBlock = nil } }
            )) {
                noteEditorAfterStop
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

    private var noteEditorAfterStop: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popis aktivity").font(.caption).bold()
            TextField("Co jsi dělal…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)
            HStack {
                Spacer()
                Button("Přeskočit") { justStoppedBlock = nil }
                Button("Uložit") { saveNoteForStoppedBlock() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func toggleTimer(for projectId: UUID) {
        if timer.isRunning(projectId: projectId) {
            let stoppedBlock = try? timer.stop(projectId: projectId)
            refreshTodayHours()
            WidgetCenter.shared.reloadAllTimelines()
            if let stoppedBlock {
                noteDraft = ""
                justStoppedBlock = stoppedBlock
            }
        } else {
            timer.start(projectId: projectId)
        }
    }

    private func saveNoteForStoppedBlock() {
        guard let block = justStoppedBlock else { return }
        _ = try? BlockEditor.setNote(db: AppEnvironment.db, blockId: block.id, note: noteDraft)
        justStoppedBlock = nil
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
