import Foundation
import Testing
@testable import KeepUp

@Test func dayIdentityDoesNotDependOnLanguageAndRetainsRecordedZone() {
    let date = Date(timeIntervalSince1970: 1_789_430_400)
    let shanghai = LocalDay(date: date, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    let losAngeles = LocalDay(date: date, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    #expect(shanghai != losAngeles)
    #expect(LocalDay(rawValue: shanghai.rawValue) == shanghai)
    #expect(LocalDay(rawValue: "2026-02-30") == nil)
    #expect(LocalDay(rawValue: "2026-2-03") == nil)
}

@Test func streakCountsCivilDaysAcrossDSTAndDeduplicatesSameDay() {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let days = ["2026-03-07", "2026-03-08", "2026-03-08", "2026-03-09"]
    let entries = days.map { day in
        CheckInEntry(id: UUID().uuidString, cardID: "preset.fruit", day: LocalDay(rawValue: day)!,
                     timeZoneID: zone.identifier, createdAt: .now, quantity: nil, unit: .none, note: "")
    }
    #expect(RecordStatistics.streak(entries: entries, today: LocalDay(rawValue: "2026-03-09")!, timeZone: zone) == 3)
    #expect(RecordStatistics.streak(entries: entries, today: LocalDay(rawValue: "2026-03-10")!, timeZone: zone) == 3)
    #expect(RecordStatistics.streak(entries: entries, today: LocalDay(rawValue: "2026-03-11")!, timeZone: zone) == 0)
}
