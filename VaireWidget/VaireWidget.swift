import WidgetKit
import SwiftUI
import VaireKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, hoursWorked: 4, targetHours: 8, projectTotals: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let entry = currentEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> DayEntry {
        guard let db = try? AppDatabase(path: SharedStorage.databasePath()) else {
            return DayEntry(date: .now, hoursWorked: 0, targetHours: 8, projectTotals: [])
        }
        let total = (try? DailySummary.totalHours(db: db, day: .now)) ?? 0
        let perProject = (try? DailySummary.perProjectTotals(db: db, day: .now)) ?? []
        return DayEntry(date: .now, hoursWorked: total, targetHours: 8, projectTotals: perProject)
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let hoursWorked: Double
    let targetHours: Double
    let projectTotals: [ProjectDayTotal]
}

struct VaireWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                ringAndTotal
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.projectTotals.prefix(4), id: \.project.id) { total in
                        Text(Strings.widgetProjectLine(project: total.project.name, hours: String(format: "%.1fh", total.hours)))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
        default:
            ringAndTotal
                .padding()
        }
    }

    private var ringAndTotal: some View {
        VStack(spacing: 6) {
            DayProgressRing(hoursWorked: entry.hoursWorked, targetHours: entry.targetHours)
                .frame(width: 56, height: 56)
            Text(String(format: "%.1fh", entry.hoursWorked))
                .font(.headline)
            Text(Strings.widgetTodaySuffix)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct VaireWidget: Widget {
    let kind: String = "VaireWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VaireWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(Strings.widgetDisplayName)
        .description(Strings.widgetDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
