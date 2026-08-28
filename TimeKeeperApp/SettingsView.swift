import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import TimeKeeperKit

struct SettingsView: View {
    @State private var projects: [Project] = []
    @State private var newProjectName = ""
    @State private var newProjectPath = ""
    @State private var exportError: String?
    @State private var importStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projekty")
                .font(.headline)

            List(projects) { project in
                HStack {
                    VStack(alignment: .leading) {
                        Text(project.name).bold()
                        Text(project.path).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import z gitu") { importGitHistory(for: project) }
                }
            }
            .frame(minHeight: 120)

            if let importStatus {
                Text(importStatus).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                TextField("Název", text: $newProjectName)
                TextField("Cesta", text: $newProjectPath)
                Button("Přidat") { addProject() }
                    .disabled(newProjectName.isEmpty || newProjectPath.isEmpty)
            }

            Divider()

            HStack {
                Button("Export CSV") { export(format: .csv) }
                Button("Export JSON") { export(format: .json) }
            }

            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 420, height: 320)
        .onAppear(perform: reload)
    }

    private enum ExportFormat { case csv, json }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
    }

    private func addProject() {
        let project = Project(name: newProjectName, path: newProjectPath)
        do {
            try AppEnvironment.db.dbQueue.write { try project.insert($0) }
            newProjectName = ""
            newProjectPath = ""
            reload()
        } catch {
            exportError = "Nepodařilo se přidat projekt: \(error.localizedDescription)"
        }
    }

    private func export(format: ExportFormat) {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = format == .csv ? "timekeeper-export.csv" : "timekeeper-export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let rows = try BlockExporter.exportRows(
                db: AppEnvironment.db,
                from: .distantPast,
                to: .distantFuture
            )
            switch format {
            case .csv:
                try BlockExporter.csv(rows: rows).write(to: url, atomically: true, encoding: .utf8)
            case .json:
                try BlockExporter.json(rows: rows).write(to: url)
            }
        } catch {
            exportError = "Export selhal: \(error.localizedDescription)"
        }
    }

    private func importGitHistory(for project: Project) {
        importStatus = "Importuji…"
        do {
            let author = try gitConfigValue(key: "user.email", repoPath: project.path)
            let since = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
            let commits = try GitImporter.fetchCommits(repoPath: project.path, author: author, since: since)
            let sessionizedBlocks = GitImporter.blocks(from: commits)

            let candidates = sessionizedBlocks.map {
                CandidateBlock(projectId: project.id, start: $0.start, end: $0.end, source: .gitCommit)
            }
            let merged = BlockMerger.merge(candidates)
            try ReimportGuard.reconcile(db: AppEnvironment.db, projectId: project.id, candidates: merged)

            importStatus = "Naimportováno \(commits.count) commitů, \(merged.count) bloků."
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            importStatus = "Import selhal: \(error.localizedDescription)"
        }
    }

    private func gitConfigValue(key: String, repoPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "config", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

#Preview {
    SettingsView()
}
