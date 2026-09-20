import XCTest
import UserNotifications
@testable import KeepUp

final class ReminderSchedulerTests: XCTestCase {
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 12))!
    private let locale = Locale(identifier: "en")

    private func snapshot() -> LocalSnapshot {
        let card = HabitCard.starters[0]
        var target = CardTarget(cardID: card.id)
        target.reminderEnabled = true
        target.weekdays = [1, 2, 3, 4, 5, 6, 7]
        target.hour = 23; target.minute = 59
        return LocalSnapshot(cards: [card], entries: [], targets: [target])
    }

    func testUnchangedSnapshotDoesNotRewritePendingReminders() async {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        await scheduler.synchronize(snapshot(), locale: locale)
        let initial = await center.pendingRequests()
        XCTAssertEqual(initial.count, 64)
        await center.resetOperations()
        await scheduler.synchronize(snapshot(), locale: locale)
        let operations = await center.operations()
        XCTAssertEqual(operations.added, 0)
        XCTAssertEqual(operations.removed, [])
    }

    func testCheckInRemovesOnlyCompletedDayAndRefillsQueue() async throws {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        var snapshot = snapshot()
        await scheduler.synchronize(snapshot, locale: locale)
        let before = await center.pendingRequests()
        let first = try XCTUnwrap(before.sorted { $0.identifier < $1.identifier }.first)
        let components = try XCTUnwrap(first.dateComponents)
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let entry = CheckInEntry(id: UUID().uuidString, cardID: snapshot.cards[0].id, day: LocalDay(date: date), timeZoneID: TimeZone.current.identifier, createdAt: now, quantity: 10, unit: .minutes, note: "")
        snapshot = LocalSnapshot(cards: snapshot.cards, entries: [entry], targets: snapshot.targets)
        await center.resetOperations()
        await scheduler.synchronize(snapshot, locale: locale)
        let operations = await center.operations()
        let after = await center.pendingRequests()
        XCTAssertEqual(operations.removed, [first.identifier])
        XCTAssertEqual(operations.added, 1)
        XCTAssertEqual(after.count, 64)
        XCTAssertFalse(after.contains { $0.identifier == first.identifier })
    }

    func testForeignRequestsArePreservedAndCountTowardCapacity() async {
        let foreign = (0..<60).map { ReminderNotificationRequest(identifier: "another.feature.\($0)") }
        let center = FakeReminderNotificationCenter(requests: foreign)
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        await scheduler.synchronize(snapshot(), locale: locale)
        let pending = await center.pendingRequests()
        XCTAssertEqual(pending.count, 64)
        XCTAssertEqual(pending.filter { $0.identifier.hasPrefix("keepup.reminder.") }.count, 4)
        await scheduler.synchronize(.empty, locale: locale)
        let remaining = await center.pendingRequests()
        XCTAssertEqual(Set(remaining.map(\.identifier)), Set(foreign.map(\.identifier)))
    }

    func testDeniedPermissionRemovesOnlyOwnedRequestsAndGrantRestoresThem() async {
        let foreign = ReminderNotificationRequest(identifier: "another.feature")
        let center = FakeReminderNotificationCenter(requests: [foreign])
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        await scheduler.synchronize(snapshot(), locale: locale)
        await center.setAuthorization(.denied)
        await scheduler.synchronize(snapshot(), locale: locale)
        let remaining = await center.pendingRequests()
        XCTAssertEqual(remaining.map(\.identifier), [foreign.identifier])
        await center.setAuthorization(.authorized)
        await scheduler.synchronize(snapshot(), locale: locale)
        let restored = await center.pendingRequests()
        XCTAssertEqual(restored.count, 64)
    }

    func testFailedReplacementPreservesOldRequestsAndRetriesNextSynchronization() async {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        await scheduler.synchronize(snapshot(), locale: locale)
        let before = await center.pendingRequests()
        await center.setFailingAdds(true)
        await scheduler.synchronize(snapshot(), locale: Locale(identifier: "zh-Hans"))
        let failed = await center.pendingRequests()
        XCTAssertEqual(Set(failed.map(\.identifier)), Set(before.map(\.identifier)))
        XCTAssertTrue(failed.allSatisfy { $0.body.hasPrefix("Time to check in:") })
        await center.setFailingAdds(false)
        await scheduler.synchronize(snapshot(), locale: Locale(identifier: "zh-Hans"))
        let retried = await center.pendingRequests()
        XCTAssertEqual(retried.count, 64)
        XCTAssertTrue(retried.allSatisfy { $0.body.hasPrefix("该打") })
    }

    func testMissingRequestsAreRetriedAfterInitialWriteFailure() async {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        await center.setFailingAdds(true)
        await scheduler.synchronize(snapshot(), locale: locale)
        let failed = await center.pendingRequests()
        XCTAssertTrue(failed.isEmpty)
        await center.setFailingAdds(false)
        await scheduler.synchronize(snapshot(), locale: locale)
        let retried = await center.pendingRequests()
        XCTAssertEqual(retried.count, 64)
    }

    func testTimeEditReplacesTriggersWithoutDeletingStableIdentifiers() async {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        let initial = snapshot()
        await scheduler.synchronize(initial, locale: locale)
        let before = await center.pendingRequests()
        var target = initial.targets[0]
        target.minute = 58
        await center.resetOperations()
        await scheduler.synchronize(LocalSnapshot(cards: initial.cards, entries: [], targets: [target]), locale: locale)
        let after = await center.pendingRequests()
        let operations = await center.operations()
        XCTAssertEqual(Set(after.map(\.identifier)), Set(before.map(\.identifier)))
        XCTAssertEqual(operations.added, 64)
        XCTAssertEqual(operations.removed, [])
        XCTAssertTrue(after.allSatisfy { $0.dateComponents?.minute == 58 })
    }

    func testNewerSnapshotWinsWhenAnOlderAddIsInFlight() async {
        let center = FakeReminderNotificationCenter()
        let now = now
        let scheduler = ReminderScheduler(center: center, now: { now })
        let snapshot = snapshot()
        let locale = locale
        await center.pauseNextAdd()
        let first = Task { await scheduler.synchronize(snapshot, locale: locale) }
        await center.waitUntilAddIsPaused()
        await scheduler.synchronize(.empty, locale: locale)
        await center.resumeAdd()
        await first.value
        let remaining = await center.pendingRequests()
        XCTAssertTrue(remaining.isEmpty)
    }

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

