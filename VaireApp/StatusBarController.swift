import AppKit
import SwiftUI
import VaireKit

/// Owns the menu bar icon and its popover directly via NSStatusItem instead
/// of MenuBarExtra. MenuBarExtra's custom SwiftUI `label:` closure silently
/// renders nothing on this machine (macOS 26.5) — verified by testing a
/// plain solid-color Circle as the label with no logic at all, which was
/// also invisible while the systemImage variant works fine. NSStatusItem
/// with a manually drawn NSImage sidesteps that renderer entirely.
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var refreshTimer: Timer?

    func start() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 320)
        popover.contentViewController = NSHostingController(rootView: ContentView())
        self.popover = popover

        refreshIcon()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshIcon),
            name: .vaireDataChanged,
            object: nil
        )
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIcon() }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refreshIcon()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func refreshIcon() {
        let timerHours = AppEnvironment.timer.runningStarts.keys.reduce(0.0) {
            $0 + AppEnvironment.timer.elapsed(projectId: $1) / 3600
        }
        let loggedHours = (try? DailySummary.totalHours(db: AppEnvironment.db, day: .now)) ?? 0
        let hoursWorked = loggedHours + timerHours

        statusItem?.button?.image = Self.renderIcon(hoursWorked: hoursWorked, targetHours: 8)
    }

    private static func renderIcon(hoursWorked: Double, targetHours: Double) -> NSImage {
        let size: CGFloat = 18
        let lineWidth: CGFloat = 3.5
        let progress = targetHours > 0 ? hoursWorked / targetHours : 0

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = lineWidth / 2
            let ringRect = rect.insetBy(dx: inset, dy: inset)

            let trackPath = NSBezierPath(ovalIn: ringRect)
            trackPath.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            trackPath.stroke()

            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = ringRect.width / 2

            let progressPath = NSBezierPath()
            progressPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * min(progress, 1),
                clockwise: true
            )
            progressPath.lineWidth = lineWidth
            progressPath.lineCapStyle = .round
            NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.35, alpha: 1.0).setStroke()
            progressPath.stroke()

            if progress > 1 {
                let overflowPath = NSBezierPath()
                overflowPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * min(progress - 1, 1),
                    clockwise: true
                )
                overflowPath.lineWidth = lineWidth
                overflowPath.lineCapStyle = .round
                NSColor.systemOrange.setStroke()
                overflowPath.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }
}
