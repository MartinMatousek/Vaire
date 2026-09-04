import SwiftUI
import UniformTypeIdentifiers
import VaireKit

struct SettingsView: View {
    @State private var projects: [Project] = []
    @State private var newProjectName = ""
    @State private var newProjectPath = ""
    @State private var exportError: String?
    @State private var selectedLanguage: AppLanguage = AppLanguage.current()
    @State private var timesheetProjects: [TimesheetProject] = []
    @State private var timesheetTasks: [TimesheetTask] = []
    @State private var timesheetPairingIssues: [UUID: TimesheetPairingIssue] = [:]
    @State private var onePasswordSetting = OnePasswordSetting.current()
    @State private var showingOnePasswordPicker = false
    @State private var isRefreshingTimesheetCatalog = false
    @State private var timesheetError: String?
    @State private var timesheetRefreshMessage: String?
    @State private var timesheetURL = TimesheetURLSetting.current() ?? ""

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

            Text(Strings.timesheetSectionTitle)
                .font(.headline)

            TextField(Strings.timesheetURLLabel, text: timesheetURLBinding, prompt: Text(Strings.timesheetURLPlaceholder))

            ForEach(projects) { project in
                timesheetPairingRow(project)
            }

            HStack {
                Button(Strings.timesheetRefreshCatalog) { refreshTimesheetCatalog() }
                    .disabled(isRefreshingTimesheetCatalog)
                if isRefreshingTimesheetCatalog {
                    Text(Strings.timesheetRefreshing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let timesheetRefreshMessage {
                Text(timesheetRefreshMessage).font(.caption).foregroundStyle(.secondary)
            }
            if let timesheetError {
                Text(timesheetError).font(.caption).foregroundStyle(.red)
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

    private var activeTimesheetProjectsSorted: [TimesheetProject] {
        timesheetProjects.filter(\.active).sorted { $0.label < $1.label }
    }

    private func activeTasks(for timesheetProjectId: String?) -> [TimesheetTask] {
        guard let timesheetProjectId else { return [] }
        return timesheetTasks
            .filter { $0.timesheetProjectId == timesheetProjectId && $0.active }
            .sorted { $0.label < $1.label }
    }

    private func timesheetPairingRow(_ project: Project) -> some View {
        let pairingIssue = timesheetPairingIssues[project.id]

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name).font(.callout)

                Picker(Strings.timesheetProjectLabel, selection: timesheetProjectBinding(for: project)) {
                    Text(Strings.timesheetNoPairing).tag(Optional<String>.none)
                    ForEach(activeTimesheetProjectsSorted) { timesheetProject in
                        Text(timesheetProject.label).tag(Optional(timesheetProject.id))
                    }
                }
                .labelsHidden()

                Picker(Strings.timesheetDefaultTaskLabel, selection: defaultTimesheetTaskBinding(for: project)) {
                    Text(Strings.timesheetNoPairing).tag(Optional<String>.none)
                    ForEach(activeTasks(for: project.timesheetProjectId)) { task in
                        Text(task.label).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .disabled(project.timesheetProjectId == nil)
            }

            if let pairingIssue {
                switch pairingIssue {
                case .projectInactiveOrMissing:
                    Text(Strings.timesheetPairingStaleProject).font(.caption).foregroundStyle(.red)
                case .defaultTaskInactiveOrMissing:
                    Text(Strings.timesheetPairingStaleTask).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var timesheetURLBinding: Binding<String> {
        Binding(
            get: { timesheetURL },
            set: { newValue in
                timesheetURL = newValue
                try? TimesheetURLSetting.set(newValue)
            }
        )
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

    private func timesheetProjectBinding(for project: Project) -> Binding<String?> {
        Binding(
            get: { project.timesheetProjectId },
            set: { newValue in setTimesheetProject(newValue, for: project) }
        )
    }

    private func defaultTimesheetTaskBinding(for project: Project) -> Binding<String?> {
        Binding(
            get: { project.defaultTimesheetTaskId },
            set: { newValue in setDefaultTimesheetTask(newValue, for: project) }
        )
    }

    private func setTimesheetProject(_ timesheetProjectId: String?, for project: Project) {
        var updated = project
        updated.timesheetProjectId = timesheetProjectId
        // Changing the paired timesheet project invalidates any previously
        // chosen default task — it almost certainly belongs to the old
        // project, and leaving it set would silently pair a task from one
        // project onto a different one.
        updated.defaultTimesheetTaskId = nil
        do {
            try AppEnvironment.db.dbQueue.write { try updated.update($0) }
            reload()
            DataChangeNotifier.post()
        } catch {
            timesheetError = Strings.trackToggleFailed(error.localizedDescription)
        }
    }

    private func setDefaultTimesheetTask(_ timesheetTaskId: String?, for project: Project) {
        var updated = project
        updated.defaultTimesheetTaskId = timesheetTaskId
        do {
            try AppEnvironment.db.dbQueue.write { try updated.update($0) }
            reload()
            DataChangeNotifier.post()
        } catch {
            timesheetError = Strings.trackToggleFailed(error.localizedDescription)
        }
    }

    private func refreshTimesheetCatalog() {
        timesheetError = nil
        timesheetRefreshMessage = nil
        isRefreshingTimesheetCatalog = true

        Task {
            do {
                let status = try await TimesheetScraper.ensureReady()
                switch status {
                case .ready:
                    break
                case .awaitingTwoFactor:
                    await MainActor.run {
                        timesheetError = Strings.uploadAwaiting2FA
                        isRefreshingTimesheetCatalog = false
                    }
                    return
                case .loginRequired:
                    await MainActor.run {
                        timesheetError = Strings.uploadLoginRequired
                        isRefreshingTimesheetCatalog = false
                    }
                    return
                }

                let scraped = try await TimesheetScraper.scrapeCatalog()
                let diff = try TimesheetCatalog.refresh(db: AppEnvironment.db, scraped: scraped)
                await MainActor.run {
                    timesheetRefreshMessage = Strings.timesheetRefreshSummary(
                        newProjects: diff.newProjectLabels.count,
                        newTasks: diff.newTaskLabels.count,
                        deactivated: diff.deactivatedProjectLabels.count + diff.deactivatedTaskLabels.count
                    )
                    isRefreshingTimesheetCatalog = false
                    reload()
                }
            } catch {
                await MainActor.run {
                    timesheetError = Strings.timesheetRefreshFailed(error.localizedDescription)
                    isRefreshingTimesheetCatalog = false
                }
            }
        }
    }

    private func reload() {
        projects = (try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? []
        timesheetProjects = (try? AppEnvironment.db.dbQueue.read { try TimesheetProject.fetchAll($0) }) ?? []
        timesheetTasks = (try? AppEnvironment.db.dbQueue.read { try TimesheetTask.fetchAll($0) }) ?? []
        // Computed once here rather than per-row-per-render — validatePairing
        // is a DB read, and timesheetPairingRow is re-evaluated on every body
        // pass for every project.
        timesheetPairingIssues = Dictionary(uniqueKeysWithValues: projects.compactMap { project -> (UUID, TimesheetPairingIssue)? in
            guard let issue = try? TimesheetCatalog.validatePairing(db: AppEnvironment.db, project: project) else { return nil }
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
