import Foundation
import Testing
@testable import KeepUp

private func profileDate(_ components: DateComponents, zone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: components)!
}

@Test func profileDurationStartsAtOneAndAdvancesAtLocalMidnight() {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let start = profileDate(DateComponents(year: 2026, month: 9, day: 20, hour: 23, minute: 59), zone: zone)
    #expect(ProfileDuration.dayCount(since: start, now: start, timeZone: zone) == 1)
    #expect(ProfileDuration.dayCount(since: start, now: start.addingTimeInterval(30), timeZone: zone) == 1)
    #expect(ProfileDuration.dayCount(since: start, now: start.addingTimeInterval(60), timeZone: zone) == 2)
}

@Test func profileDurationCountsCivilDaysAcrossBothDSTChanges() {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let springStart = profileDate(DateComponents(year: 2026, month: 3, day: 8), zone: zone)
    let springEnd = profileDate(DateComponents(year: 2026, month: 3, day: 9), zone: zone)
    #expect(springEnd.timeIntervalSince(springStart) == 23 * 3_600)
    #expect(ProfileDuration.dayCount(since: springStart, now: springEnd, timeZone: zone) == 2)
    let fallStart = profileDate(DateComponents(year: 2026, month: 11, day: 1), zone: zone)
    let fallEnd = profileDate(DateComponents(year: 2026, month: 11, day: 2), zone: zone)
    #expect(fallEnd.timeIntervalSince(fallStart) == 25 * 3_600)
    #expect(ProfileDuration.dayCount(since: fallStart, now: fallEnd, timeZone: zone) == 2)
}

@Test func profileDurationUsesCurrentCivilTimeZoneAndHandlesFutureCreation() {
    let utc = TimeZone(secondsFromGMT: 0)!
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let start = profileDate(DateComponents(year: 2026, month: 9, day: 20, hour: 15, minute: 59), zone: utc)
    let end = start.addingTimeInterval(60)
    #expect(ProfileDuration.dayCount(since: start, now: end, timeZone: utc) == 1)
    #expect(ProfileDuration.dayCount(since: start, now: end, timeZone: shanghai) == 2)
    #expect(ProfileDuration.dayCount(since: end.addingTimeInterval(86_400), now: end, timeZone: shanghai) == 1)
    #expect(ProfileDuration.dayCount(since: Date(timeIntervalSince1970: .nan), now: end, timeZone: shanghai) == 1)
}
