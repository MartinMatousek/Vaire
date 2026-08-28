import SwiftUI
import UniformTypeIdentifiers
import TimeKeeperKit

struct SettingsView: View {
    @State private var projects: [Project] = []
    @State private var newProjectName = ""
    @State private var newProjectPath = ""
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projekty")
                .font(.headline)

            List(projects) { project in
                VStack(alignment: .leading) {
                    Text(project.name).bold()
                    Text(project.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)

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
}

#Preview {
    SettingsView()
}
