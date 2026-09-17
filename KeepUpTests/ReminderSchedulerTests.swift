import XCTest
import UserNotifications
@testable import KeepUp

final class ReminderSchedulerTests: XCTestCase {
    func testSystemQueueAddsSuppressesAndRemovesOwnedRequests() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Grant notification permission in the reminder UI flow before running system-queue integration.")
        }
        let prefix = "keepup.test.\(UUID().uuidString)."
        let scheduler = ReminderScheduler(prefix: prefix)
        defer { Task { await scheduler.synchronize(.empty, locale: Locale(identifier: "en")) } }
        let card = HabitCard.starters[0]
        var target = CardTarget(cardID: card.id); target.reminderEnabled = true; target.weekdays = [1,2,3,4,5,6,7]; target.hour = 23; target.minute = 59
        var snapshot = LocalSnapshot(cards: [card], entries: [], targets: [target])
        await scheduler.synchronize(snapshot, locale: Locale(identifier: "en"))
        let before = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        XCTAssertFalse(before.isEmpty)
        XCTAssertTrue(before.allSatisfy { $0.content.body.contains("Exercise") }, before.first?.content.body ?? "No requests")
        let first = try XCTUnwrap(before.compactMap { request -> (UNNotificationRequest, Date)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger, let date = trigger.nextTriggerDate() else { return nil }
            return (request, date)
        }.sorted { $0.1 < $1.1 }.first)
        let day = LocalDay(date: first.1)
        let entry = CheckInEntry(id: UUID().uuidString, cardID: card.id, day: day, timeZoneID: TimeZone.current.identifier, createdAt: .now, quantity: 10, unit: .minutes, note: "")
        snapshot = LocalSnapshot(cards: [card], entries: [entry], targets: [target])
        await scheduler.synchronize(snapshot, locale: Locale(identifier: "en"))
        let after = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        XCTAssertFalse(after.contains { $0.identifier == first.0.identifier })
        XCTAssertFalse(after.isEmpty)
        await scheduler.synchronize(.empty, locale: Locale(identifier: "en"))
        let remaining = await center.pendingNotificationRequests()
        XCTAssertFalse(remaining.contains { $0.identifier.hasPrefix(prefix) })
    }
}
