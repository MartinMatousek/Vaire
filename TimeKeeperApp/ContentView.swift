import SwiftUI
import TimeKeeperKit

struct ContentView: View {
    @State private var timer = AppEnvironment.timer
    @State private var projects: [Project] = []
    @State private var selectedProjectId: UUID?
    @State private var todayHours: Double = 0
    @State private var tick = 0

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            DayProgressRing(hoursWorked: todayHours + runningHours, targetHours: 8)
                .frame(width: 72, height: 72)

            Text(formattedTotal)
                .font(.headline)

            if projects.isEmpty {
                Text("Žádné projekty. Přidej je v nastavení.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Projekt", selection: $selectedProjectId) {
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()
                .disabled(timer.isRunning)

                Button(timer.isRunning ? "Stop" : "Start") {
                    toggleTimer()
                }
                .disabled(!timer.isRunning && selectedProjectId == nil)
            }

            Divider()

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
        .frame(width: 240)
        .onAppear(perform: reload)
        .onReceive(refreshTimer) { _ in
            tick += 1
            refreshTodayHours()
        }
    }

    private var runningHours: Double {
        timer.isRunning ? timer.elapsed() / 3600 : 0
    }

    private var formattedTotal: String {
        let hours = todayHours + runningHours
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m / 8h"
    }

    private func toggleTimer() {
        if timer.isRunning {
            try? timer.stop()
            refreshTodayHours()
        } else if let projectId = selectedProjectId {
            timer.start(projectId: projectId)
        }
    }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
        if selectedProjectId == nil {
            selectedProjectId = projects.first?.id
        }
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
