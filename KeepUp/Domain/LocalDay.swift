import Foundation

/// A recorded civil date. It does not move when the device changes time zone.
struct LocalDay: Hashable, Comparable, Sendable {
    let rawValue: String

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              LocalDay(date: date, timeZone: calendar.timeZone).rawValue == rawValue else { return nil }
        self.rawValue = rawValue
    }

    func date(in timeZone: TimeZone = .current) -> Date {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Noon avoids most midnight DST transitions in civil date presentation.
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum RecordStatistics {
    static func streak(entries: [CheckInEntry], today: LocalDay, timeZone: TimeZone = .current) -> Int {
        let days = Set(entries.map(\.day))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var cursor = today.date(in: timeZone)
        if !days.contains(today) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var count = 0
        while days.contains(LocalDay(date: cursor, timeZone: timeZone)) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }
}

extension LocalDay: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = LocalDay(rawValue: raw) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid civil date") }
        self = day
    }
    func encode(to encoder: any Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}
