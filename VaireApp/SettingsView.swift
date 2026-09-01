import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import VaireKit

struct SettingsView: View {
    @State private var projects: [Project] = []
    @State private var newProjectName = ""
    @State private var newProjectPath = ""
    @State private var exportError: String?
    @State private var importStatus: String?
    @State private var selectedLanguage: AppLanguage = AppLanguage.current()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
        }
        .frame(width: 520, height: 480)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .vaireDataChanged)) { _ in
            reload()
        }
    }

    private var content: some View {
        Group {
            Text(Strings.projects)
                .font(.headline)

            List(projects) { project in
                HStack {
                    VStack(alignment: .leading) {
                        Text(project.name).bold()
                        Text(project.path).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(Strings.track, isOn: hooksEnabledBinding(for: project))
                        .toggleStyle(.checkbox)
                    Button(Strings.importFromGit) { importGitHistory(for: project) }
                        .help(Strings.importFromGitHelp)
                }
            }
            .frame(minHeight: 120, maxHeight: 200)

            if let importStatus {
                Text(importStatus).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                TextField(Strings.name, text: $newProjectName)
                TextField(Strings.path, text: $newProjectPath)
                Button(Strings.choose) { pickProjectPath() }
                Button(Strings.add) { addProject() }
                    .disabled(newProjectName.isEmpty || newProjectPath.isEmpty)
            }

            Text(Strings.addProjectHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button(Strings.exportCSV) { export(format: .csv) }
                Button(Strings.exportJSON) { export(format: .json) }
            }

            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }

            Divider()

            Picker(Strings.languageLabel, selection: $selectedLanguage) {
                Text(Strings.languageCzech).tag(AppLanguage.cs)
                Text(Strings.languageEnglish).tag(AppLanguage.en)
            }
            .onChange(of: selectedLanguage) { _, newValue in
                try? AppLanguage.set(newValue)
            }

            Text(Strings.languageRestartHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private enum ExportFormat { case csv, json }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
    }

    private func addProject() {
        let project = Project(name: newProjectName, path: newProjectPath, hooksEnabled: true)
        do {
            try AppEnvironment.db.dbQueue.write { try project.insert($0) }
            newProjectName = ""
            newProjectPath = ""
            reload()
            DataChangeNotifier.post()
        } catch {
            exportError = Strings.addProjectFailed(error.localizedDescription)
        }
    }

    private func pickProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        newProjectPath = url.path
        if newProjectName.isEmpty {
            newProjectName = url.lastPathComponent
        }
    }

    private func hooksEnabledBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { project.hooksEnabled },
            set: { newValue in setHooksEnabled(newValue, for: project) }
        )
    }

    private func setHooksEnabled(_ enabled: Bool, for project: Project) {
        var updated = project
        updated.hooksEnabled = enabled
        do {
            try AppEnvironment.db.dbQueue.write { try updated.update($0) }
            reload()
            DataChangeNotifier.post()
        } catch {
            exportError = Strings.trackToggleFailed(error.localizedDescription)
        }
    }

    private func export(format: ExportFormat) {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = format == .csv ? "vaire-export.csv" : "vaire-export.json"

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
            exportError = Strings.exportFailed(error.localizedDescription)
        }
    }

    private func importGitHistory(for project: Project) {
        importStatus = Strings.importing
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

            importStatus = Strings.importSummary(commits: commits.count, blocks: merged.count)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            importStatus = Strings.importFailed(error.localizedDescription)
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