private actor FakeReminderNotificationCenter: ReminderNotificationCenter {
    private var requests: [String: ReminderNotificationRequest]
    private var status: UNAuthorizationStatus = .authorized
    private var added = 0
    private var removed: [String] = []
    private var failingAdds = false
    private var shouldPauseAdd = false
    private var pausedAdd: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?

    init(requests: [ReminderNotificationRequest] = []) {
        self.requests = Dictionary(uniqueKeysWithValues: requests.map { ($0.identifier, $0) })
    }
    func requestAuthorization() async throws -> Bool { status == .authorized }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pendingRequests() async -> [ReminderNotificationRequest] { Array(requests.values) }
    func add(_ request: ReminderNotificationRequest) async throws {
        if shouldPauseAdd {
            shouldPauseAdd = false
            await withCheckedContinuation { continuation in
                pausedAdd = continuation
                pauseObserver?.resume()
                pauseObserver = nil
            }
        }
        added += 1
        if failingAdds { throw CocoaError(.fileWriteUnknown) }
        requests[request.identifier] = request
    }
    func removeRequests(withIdentifiers identifiers: [String]) async {
        removed += identifiers
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }
    func setAuthorization(_ status: UNAuthorizationStatus) { self.status = status }
    func setFailingAdds(_ value: Bool) { failingAdds = value }
    func resetOperations() { added = 0; removed = [] }
    func operations() -> (added: Int, removed: [String]) { (added, removed) }
    func pauseNextAdd() { shouldPauseAdd = true }
    func waitUntilAddIsPaused() async {
        if pausedAdd != nil { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }
    func resumeAdd() { pausedAdd?.resume(); pausedAdd = nil }
}
