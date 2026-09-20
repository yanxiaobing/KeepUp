import Foundation
import UserNotifications

// Send only value data across actor boundaries. Framework request/content objects stay in
// the system adapter, while foreign pending requests are projected only for queue accounting.
struct ReminderNotificationRequest: Sendable, Equatable {
    let identifier: String
    var title = "KeepUp"
    var body = ""
    var cardID: String?
    var playsDefaultSound = true
    var dateComponents: DateComponents?
    var repeats = false
}

protocol ReminderNotificationCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingRequests() async -> [ReminderNotificationRequest]
    func add(_ request: ReminderNotificationRequest) async throws
    func removeRequests(withIdentifiers identifiers: [String]) async
}

struct SystemReminderNotificationCenter: ReminderNotificationCenter {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func pendingRequests() async -> [ReminderNotificationRequest] {
        await center.pendingNotificationRequests().map { request in
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            return ReminderNotificationRequest(identifier: request.identifier, title: request.content.title,
                body: request.content.body, cardID: request.content.userInfo["cardID"] as? String,
                playsDefaultSound: request.content.sound?.isEqual(UNNotificationSound.default) == true,
                dateComponents: trigger?.dateComponents, repeats: trigger?.repeats ?? false)
        }
    }
    func add(_ request: ReminderNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = request.playsDefaultSound ? .default : nil
        if let cardID = request.cardID { content.userInfo = ["cardID": cardID] }
        let trigger = request.dateComponents.map { UNCalendarNotificationTrigger(dateMatching: $0, repeats: request.repeats) }
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }
    func removeRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private var latest: (LocalSnapshot, Locale)?
    private var syncing = false
    private let center: any ReminderNotificationCenter
    private let prefix: String
    private let now: @Sendable () -> Date

    init(prefix: String = "keepup.reminder.", center: any ReminderNotificationCenter = SystemReminderNotificationCenter(), now: @escaping @Sendable () -> Date = { .now }) {
        self.prefix = prefix
        self.center = center
        self.now = now
    }

    func requestPermission() async throws -> Bool { try await center.requestAuthorization() }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.authorizationStatus() }
    func isAuthorized() async -> Bool { Self.canNotify(await authorizationStatus()) }

    private static func canNotify(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // Coalesce reentrant calls so an older snapshot cannot restore a cancelled reminder.
    func synchronize(_ snapshot: LocalSnapshot, locale: Locale) async {
        latest = (snapshot, locale)
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        while let (snapshot, locale) = latest {
            latest = nil
            let pending = await center.pendingRequests()
            guard latest == nil else { continue }
            let authorized = await isAuthorized()
            guard latest == nil else { continue }
            let own = pending.filter { $0.identifier.hasPrefix(prefix) }
            let available = max(0, 64 - (pending.count - own.count))
            let desired = authorized ? requests(for: snapshot, locale: locale, limit: available) : []
            let desiredIDs = Set(desired.map(\.identifier))
            let obsolete = own.filter { !desiredIDs.contains($0.identifier) }.map(\.identifier)
            // Preserve matching requests, including the existing delivery when replacement fails.
            // Only remove obsolete requests; this also frees capacity for newly planned reminders.
            if !obsolete.isEmpty { await center.removeRequests(withIdentifiers: obsolete) }
            guard latest == nil else { continue }
            let existing = Dictionary(uniqueKeysWithValues: own.map { ($0.identifier, $0) })
            for request in desired {
                if latest != nil { break }
                if let previous = existing[request.identifier], previous == request { continue }
                do { try await center.add(request) }
                catch { continue } // Diff against the actual queue again on the next foreground or data update.
            }
        }
    }

    private func requests(for snapshot: LocalSnapshot, locale: Locale, limit: Int) -> [ReminderNotificationRequest] {
        // Ignore orphaned targets before applying the queue limit so they cannot crowd out valid cards.
        let cardIDs = Set(snapshot.cards.map(\.id))
        let targets = snapshot.targets.filter { cardIDs.contains($0.cardID) }
        return ReminderPlan.upcoming(targets: targets, entries: snapshot.entries, now: now(), limit: limit).compactMap { plan in
            guard let card = snapshot.cards.first(where: { $0.id == plan.cardID }) else { return nil }
            let name = card.isCustom ? card.titleKey : localized(card.titleKey, locale)
            let body = locale.identifier.hasPrefix("zh") ? "该打\(name)卡啦！" : "Time to check in: \(name)"
            let calendar = Calendar(identifier: .gregorian)
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            parts.calendar = calendar
            return ReminderNotificationRequest(identifier: prefix + plan.cardID + "." + LocalDay(date: plan.date).rawValue, body: body, cardID: card.id, dateComponents: parts)
        }
    }
}
