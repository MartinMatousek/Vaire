import Foundation
import UserNotifications
import VaireKit

@MainActor
final class DailyReviewScheduler: NSObject {
    static let shared = DailyReviewScheduler()

    private let reviewCategoryId = "daily-review"
    private let reviewRequestId = "daily-review-reminder"

    func start(hour: Int = 18, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let category = UNNotificationCategory(
            identifier: reviewCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        scheduleDailyReminder(hour: hour, minute: minute)
    }

    /// The notification body can't reflect the day's final hour count since
    /// UNCalendarNotificationTrigger content is fixed at scheduling time, not
    /// delivery time. It nudges the user to open the review window, which
    /// shows the real numbers.
    private func scheduleDailyReminder(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = Strings.dailySummaryTitle
        content.body = Strings.dailySummaryBody
        content.categoryIdentifier = reviewCategoryId
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: reviewRequestId, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}

extension DailyReviewScheduler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            WeekWindowController.shared.show()
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
