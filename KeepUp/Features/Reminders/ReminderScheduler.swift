import Foundation
import UserNotifications

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private var latest: (LocalSnapshot, Locale)?
    private var syncing = false
    private let center = UNUserNotificationCenter.current()
    private let prefix: String
    init(prefix: String = "keepup.reminder.") { self.prefix = prefix }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
    // Coalesce reentrant calls so an older snapshot cannot restore a cancelled reminder.
    func synchronize(_ snapshot: LocalSnapshot, locale: Locale) async {
        latest = (snapshot, locale)
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        while let (snapshot, locale) = latest {
            latest = nil
            let pending = await center.pendingNotificationRequests()
            let own = pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: own)
            guard await isAuthorized() else { continue }
            let available = max(0, 64 - (pending.count-own.count))
            for plan in ReminderPlan.upcoming(targets: snapshot.targets, entries: snapshot.entries, now: .now, limit: available) {
                if latest != nil { break }
                guard let card = snapshot.cards.first(where: { $0.id == plan.cardID }) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "KeepUp"
                let name = card.isCustom ? card.titleKey : localized(card.titleKey, locale)
                content.body = locale.identifier.hasPrefix("zh") ? "该打\(name)卡啦！" : "Time to check in: \(name)"
                content.sound = .default
                content.userInfo = ["cardID": card.id]
                let calendar = Calendar(identifier: .gregorian)
                var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
                parts.calendar = Calendar(identifier: .gregorian)
                let request = UNNotificationRequest(identifier: prefix + plan.cardID + "." + LocalDay(date: plan.date).rawValue, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                do { try await center.add(request) }
                catch { continue } // Retried on the next foreground or data update.
            }
        }
    }
}
