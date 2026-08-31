import SwiftUI
import WidgetKit
import TimeKeeperKit

struct DayColumn: Identifiable {
    let date: Date
    var blocks: [Block]
    var id: Date { date }
}

struct WeekView: View {
    @Environment(\.weekUndoManager) private var undoManager
    @State private var days: [DayColumn] = []
    @State private var projects: [UUID: Project] = [:]
    @State private var selectedBlockIds: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var editingBlock: Block?
    @State private var noteDraft: String = ""

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(days) { day in
                    dayColumn(day)
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
        .frame(minWidth: 700, minHeight: 400)
        .onAppear(perform: reload)
    }

    private func dayColumn(_ day: DayColumn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).day())
                .font(.caption).bold()

            ForEach(day.blocks) { block in
                blockRow(block)
            }

            Spacer(minLength: 40)
        }
        .frame(minWidth: 90, maxWidth: .infinity, minHeight: 300, alignment: .top)
        .padding(4)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(6)
        .dropDestination(for: BlockTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            return moveBlock(transfer.blockId, to: day.date)
        }
    }

    private func blockRow(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(projects[block.projectId]?.name ?? "?")
                .font(.caption2).bold()
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedBlockIds.contains(block.id) ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
        .cornerRadius(4)
        .onTapGesture(count: 2) {
            beginEditingNote(block)
        }
        .onTapGesture {
            toggleSelection(block.id)
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
            errorMessage = "Přesun selhal: \(error.localizedDescription)"
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
            errorMessage = "Rozdělení selhalo: \(error.localizedDescription)"
        }
    }

    private func mergeSelected() {
        do {
            try BlockEditor.merge(db: AppEnvironment.db, blockIds: Array(selectedBlockIds))
            selectedBlockIds.removeAll()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Sloučení selhalo: \(error.localizedDescription)"
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
            errorMessage = "Smazání selhalo: \(error.localizedDescription)"
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
