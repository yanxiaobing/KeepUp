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

@Test func themeCalendarUsesRealMonthAndLocaleWeekStart() throws {
    let calendar = Calendar(identifier: .gregorian)
    let september = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))

    let chinese = ThemeCalendarMonth(date: september, locale: Locale(identifier: "zh_CN"))
    #expect(chinese.firstWeekday == 2)
    #expect(chinese.weekdaySymbols.first == "一")
    #expect(chinese.leadingDayCount == 1) // September 1, 2026 is Tuesday.
    #expect(chinese.dayCount == 30)
    #expect(chinese.cellCount == 35)
    #expect(chinese.day(at: 0) == nil)
    #expect(chinese.day(at: 1) == 1)
    #expect(chinese.day(at: 30) == 30)
    #expect(chinese.day(at: 31) == nil)

    let english = ThemeCalendarMonth(date: september, locale: Locale(identifier: "en_US"))
    #expect(english.firstWeekday == 1)
    #expect(english.weekdaySymbols.first == "S")
    #expect(english.leadingDayCount == 2)
    #expect(english.day(at: 2) == 1)

    let august = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
    #expect(ThemeCalendarMonth(date: august, locale: Locale(identifier: "en_US")).cellCount == 42)
}
