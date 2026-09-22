import Foundation

/// A sensor measurement is independent of a completed check-in.
struct StepRecord: Codable, Equatable, Sendable {
    let day: LocalDay
    let timeZoneID: String
    let steps: Int
    let distance: Double?
    let measuredAt: Date
    let goal: Int?
    var checkInDeleted: Bool? = nil
    var intraday: StepIntraday? = nil
}

/// Five-minute queries, including explicit unknown readings when a query fails.
struct StepInterval: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
    let steps: Int?
}

struct StepIntraday: Codable, Equatable, Sendable {
    let intervals: [StepInterval]
    let measuredThrough: Date

    static func ranges(day: LocalDay, through: Date, timeZone: TimeZone) -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day.date(in: timeZone))
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let end = min(through, next)
        var cursor = start
        var result: [DateInterval] = []
        while cursor < end {
            let upper = min(cursor.addingTimeInterval(300), end)
            result.append(DateInterval(start: cursor, end: upper))
            cursor = upper
        }
        return result
    }

    func isValid(day: LocalDay, timeZoneID: String) -> Bool {
        guard let zone = TimeZone(identifier: timeZoneID), measuredThrough.timeIntervalSince1970.isFinite else { return false }
        let expected = Self.ranges(day: day, through: measuredThrough, timeZone: zone)
        guard !expected.isEmpty, expected.count == intervals.count, expected.last?.end == measuredThrough else { return false }
        return zip(intervals, expected).allSatisfy { sample, range in
            sample.start == range.start && sample.end == range.end &&
            (sample.steps.map { (0...1_000_000).contains($0) } ?? true)
        }
    }

    var isComplete: Bool { !intervals.isEmpty && intervals.allSatisfy { $0.steps != nil } }
    /// Matches PunchCard: count the duration of five-minute bins with more than five steps.
    var estimatedActiveMinutes: Int? {
        guard isComplete else { return nil }
        return Int(intervals.filter { ($0.steps ?? 0) > 5 }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
    }

    struct Hour: Identifiable {
        let start: Date
        let steps: Int?
        var id: Date { start }
    }

    func hours(timeZoneID: String) -> [Hour] {
        guard let zone = TimeZone(identifier: timeZoneID) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let groups = Dictionary(grouping: intervals) { calendar.dateInterval(of: .hour, for: $0.start)!.start }
        return groups.keys.sorted().map { start in
            let samples = groups[start]!
            return Hour(start: start, steps: samples.allSatisfy { $0.steps != nil } ? samples.reduce(0) { $0 + ($1.steps ?? 0) } : nil)
        }
    }
}
