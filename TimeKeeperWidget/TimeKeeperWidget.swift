import WidgetKit
import SwiftUI
import TimeKeeperKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, hoursWorked: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, hoursWorked: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let entry = DayEntry(date: .now, hoursWorked: 0)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let hoursWorked: Double
}

struct TimeKeeperWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("\(entry.hoursWorked, specifier: "%.1f")h")
                .font(.title2)
                .bold()
            Text("dnes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TimeKeeperWidget: Widget {
    let kind: String = "TimeKeeperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TimeKeeperWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TimeKeeper")
        .description("Dnešní odpracovaný čas.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
