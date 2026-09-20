import Foundation

struct StepReading: Sendable, Equatable {
    let day: LocalDay
    let timeZoneID: String
    let steps: Int
    let distance: Double?
    /// End of the measured interval, never callback arrival time.
    let measuredAt: Date

    var isValid: Bool {
        steps >= 0 && steps <= 1_000_000 && TimeZone(identifier: timeZoneID) != nil &&
        measuredAt.timeIntervalSince1970.isFinite &&
        (distance.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

enum StepsDateRange {
    static func recentDays(now: Date, timeZone: TimeZone) -> [LocalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .map { LocalDay(date: $0, timeZone: timeZone) }
    }

    static func interval(for day: LocalDay, now: Date, timeZone: TimeZone) -> DateInterval? {
        guard recentDays(now: now, timeZone: timeZone).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day.date(in: timeZone))
        guard let end = calendar.date(byAdding: .day, value: 1, to: start), start < now else { return nil }
        return DateInterval(start: start, end: min(end, now))
    }
}
