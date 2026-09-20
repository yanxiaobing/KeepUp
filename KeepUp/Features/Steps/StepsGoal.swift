import Foundation

extension Defaults.Keys {
    static let stepGoalChanges = Key<[String: Int]>("stepGoalChanges", default: [:], suite: AppPreferences.store)
}

enum StepsGoal {
    static let choices = Array(stride(from: 5_000, through: 30_000, by: 1_000))
    static func value(on day: LocalDay, changes: [String: Int] = Defaults[.stepGoalChanges]) -> Int? {
        let key = changes.keys.filter { $0 <= day.rawValue }.max()
        guard let key, let value = changes[key], choices.contains(value) else { return nil }
        return value
    }

    static func updated(_ changes: [String: Int], value: Int, now: Date, timeZone: TimeZone) -> [String: Int] {
        guard choices.contains(value) else { return changes }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = changes.isEmpty ? now : calendar.date(byAdding: .day, value: 1, to: now)!
        var result = changes
        result[LocalDay(date: date, timeZone: timeZone).rawValue] = value
        return result
    }
}
