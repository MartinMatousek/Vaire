import SwiftUI
import UniformTypeIdentifiers
import VaireKit

struct SettingsView: View {
    @State private var projects: [Project] = []
    @State private var newProjectName = ""
    @State private var newProjectPath = ""
    @State private var exportError: String?
    @State private var selectedLanguage: AppLanguage = AppLanguage.current()
    @State private var traskProjects: [TraskProject] = []
    @State private var traskTasks: [TraskTask] = []
    @State private var traskPairingIssues: [UUID: TraskPairingIssue] = [:]
    @State private var onePasswordSetting = OnePasswordSetting.current()
    @State private var showingOnePasswordPicker = false
    @State private var isRefreshingTraskCatalog = false
    @State private var traskError: String?
    @State private var traskRefreshMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
        }
        .frame(width: 520, height: 480)
        .onAppear {
            reload()
        }
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
                }
            }
            .frame(minHeight: 120, maxHeight: 200)

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

            Text(Strings.gitImportMovedHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text(Strings.traskSectionTitle)
                .font(.headline)

            ForEach(projects) { project in
                traskPairingRow(project)
            }

            HStack {
                Button(Strings.traskRefreshCatalog) { refreshTraskCatalog() }
                    .disabled(isRefreshingTraskCatalog)
                if isRefreshingTraskCatalog {
                    Text(Strings.traskRefreshing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let traskRefreshMessage {
                Text(traskRefreshMessage).font(.caption).foregroundStyle(.secondary)
            }
            if let traskError {
                Text(traskError).font(.caption).foregroundStyle(.red)
            }

            Toggle(Strings.onePasswordUseForLogin, isOn: onePasswordEnabledBinding)
                .toggleStyle(.checkbox)

            if onePasswordSetting.isEnabled {
                HStack {
                    Button(Strings.onePasswordChooseItem) { showingOnePasswordPicker = true }
                    Text(onePasswordItemDisplayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .sheet(isPresented: $showingOnePasswordPicker) {
                    OnePasswordItemPickerView { item in
                        setOnePasswordItem(item)
                    }
                }
            }

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

    private var activeTraskProjectsSorted: [TraskProject] {
        traskProjects.filter(\.active).sorted { $0.label < $1.label }
    }

    private func activeTasks(for traskProjectId: String?) -> [TraskTask] {
        guard let traskProjectId else { return [] }
        return traskTasks
            .filter { $0.traskProjectId == traskProjectId && $0.active }
            .sorted { $0.label < $1.label }
    }

    private func traskPairingRow(_ project: Project) -> some View {
        let pairingIssue = traskPairingIssues[project.id]

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name).font(.callout)

                Picker(Strings.traskProjectLabel, selection: traskProjectBinding(for: project)) {
                    Text(Strings.traskNoPairing).tag(Optional<String>.none)
                    ForEach(activeTraskProjectsSorted) { traskProject in
                        Text(traskProject.label).tag(Optional(traskProject.id))
                    }
                }
                .labelsHidden()

                Picker(Strings.traskDefaultTaskLabel, selection: defaultTraskTaskBinding(for: project)) {
                    Text(Strings.traskNoPairing).tag(Optional<String>.none)
                    ForEach(activeTasks(for: project.traskProjectId)) { task in
                        Text(task.label).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .disabled(project.traskProjectId == nil)
            }

            if let pairingIssue {
                switch pairingIssue {
                case .projectInactiveOrMissing:
                    Text(Strings.traskPairingStaleProject).font(.caption).foregroundStyle(.red)
                case .defaultTaskInactiveOrMissing:
                    Text(Strings.traskPairingStaleTask).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var onePasswordEnabledBinding: Binding<Bool> {
        Binding(
            get: { onePasswordSetting.isEnabled },
            set: { newValue in
                onePasswordSetting.isEnabled = newValue
                try? OnePasswordSetting.set(onePasswordSetting)
            }
        )
    }

    private var onePasswordItemDisplayLabel: String {
        guard onePasswordSetting.itemId != nil else { return Strings.onePasswordNoneSelected }
        guard let itemTitle = onePasswordSetting.itemTitle else { return Strings.onePasswordNoneSelected }
        return Strings.onePasswordSelectedItem(itemTitle)
    }

    private func setOnePasswordItem(_ item: OnePasswordItem) {
        onePasswordSetting.itemId = item.id
        onePasswordSetting.itemTitle = item.title
        try? OnePasswordSetting.set(onePasswordSetting)
    }

    private func traskProjectBinding(for project: Project) -> Binding<String?> {
        Binding(
            get: { project.traskProjectId },
            set: { newValue in setTraskProject(newValue, for: project) }
        )
    }

    private func defaultTraskTaskBinding(for project: Project) -> Binding<String?> {
        Binding(
            get: { project.defaultTraskTaskId },
            set: { newValue in setDefaultTraskTask(newValue, for: project) }
        )
    }

    private func setTraskProject(_ traskProjectId: String?, for project: Project) {
        var updated = project
        updated.traskProjectId = traskProjectId
        // Changing the paired Trask project invalidates any previously
        // chosen default task — it almost certainly belongs to the old
        // project, and leaving it set would silently pair a task from one
        // project onto a different one.
        updated.defaultTraskTaskId = nil
        do {
            try AppEnvironment.db.dbQueue.write { try updated.update($0) }
            reload()
            DataChangeNotifier.post()
        } catch {
            traskError = Strings.trackToggleFailed(error.localizedDescription)
        }
    }

    private func setDefaultTraskTask(_ traskTaskId: String?, for project: Project) {
        var updated = project
        updated.defaultTraskTaskId = traskTaskId
        do {
            try AppEnvironment.db.dbQueue.write { try updated.update($0) }
            reload()
            DataChangeNotifier.post()
        } catch {
            traskError = Strings.trackToggleFailed(error.localizedDescription)
        }
    }

    private func refreshTraskCatalog() {
        traskError = nil
        traskRefreshMessage = nil
        isRefreshingTraskCatalog = true

        Task {
            do {
                let status = try await TraskScraper.ensureReady()
                switch status {
                case .ready:
                    break
                case .awaitingTwoFactor:
                    await MainActor.run {
                        traskError = Strings.uploadAwaiting2FA
                        isRefreshingTraskCatalog = false
                    }
                    return
                case .loginRequired:
                    await MainActor.run {
                        traskError = Strings.uploadLoginRequired
                        isRefreshingTraskCatalog = false
                    }
                    return
                }

                let scraped = try await TraskScraper.scrapeCatalog()
                let diff = try TraskCatalog.refresh(db: AppEnvironment.db, scraped: scraped)
                await MainActor.run {
                    traskRefreshMessage = Strings.traskRefreshSummary(
                        newProjects: diff.newProjectLabels.count,
                        newTasks: diff.newTaskLabels.count,
                        deactivated: diff.deactivatedProjectLabels.count + diff.deactivatedTaskLabels.count
                    )
                    isRefreshingTraskCatalog = false
                    reload()
                }
            } catch {
                await MainActor.run {
                    traskError = Strings.traskRefreshFailed(error.localizedDescription)
                    isRefreshingTraskCatalog = false
                }
            }
        }
    }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
        traskProjects = (try? AppEnvironment.db.dbQueue.read { try TraskProject.fetchAll($0) }) ?? []
        traskTasks = (try? AppEnvironment.db.dbQueue.read { try TraskTask.fetchAll($0) }) ?? []
        // Computed once here rather than per-row-per-render — validatePairing
        // is a DB read, and traskPairingRow is re-evaluated on every body
        // pass for every project.
        traskPairingIssues = Dictionary(uniqueKeysWithValues: projects.compactMap { project -> (UUID, TraskPairingIssue)? in
            guard let issue = try? TraskCatalog.validatePairing(db: AppEnvironment.db, project: project) else { return nil }
            return (project.id, issue)
        })
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
}

#Preview {
    SettingsView()
}
