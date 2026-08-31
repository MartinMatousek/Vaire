import SwiftUI
import WidgetKit
import TimeKeeperKit

struct ContentView: View {
    @State private var timer = AppEnvironment.timer
    @State private var projects: [Project] = []
    @State private var todayHours: Double = 0
    @State private var tick = 0
    @State private var startingProjectId: UUID?
    @State private var stoppedBlock: Block?
    @State private var noteDraft: String = ""
    @State private var startDraft: Date = .now
    @State private var endDraft: Date = .now

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
            Text("Popis aktivity (než zapomeneš)").font(.caption).bold()
            TextField("Co budeš dělat…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)
            HStack {
                Spacer()
                Button("Bez poznámky") { startTimer(for: projectId, note: nil) }
                Button("Start") { startTimer(for: projectId, note: noteDraft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var editorAfterStop: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uprav čas a popis").font(.caption).bold()

            DatePicker("Start", selection: $startDraft, displayedComponents: [.hourAndMinute])
            DatePicker("Konec", selection: $endDraft, displayedComponents: [.hourAndMinute])

            TextField("Co jsi dělal…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 240)

            HStack {
                roundingButton("−15 min") { endDraft.addTimeInterval(-15 * 60) }
                roundingButton("+15 min") { endDraft.addTimeInterval(15 * 60) }
                Spacer()
                Button("Zahodit") { stoppedBlock = nil }
                Button("Uložit") { saveStoppedBlock() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func roundingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2)
    }

    private func handleTap(for projectId: UUID) {
        if timer.isRunning(projectId: projectId) {
            stopTimer(for: projectId)
        } else {
            noteDraft = ""
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
            startDraft = block.start
            endDraft = block.end
            stoppedBlock = block
        }
    }

    private func saveStoppedBlock() {
        guard let block = stoppedBlock else { return }
        do {
            _ = try BlockEditor.setTimes(db: AppEnvironment.db, blockId: block.id, start: startDraft, end: endDraft)
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
