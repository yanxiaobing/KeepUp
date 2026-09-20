import Foundation
import Testing
@testable import KeepUp

private func statisticsEntry(
    _ id: String,
    day: String = "2026-09-20",
    kind: RunningKind? = .outdoor,
    kilometers: Double? = 1,
    seconds: Double? = 600,
    energy: Double? = 60,
    createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    timeZoneID: String = "Asia/Shanghai"
) -> CheckInEntry {
    var entry = CheckInEntry(
        id: id, cardID: kind?.cardID ?? RunningKind.outdoor.cardID,
        day: LocalDay(rawValue: day)!, timeZoneID: timeZoneID,
        createdAt: createdAt, quantity: kilometers, unit: .kilometers, note: ""
    )
    entry.runningKind = kind
    entry.runningKilocalories = energy
    entry.runningElapsedSeconds = seconds
    return entry
}

@Test func runningStatisticsExcludesManualRecordsAndFiltersEveryMode() {
    let records = [
        statisticsEntry("outdoor", kind: .outdoor, kilometers: 2),
        statisticsEntry("indoor", kind: .indoor, kilometers: 3),
        statisticsEntry("cycling", kind: .cycling, kilometers: 10),
        statisticsEntry("manual", kind: nil, kilometers: 100)
    ]
    let statistics = RunningStatistics(entries: records)
    #expect(statistics.count == 3)
    #expect(statistics.dayCount == 1)
    #expect(statistics.distanceMeters == 15_000)
    #expect(statistics.longestDistanceMeters == 10_000)
    #expect(statistics.kilocalories == 180)
    for kind in RunningKind.allCases {
        let filtered = RunningStatistics(entries: records, kind: kind)
        #expect(filtered.count == 1)
        #expect(filtered.entries.first?.runningKind == kind)
    }
}

@Test func runningStatisticsGroupsByRecordedCivilDayAcrossYearsAndTimeZones() {
    let records = [
        statisticsEntry("new-year", day: "2027-01-01", kind: .indoor, timeZoneID: "Pacific/Kiritimati"),
        statisticsEntry("december", day: "2026-12-31", kind: .cycling, timeZoneID: "Pacific/Honolulu"),
        statisticsEntry("old-january", day: "2026-01-01"),
        statisticsEntry("manual", day: "2025-02-01", kind: nil)
    ]
    let statistics = RunningStatistics(entries: records, kind: .indoor, month: LocalDay(rawValue: "2027-01-25")!)
    #expect(statistics.entries.map(\.id) == ["new-year"])
    #expect(statistics.days.map(\.rawValue) == ["2027-01-01"])
    #expect(statistics.availableMonths.map(\.rawValue) == ["2027-01-01", "2026-12-01", "2026-01-01"])
    let all = RunningStatistics(entries: records)
    #expect(all.days.map(\.rawValue) == ["2027-01-01", "2026-12-31", "2026-01-01"])
    #expect(all.dayCount == 3)
    #expect(all.entries.map(\.id) == ["new-year", "december", "old-january"])
}

@Test func runningStatisticsKeepsUnknownDurationAndEnergyDistinctFromZero() {
    let zero = statisticsEntry("zero", kilometers: 0, seconds: 0, energy: 0)
    let unknown = statisticsEntry("unknown", seconds: nil, energy: nil)
    let known = statisticsEntry("known", seconds: 300, energy: 30)
    let statistics = RunningStatistics(entries: [zero, unknown, known])
    #expect(statistics.count == 3)
    #expect(statistics.elapsedSeconds == 300)
    #expect(statistics.missingDurationCount == 1)
    #expect(statistics.kilocalories == 30)
    #expect(statistics.missingEnergyCount == 1)
    #expect(statistics.averageSpeedKilometersPerHour == nil)
    #expect(statistics.averagePaceSecondsPerKilometer == nil)
    let onlyZero = RunningStatistics(entries: [zero])
    #expect(onlyZero.missingDurationCount == 0)
    #expect(onlyZero.missingEnergyCount == 0)
    #expect(onlyZero.longestDistanceMeters == 0)
    #expect(onlyZero.averageSpeedKilometersPerHour == nil)
}

@Test func runningStatisticsUsesWeightedTotalsAndRoundsEachEnergyBeforeAdding() {
    let statistics = RunningStatistics(entries: [
        statisticsEntry("short", kilometers: 1, seconds: 600, energy: 10.6),
        statisticsEntry("long", kilometers: 3, seconds: 1200, energy: 20.6)
    ])
    #expect(statistics.distanceMeters == 4_000)
    #expect(statistics.elapsedSeconds == 1_800)
    #expect(statistics.kilocalories == 32)
    #expect(statistics.averageSpeedKilometersPerHour == 8)
    #expect(statistics.averagePaceSecondsPerKilometer == 450)
    #expect(statistics.longestDistanceMeters == 3_000)
}

@Test func runningStatisticsRebuildAfterDeletionRemovesDaysMonthsAndTotals() {
    let retained = statisticsEntry("retained", day: "2026-08-01", kilometers: 2)
    let deleted = statisticsEntry("deleted", day: "2026-09-01", kilometers: 4)
    let before = RunningStatistics(entries: [retained, deleted])
    #expect(before.dayCount == 2)
    #expect(before.distanceMeters == 6_000)
    let after = RunningStatistics(entries: [retained])
    #expect(after.count == 1)
    #expect(after.distanceMeters == 2_000)
    #expect(after.days == [retained.day])
    #expect(after.availableMonths.map(\.rawValue) == ["2026-08-01"])
    let empty = RunningStatistics(entries: [])
    #expect(empty.count == 0)
    #expect(empty.dayCount == 0)
    #expect(empty.distanceMeters == 0)
    #expect(empty.elapsedSeconds == 0)
    #expect(empty.kilocalories == 0)
    #expect(empty.missingDurationCount == 0)
    #expect(empty.missingEnergyCount == 0)
    #expect(empty.longestDistanceMeters == nil)
    #expect(empty.averagePaceSecondsPerKilometer == nil)
    #expect(empty.availableMonths.isEmpty)
}

@Test func runningStatisticsTreatsInvalidMetricsAsUnknown() {
    let statistics = RunningStatistics(entries: [
        statisticsEntry("nan", kilometers: .nan, seconds: .nan, energy: .nan),
        statisticsEntry("negative", kilometers: -1, seconds: -1, energy: -1),
        statisticsEntry("infinite", kilometers: .infinity, seconds: .infinity, energy: .infinity)
    ])
    #expect(statistics.count == 3)
    #expect(statistics.distanceMeters == 0)
    #expect(statistics.longestDistanceMeters == nil)
    #expect(statistics.elapsedSeconds == 0)
    #expect(statistics.missingDurationCount == 3)
    #expect(statistics.kilocalories == 0)
    #expect(statistics.missingEnergyCount == 3)
    #expect(statistics.averageSpeedKilometersPerHour == nil)
}

@Test func runningStatisticsSortsRecordsWithinEachDayByCreationTime() {
    let earlier = statisticsEntry("earlier", createdAt: Date(timeIntervalSince1970: 10))
    let later = statisticsEntry("later", createdAt: Date(timeIntervalSince1970: 20))
    let nextDay = statisticsEntry("next", day: "2026-09-21", createdAt: Date(timeIntervalSince1970: 1))
    #expect(RunningStatistics(entries: [earlier, nextDay, later]).entries.map(\.id) == ["next", "later", "earlier"])
}
