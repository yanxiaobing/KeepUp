import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class ReminderRoute {
    static let shared = ReminderRoute()
    var cardID: String?
    var requestID = UUID()
    func open(cardID: String) { self.cardID = cardID; requestID = UUID() }
}

@MainActor
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationDelegate()
    #if DEBUG
    private static var routeTestScheduled = false
    static func scheduleRouteTestIfRequested() async {
        guard !routeTestScheduled, ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.arguments.contains("-ui-testing-reminder-route") else { return }
        routeTestScheduled = true
        let content = UNMutableNotificationContent()
        content.title = "KeepUp"; content.body = "KeepUp route verification"; content.sound = .default
        content.userInfo = ["cardID": "preset.exercise"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "keepup.test.route", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)))
    }
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let cardID = response.notification.request.content.userInfo["cardID"] as? String
        let shouldOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        // UIKit's notification-response completion updates scene snapshots and must run on the main thread.
        Task { @MainActor in
            if shouldOpen, let cardID { ReminderRoute.shared.open(cardID: cardID) }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .sound]) }
    }
}
