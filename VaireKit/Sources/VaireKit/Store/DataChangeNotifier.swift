import Foundation
import CoreFoundation

/// Cross-process signal that the shared database changed. The CLI (a plain
/// executable with no app bundle) can't call WidgetCenter directly, so it
/// posts this Darwin notification instead; the app, while running, observes
/// it and reloads the widget's timeline on its behalf.
public enum DataChangeNotifier {
    public static let notificationName = "com.martinmatousek.vaire.dataChanged" as CFString

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil, nil, true
        )
    }

    /// Registers `handler` to run whenever another process posts the
    /// data-changed notification. Call once at app startup; the returned
    /// observer token is unused but kept alive by the Darwin center itself.
    public static func observe(_ handler: @escaping () -> Void) {
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(ObserverBox.shared).toOpaque())
        ObserverBox.shared.handler = handler

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, _, _, _, _ in
                ObserverBox.shared.handler?()
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }

    private final class ObserverBox {
        static let shared = ObserverBox()
        var handler: (() -> Void)?
    }
}
