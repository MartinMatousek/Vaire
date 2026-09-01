import AppKit
import SwiftUI
import WidgetKit
import VaireKit

struct DayColumn: Identifiable {
    let date: Date
    var blocks: [Block]
    var liveTrackings: [AgentSessionTracking]
    var id: Date { date }
}

struct WeekView: View {
    @Environment(\.weekUndoManager) private var undoManager
    @State private var weekOffset = 0
    @State private var days: [DayColumn] = []
    @State private var projects: [UUID: Project] = [:]
    @State private var selectedBlockId: UUID?
    @State private var errorMessage: String?
    @State private var editingBlock: Block?
    @State private var noteDraft: String = ""
    @State private var hoursDraft: Int = 0
    @State private var minutesDraft: Int = 0
    @State private var estimateHoursDraft: Int = 0
    @State private var estimateMinutesDraft: Int = 0
    @State private var hasEstimateDraft: Bool = false
    @State private var showingTimeSaved = false
    @State private var showingDeleteConfirmation = false
    @State private var showingGitImport = false

    private let targetHours: Double = 8
    private let defaultPixelsPerHour: CGFloat = 30
    private let minBlockHours: Double = 0.25 // 15 min floor so short entries stay visible without dwarfing the hour scale
    @State private var timelineHeight: CGFloat = 0

    private let minPixelsPerHour: CGFloat = 12
    private let maxPixelsPerHour: CGFloat = 45

    /// Scales with the window: the timeline area reports its available
    /// height via GeometryReader, and hour rows stretch/shrink to fill it
    /// so resizing the week window actually resizes the grid instead of
    /// just adding empty space or getting clipped. Clamped to a narrow
    /// band around the default (12-45px/hour) — this is meant to absorb
    /// modest window resizing, not to make an hour block visually balloon
    /// just because the window got taller.
    private var pixelsPerHour: CGFloat {
        guard timelineHeight > 0 else { return defaultPixelsPerHour }
        return min(maxPixelsPerHour, max(minPixelsPerHour, timelineHeight / CGFloat(gridHours)))
    }

