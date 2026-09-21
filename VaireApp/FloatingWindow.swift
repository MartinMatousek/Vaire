import AppKit

/// Shared configuration for every Vaire window. Vaire is an accessory app
/// (LSUIElement, AppDelegate.applicationDidFinishLaunching), so it has no
/// Dock icon and no Cmd-Tab entry — a window that falls behind another app
/// cannot be reached again except through the menu bar icon. Confirmed live:
/// this is how the week window, the log start/end popups, and the upload
/// sheet all kept getting lost. Floating level keeps every window reachable,
/// and .canJoinAllSpaces means switching Spaces doesn't strand one on the
/// Space it was opened in.
@MainActor
func configureFloatingWindow(_ window: NSWindow) {
    window.level = .floating
    // Without .fullScreenAuxiliary, a floating window still won't appear
    // over another app running full-screen — exactly when a log-start
    // popup is easiest to miss.
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
}
