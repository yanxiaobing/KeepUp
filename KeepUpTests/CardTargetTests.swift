import Foundation
import Testing
@testable import KeepUp

private let zone = TimeZone(identifier: "America/Los_Angeles")!
private func day(_ text: String) -> LocalDay { LocalDay(rawValue: text)! }
private func entry(_ date: String, id: String = UUID().uuidString, card: String = "preset.exercise") -> CheckInEntry {
    .init(id: id, cardID: card, day: day(date), timeZoneID: zone.identifier, createdAt: day(date).date(in: zone), quantity: 30, unit: .minutes, note: "")
}

@Test func weeklyProgressCountsDaysAndUsesMondayAcrossDST() {
    let target = CardTarget(cardID: "preset.exercise")
    let records = [entry("2026-03-01"), entry("2026-03-02"), entry("2026-03-02"), entry("2026-03-08"), entry("2026-03-09"), entry("2026-03-03", card: "other")]
    #expect(target.completedDays(entries: records, day: day("2026-03-08"), timeZone: zone) == [day("2026-03-02"), day("2026-03-08")])
    #expect(target.completedDays(entries: records, day: day("2026-03-09"), timeZone: zone) == [day("2026-03-09")])
    #expect(target.completedDays(entries: records, day: day("2026-03-08"), timeZone: zone, firstWeekday: 1) ==
            [day("2026-03-08")])
}

@Test func remindersSkipCompletedDaysKeepFutureAndRespectQueueLimit() {
    var target = CardTarget(cardID: "preset.exercise"); target.reminderEnabled = true; target.weekdays = [1, 2, 3, 4, 5, 6, 7]
    let now = day("2026-03-07").date(in: zone)
    let records = [entry("2026-03-07"), entry("2026-03-07")]
    let plans = ReminderPlan.upcoming(targets: [target], entries: records, now: now, timeZone: zone)
    #expect(plans.count == 64)
    #expect(LocalDay(date: plans[0].date, timeZone: zone) == day("2026-03-08"))
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    #expect(plans.allSatisfy { calendar.component(.hour, from: $0.date) == 21 })
    #expect(Set(plans.map(\.identifier)).count == 64)
    #expect(ReminderPlan.upcoming(targets: [target], entries: [], now: now, timeZone: zone, limit: 1).first!.date < plans[0].date)
    target.reminderEnabled = false
    #expect(ReminderPlan.upcoming(targets: [target], entries: [], now: now, timeZone: zone).isEmpty)
}
