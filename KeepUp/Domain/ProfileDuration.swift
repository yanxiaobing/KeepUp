import Foundation

enum ProfileDuration {
    /// The creation date is day one. Calendar days keep this stable across DST.
    static func dayCount(since createdAt: Date, now: Date = .now, timeZone: TimeZone = .current) -> Int {
        guard createdAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              createdAt <= now else { return 1 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: createdAt)
        let end = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day,
              days >= 0, days < Int.max else { return 1 }
        return days + 1
    }
}
