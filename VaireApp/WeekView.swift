import SwiftUI
import WidgetKit
import VaireKit

struct DayColumn: Identifiable {
    let date: Date
    var blocks: [Block]
    var id: Date { date }
}

struct WeekView: View {
    @Environment(\.weekUndoManager) private var undoManager
    @State private var weekOffset = 0
    @State private var days: [DayColumn] = []
    @State private var projects: [UUID: Project] = [:]
    @State private var selectedBlockIds: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var editingBlock: Block?
    @State private var noteDraft: String = ""
    @State private var showingTimeSaved = false

    private let targetHours: Double = 8
    private let pixelsPerHour: CGFloat = 30

    private var weekStart: Date {
        let thisWeekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeekStart) ?? thisWeekStart
    }

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let formatter = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(weekStart.formatted(formatter)) – \(weekEnd.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button {
                    weekOffset -= 1
                    reload()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(weekRangeLabel)
                    .font(.headline)
                    .frame(minWidth: 140)

                Button {
                    weekOffset += 1
                    reload()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)

                if weekOffset != 0 {
                    Button("Dnes") {
                        weekOffset = 0
                        reload()
                    }
                    .buttonStyle(.link)
                }

                Spacer()

                Button("Úspory") {
                    showingTimeSaved = true
                }
                .popover(isPresented: $showingTimeSaved) {
                    TimeSavedView(weekStart: weekStart)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: 8) {
                hourLegend
                    .padding(.top, dayColumnHeaderHeight)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(days) { day in
                        dayColumn(day)
                    }
                }
            }

            HStack {
                Button("Split") { splitSelected() }
                    .disabled(selectedBlockIds.count != 1)
                Button("Merge") { mergeSelected() }
                    .disabled(selectedBlockIds.count < 2)
                Button("Delete") { deleteSelected() }
                    .disabled(selectedBlockIds.isEmpty)
                Spacer()
                Button("Undo") { undoManager?.undo() }
                    .disabled(undoManager?.canUndo != true)
                Button("Redo") { undoManager?.redo() }
                    .disabled(undoManager?.canRedo != true)
            }
        }
        .padding()
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .vaireDataChanged)) { _ in
            reload()
        }
    }

    private var scaleHeight: CGFloat {
        targetHours * pixelsPerHour
    }

    /// The grid extends past the 8h workday target to cover evening hours
    /// too, so blocks logged outside 8:00-16:00 still land on a ruled line.
    private let gridHours = 12
    private var gridHeight: CGFloat {
        CGFloat(gridHours) * pixelsPerHour
    }

    private let dayColumnHeaderHeight: CGFloat = 20
    private let workdayStartHour = 8

    private var hourLegend: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0...gridHours, id: \.self) { hourOffset in
                Text("\(workdayStartHour + hourOffset):00")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: CGFloat(hourOffset) * pixelsPerHour - 6)
            }
        }
        .frame(width: 44, height: gridHeight, alignment: .topTrailing)
    }

    private var hourGridLines: some View {
        ForEach(0...gridHours, id: \.self) { hourOffset in
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
                .offset(y: CGFloat(hourOffset) * pixelsPerHour)
        }
    }

    private func dayColumn(_ day: DayColumn) -> some View {
        let totalHours = day.blocks.reduce(0.0) { $0 + $1.duration / 3600 }
        let isWorkday = !Calendar.current.isDateInWeekend(day.date)
        let metTarget = totalHours >= targetHours

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.caption).bold()
                if isWorkday {
                    Text(String(format: "%.1fh", totalHours))
                        .font(.caption2)
                        .foregroundStyle(metTarget ? .green : .secondary)
                }
            }

            ZStack(alignment: .top) {
                hourGridLines

                // 8h scale: a filled track up to the target, so a day's
                // blocks visually show how much of the workday they cover.
                if isWorkday {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.08))
                        .frame(height: scaleHeight)

                    Rectangle()
                        .fill(Color.green.opacity(0.4))
                        .frame(height: 1)
                        .offset(y: scaleHeight)
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(day.blocks) { block in
                        blockRow(block)
                    }
                }
            }
            .frame(minHeight: gridHeight, alignment: .top)

            Spacer(minLength: 8)
        }
        .frame(minWidth: 90, maxWidth: .infinity, alignment: .top)
        .padding(4)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(6)
        .dropDestination(for: BlockTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            return moveBlock(transfer.blockId, to: day.date)
        }
    }

    private func blockRow(_ block: Block) -> some View {
        let hours = block.duration / 3600
        let barHeight = max(20, hours * pixelsPerHour)

        return VStack(alignment: .leading, spacing: 2) {
            Text(projects[block.projectId]?.name ?? "?")
                .font(.caption2).bold()
                .lineLimit(1)
            Text(durationLabel(block))
                .font(.caption2)
            if let note = block.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .topLeading)
        .background(selectedBlockIds.contains(block.id) ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
        .cornerRadius(4)
        .onTapGesture {
            toggleSelection(block.id)
        }
        .contextMenu {
            Button("Upravit popis…") { beginEditingNote(block) }
        }
        .draggable(BlockTransfer(blockId: block.id))
        .popover(isPresented: Binding(
            get: { editingBlock?.id == block.id },
            set: { if !$0 { editingBlock = nil } }
        )) {
            noteEditor(for: block)
        }
    }

    private func noteEditor(for block: Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popis aktivity").font(.caption).bold()
            TextField("Co jsi dělal…", text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)
            HStack {
                Spacer()
                Button("Zrušit") { editingBlock = nil }
                Button("Uložit") { saveNote(for: block) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func beginEditingNote(_ block: Block) {
        noteDraft = block.note ?? ""
        editingBlock = block
    }

    private func saveNote(for block: Block) {
        do {
            _ = try BlockEditor.setNote(db: AppEnvironment.db, blockId: block.id, note: noteDraft)
            editingBlock = nil
            reload()
        } catch {
            errorMessage = "Uložení popisu selhalo: \(error.localizedDescription)"
        }
    }

    private func durationLabel(_ block: Block) -> String {
        let hours = block.duration / 3600
        return String(format: "%.1fh", hours)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedBlockIds.contains(id) {
            selectedBlockIds.remove(id)
        } else {
            selectedBlockIds.insert(id)
        }
    }

    private func reload() {
        let calendar = Calendar.current
        let allBlocks = (try? AppEnvironment.db.dbQueue.read { try Block.fetchAll($0) }) ?? []
        projects = Dictionary(
            uniqueKeysWithValues: ((try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? [])
                .map { ($0.id, $0) }
        )

        days = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let dayBlocks = allBlocks.filter { calendar.isDate($0.start, inSameDayAs: date) }
                .sorted { $0.start < $1.start }
            return DayColumn(date: date, blocks: dayBlocks)
        }
    }

    /// Auto-imported blocks (isManual == false, e.g. from a live Claude
    /// session import) get deleted and re-inserted with a fresh id every
    /// time the background importer reconciles them. If the user clicks an
    /// action between that reconcile and this call, the id they have is
    /// stale — BlockEditorError.blockNotFound. Reloading recovers the
    /// current state; the friendly message explains why the action didn't
    /// "do nothing" silently.
    private func handleStaleBlockError(_ error: Error, actionDescription: String) {
        if case BlockEditorError.blockNotFound = error {
            errorMessage = "\(actionDescription) se nepodařilo — záznam se mezitím aktualizoval (např. živým importem). Zkus to prosím znovu."
            reload()
        } else {
            errorMessage = "\(actionDescription) selhalo: \(error.localizedDescription)"
        }
    }

    private func moveBlock(_ blockId: UUID, to targetDay: Date) -> Bool {
        guard let block = days.flatMap(\.blocks).first(where: { $0.id == blockId }) else { return false }
        let calendar = Calendar.current
        let sourceDay = calendar.startOfDay(for: block.start)
        let dayDelta = calendar.dateComponents([.day], from: sourceDay, to: calendar.startOfDay(for: targetDay)).day ?? 0
        guard dayDelta != 0 else { return false }

        do {
            try BlockEditor.move(db: AppEnvironment.db, blockId: blockId, byDays: dayDelta)
            registerUndo(reverseDays: -dayDelta, blockId: blockId)
            reload()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            handleStaleBlockError(error, actionDescription: "Přesun")
            return false
        }
    }

    private func registerUndo(reverseDays: Int, blockId: UUID) {
        undoManager?.registerUndo(withTarget: UndoToken()) { [reload] _ in
            try? BlockEditor.move(db: AppEnvironment.db, blockId: blockId, byDays: reverseDays)
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func splitSelected() {
        guard let blockId = selectedBlockIds.first,
              let block = days.flatMap(\.blocks).first(where: { $0.id == blockId }) else { return }
        let midpoint = block.start.addingTimeInterval(block.duration / 2)

        do {
            try BlockEditor.split(db: AppEnvironment.db, blockId: blockId, at: midpoint)
            selectedBlockIds.removeAll()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleStaleBlockError(error, actionDescription: "Rozdělení")
        }
    }

    private func mergeSelected() {
        do {
            try BlockEditor.merge(db: AppEnvironment.db, blockIds: Array(selectedBlockIds))
            selectedBlockIds.removeAll()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleStaleBlockError(error, actionDescription: "Sloučení")
        }
    }

    private func deleteSelected() {
        let blocksToDelete = days.flatMap(\.blocks).filter { selectedBlockIds.contains($0.id) }
        guard !blocksToDelete.isEmpty else { return }

        do {
            for block in blocksToDelete {
                try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
            }
            registerUndoForDelete(blocksToDelete)
            selectedBlockIds.removeAll()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleStaleBlockError(error, actionDescription: "Smazání")
        }
    }

    private func registerUndoForDelete(_ blocks: [Block]) {
        undoManager?.registerUndo(withTarget: UndoToken()) { [reload] _ in
            try? AppEnvironment.db.dbQueue.write { conn in
                for block in blocks {
                    try block.insert(conn)
                }
            }
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private final class UndoToken {}

#Preview {
    WeekView()
}