    private var weekStart: Date {
        let thisWeekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeekStart) ?? thisWeekStart
    }

    // Not filtered to hooksEnabled: git import exists specifically for
    // work done outside Claude Code, which is often the projects that
    // don't have hooks tracking on at all.
    private var allProjectsSorted: [Project] {
        projects.values.sorted { $0.name < $1.name }
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
                    Button(Strings.today) {
                        weekOffset = 0
                        reload()
                    }
                    .buttonStyle(.link)
                }

                Spacer()

                Button(Strings.importFromGit) {
                    showingGitImport = true
                }
                .buttonStyle(.link)
                .help(Strings.importFromGitHelp)
                .disabled(allProjectsSorted.isEmpty)
                .sheet(isPresented: $showingGitImport) {
                    GitImportSheet(weekStart: weekStart, projects: allProjectsSorted, onImported: reload)
                }

                Button(Strings.savings) {
                    showingTimeSaved = true
                }
                .popover(isPresented: $showingTimeSaved) {
                    TimeSavedView(weekStart: weekStart)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 8) {
                    hourLegend
                        .padding(.top, dayColumnHeaderHeight)

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(days) { day in
                            dayColumn(day)
                        }
                    }
                }
                .onAppear { timelineHeight = geometry.size.height - dayColumnHeaderHeight }
                .onChange(of: geometry.size.height) { _, newValue in
                    timelineHeight = newValue - dayColumnHeaderHeight
                }
            }

            HStack {
                Button(Strings.delete) { confirmDeleteSelected() }
                    .disabled(selectedBlockId == nil)
                Spacer()
                Button(Strings.reportBug) {
                    reportBug()
                }
                .buttonStyle(.link)
                Spacer()
                Button(Strings.undo) { undoManager?.undo() }
                    .disabled(undoManager?.canUndo != true)
                Button(Strings.redo) { undoManager?.redo() }
                    .disabled(undoManager?.canRedo != true)
            }
        }
        .padding()
        .frame(minWidth: 590, minHeight: 320)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .vaireDataChanged)) { _ in
            reload()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            // Live blocks grow with elapsed time even without a data
            // change — a slow poll keeps their bar height/hours roughly
            // current without re-querying on every tick.
            reload()
        }
        .confirmationDialog(
            Strings.deleteBlockConfirmTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(Strings.delete, role: .destructive) { deleteSelected() }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(Strings.deleteBlockConfirmMessage)
        }
    }

    private var scaleHeight: CGFloat {
        targetHours * pixelsPerHour
    }

    private let minGridHours = 10
    private let maxGridHours = 24

    /// The stacked height of a day's blocks (rounded the same way as
    /// `blockRow`/`liveBlockRow`) plus its live trackings — the tallest day
    /// determines how many hour-marks the ruler needs to cover.
    private func stackedHours(for day: DayColumn) -> Double {
        let blockHours = day.blocks.reduce(0.0) { $0 + displayHours(for: $1.duration / 3600) }
        let liveHours = day.liveTrackings.reduce(0.0) { total, tracking in
            total + max(Date().timeIntervalSince(tracking.start) / 3600, minBlockHours)
        }
        return blockHours + liveHours
    }

    /// Grows past the default 12h grid as logged time approaches it, so a
    /// busy day's stacked blocks always land inside ruled lines instead of
    /// overflowing past the last mark. Grows in whole hours with 2h of
    /// headroom above the tallest day, capped at 24h.
    private var gridHours: Int {
        let tallestDay = days.map(stackedHours).max() ?? 0
        let needed = Int(tallestDay.rounded(.up)) + 2
        return min(maxGridHours, max(minGridHours, needed))
    }

    private var gridHeight: CGFloat {
        CGFloat(gridHours) * pixelsPerHour
    }

    private let dayColumnHeaderHeight: CGFloat = 20

    /// Blocks stack sequentially by logged order, not by clock time — so
    /// this ruler marks accumulated length (0h, 1h, 2h...) from the top of
    /// the column, not times of day. Labeling it 8:00/9:00/etc. would imply
    /// a real calendar timeline, which the stacked layout doesn't provide.
    private var hourLegend: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0...gridHours, id: \.self) { hourOffset in
                Text("\(hourOffset)h")
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
                    Text(DurationFormatter.hoursMinutes(totalHours))
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
                    ForEach(day.liveTrackings, id: \.sessionId) { tracking in
                        liveBlockRow(tracking)
                    }
                }
            }
            .frame(minHeight: gridHeight, alignment: .top)

            Spacer(minLength: 8)
        }
        .frame(minWidth: 64, maxWidth: .infinity, alignment: .top)
        .padding(4)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(6)
        .dropDestination(for: BlockTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            return moveBlock(transfer.blockId, to: day.date)
        }
    }

    /// Rounds a duration up to the nearest `minBlockHours` (15 min) — so a
    /// 3-minute task is both shown and treated as 15 minutes, not just
    /// visually padded while the label still says "0.1h". Keeps the bar
    /// height and the printed duration consistent with each other.
    private func displayHours(for actualHours: Double) -> Double {
        guard minBlockHours > 0 else { return actualHours }
        return (actualHours / minBlockHours).rounded(.up) * minBlockHours
    }

    /// Approximate height of one caption2 text line including its VStack
    /// spacing — used to decide how many EXTRA label lines fit above the
    /// always-shown compact summary line.
    private let lineHeight: CGFloat = 13

    /// How many extra lines fit in `height` after the compact summary line
    /// and 8pt (4+4) padding, clamped to [0, maxLines].
    private func linesThatFit(in height: CGFloat, maxLines: Int) -> Int {
        let available = height - 8 - 9 // 9pt for the always-shown tiny summary line
        guard available > 0 else { return 0 }
        return min(maxLines, max(0, Int(available / lineHeight)))
    }

    private func blockRow(_ block: Block) -> some View {
        let hours = displayHours(for: block.duration / 3600)
        let barHeight = hours * pixelsPerHour
        let hasNote = !(block.note?.isEmpty ?? true)
        let extraLines = linesThatFit(in: barHeight, maxLines: hasNote ? 8 : 0)
        let projectName = projects[block.projectId]?.name ?? "?"

        return VStack(alignment: .leading, spacing: 2) {
            // Always visible, even on the smallest (15 min) blocks — a
            // system-size-8 single line beats a hover tooltip that macOS
            // wasn't reliably showing over the draggable/popover stack.
            Text(Strings.blockLabel(project: projectName, duration: durationLabel(block)))
                .font(.system(size: 8))
                .bold()
                .lineLimit(1)
            if extraLines >= 1, let note = block.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(extraLines)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: barHeight, alignment: .top)
        .clipped()
        .background(selectedBlockId == block.id ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            beginEditingNote(block)
        }
        .onTapGesture {
            toggleSelection(block.id)
        }
        .contextMenu {
            Button(Strings.edit) { beginEditingNote(block) }
        }
        .draggable(BlockTransfer(blockId: block.id))
        .popover(isPresented: Binding(
            get: { editingBlock?.id == block.id },
            set: { if !$0 { editingBlock = nil } }
        )) {
            noteEditor(for: block)
        }
    }

    /// Live blocks (Claude sessions still tracking, or a manually-started
    /// timer) never appear in `Block` — they're drawn from
    /// AgentSessionTracking/TimerController so a running task is visibly
    /// distinct from finished, editable ones: a pulsing green border and a
    /// "Běží" badge instead of the neutral gray background, and no
    /// tap/drag/context-menu since there's no Block to act on yet.
    private func liveBlockRow(_ tracking: AgentSessionTracking) -> some View {
        let elapsedHours = Date().timeIntervalSince(tracking.start) / 3600
        let barHeight = max(elapsedHours, minBlockHours) * pixelsPerHour
        let hasNote = !(tracking.note?.isEmpty ?? true)
        let extraLines = linesThatFit(in: barHeight, maxLines: hasNote ? 8 : 0)
        let projectName = projects[tracking.projectId]?.name ?? "?"

        return VStack(alignment: .leading, spacing: 2) {
            Text(Strings.runningLabel(project: projectName, hours: DurationFormatter.hoursMinutes(elapsedHours)))
                .font(.system(size: 8))
                .bold()
                .foregroundStyle(.green)
                .lineLimit(1)
            if extraLines >= 1, let note = tracking.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(extraLines)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: barHeight, alignment: .top)
        .clipped()
        .background(Color.green.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.green, lineWidth: 1.5)
        )
        .cornerRadius(4)
    }

    private func noteEditor(for block: Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.activityDescriptionLabel).font(.caption).bold()
            TextField(Strings.whatDidYouDoPlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(3...6)
                .frame(minWidth: 220)

            Text(Strings.timeLabel).font(.caption).bold()
            HoursMinutesField(hours: $hoursDraft, minutes: $minutesDraft)

            Toggle(Strings.estimateWithoutAI, isOn: $hasEstimateDraft)
                .font(.caption)
            if hasEstimateDraft {
                HoursMinutesField(hours: $estimateHoursDraft, minutes: $estimateMinutesDraft)
            }

            HStack {
                Button(Strings.delete) { deleteEditingBlock(block) }
                    .foregroundStyle(.red)
                Spacer()
                Button(Strings.cancel) { editingBlock = nil }
                Button(Strings.save) { saveBlockEdits(for: block) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func deleteEditingBlock(_ block: Block) {
        do {
            try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
            registerUndoForDelete([block])
            editingBlock = nil
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleStaleBlockError(error, actionDescription: Strings.actionDelete)
        }
    }

    private func beginEditingNote(_ block: Block) {
        noteDraft = block.note ?? ""
        let measured = HoursMinutesField.roundedUp(totalMinutes: Int((block.duration / 60).rounded()))
        hoursDraft = measured.hours
        minutesDraft = measured.minutes

        if let estimate = block.estimatedHoursWithoutAI {
            let estimateRounded = HoursMinutesField.roundedUp(totalMinutes: Int((estimate * 60).rounded()))
            estimateHoursDraft = estimateRounded.hours
            estimateMinutesDraft = estimateRounded.minutes
            hasEstimateDraft = true
        } else {
            estimateHoursDraft = 0
            estimateMinutesDraft = 0
            hasEstimateDraft = false
        }

        editingBlock = block
    }

    private func saveBlockEdits(for block: Block) {
        do {
            _ = try BlockEditor.setNote(db: AppEnvironment.db, blockId: block.id, note: noteDraft)

            let duration = HoursMinutesField.roundedUp(totalMinutes: hoursDraft * 60 + minutesDraft)
            let newDuration = TimeInterval((duration.hours * 60 + duration.minutes) * 60)
            if newDuration != block.duration {
                let newEnd = block.start.addingTimeInterval(newDuration)
                _ = try BlockEditor.setTimes(db: AppEnvironment.db, blockId: block.id, start: block.start, end: newEnd)
            }

            let newEstimate: Double? = hasEstimateDraft
                ? {
                    let rounded = HoursMinutesField.roundedUp(totalMinutes: estimateHoursDraft * 60 + estimateMinutesDraft)
                    return Double(rounded.hours * 60 + rounded.minutes) / 60
                }()
                : nil
            if newEstimate != block.estimatedHoursWithoutAI {
                _ = try BlockEditor.setEstimate(db: AppEnvironment.db, blockId: block.id, hours: newEstimate)
            }

            editingBlock = nil
            reload()
        } catch {
            handleStaleBlockError(error, actionDescription: Strings.actionSaveEdits)
        }
    }

    private func durationLabel(_ block: Block) -> String {
        DurationFormatter.hoursMinutes(displayHours(for: block.duration / 3600))
    }

    private func reportBug() {
        guard let url = URL(string: "https://github.com/MartinMatousek/Vaire/issues/new") else { return }
        NSWorkspace.shared.open(url)
    }

    private func toggleSelection(_ id: UUID) {
        selectedBlockId = selectedBlockId == id ? nil : id
    }

    private func reload() {
        let calendar = Calendar.current
        let allBlocks = (try? AppEnvironment.db.dbQueue.read { try Block.fetchAll($0) }) ?? []
        projects = Dictionary(
            uniqueKeysWithValues: ((try? AppEnvironment.db.dbQueue.read { try Project.fetchAll($0) }) ?? [])
                .map { ($0.id, $0) }
        )

        // Running work — Claude session timers (in agentSessionTracking,
        // not yet a Block) and manually-started timers (in-memory on
        // AppEnvironment.timer) — never appear in the block table until
        // stopped. Surface both here so the week view shows what's
        // currently in progress, not just what's already finished.
        let claudeTrackings = (try? AgentSessionRecorder.allActiveTrackings(db: AppEnvironment.db)) ?? []
        let manualTrackings = AppEnvironment.timer.runningStarts.map { projectId, start in
            AgentSessionTracking(sessionId: "manual-\(projectId)", projectId: projectId, start: start, note: AppEnvironment.timer.runningNotes[projectId])
        }
        let allLive = claudeTrackings + manualTrackings

        days = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let dayBlocks = allBlocks.filter { calendar.isDate($0.start, inSameDayAs: date) }
                .sorted { $0.start < $1.start }
            let dayLive = allLive.filter { calendar.isDate($0.start, inSameDayAs: date) }
                .sorted { $0.start < $1.start }
            return DayColumn(date: date, blocks: dayBlocks, liveTrackings: dayLive)
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
            errorMessage = Strings.actionFailedStale(actionDescription)
            reload()
        } else {
            errorMessage = Strings.actionFailed(action: actionDescription, message: error.localizedDescription)
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
            handleStaleBlockError(error, actionDescription: Strings.actionMove)
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

    private func confirmDeleteSelected() {
        guard selectedBlockId != nil else { return }
        showingDeleteConfirmation = true
    }

    private func deleteSelected() {
        guard let selectedBlockId, let block = days.flatMap(\.blocks).first(where: { $0.id == selectedBlockId }) else { return }

        do {
            try BlockEditor.delete(db: AppEnvironment.db, blockId: block.id)
            registerUndoForDelete([block])
            self.selectedBlockId = nil
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleStaleBlockError(error, actionDescription: Strings.actionDelete)
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
