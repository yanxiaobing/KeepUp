import Foundation

struct CardTarget: Identifiable, Codable, Equatable, Sendable {
    static let registrationDefaults = [
        CardTarget(cardID: "punchcard.2", isPinned: true, showsProgress: true),
        CardTarget(cardID: "punchcard.50", isPinned: true, showsProgress: true),
        CardTarget(cardID: "punchcard.63", isPinned: true, showsProgress: true, hour: 8)
    ]

    var cardID: String
    var isPinned = false
    var showsProgress = false
    var reminderEnabled = false
    // ISO weekday: Monday = 1, Sunday = 7.
    var weekdays = [1, 2, 3, 4, 5]
    var hour = 21
    var minute = 0
    var id: String { cardID }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
    var isEmpty: Bool { !isPinned && !showsProgress && !reminderEnabled }
    func validated() throws -> Self {
        guard (0...23).contains(hour), (0...59).contains(minute), weekdays.allSatisfy({ (1...7).contains($0) }),
              !reminderEnabled || !weekdays.isEmpty else { throw StoreError.invalidTarget }
        var value = self; value.weekdays = Array(Set(weekdays)).sorted(); return value
    }
    func completedDays(entries: [CheckInEntry], day: LocalDay, timeZone: TimeZone = .current) -> Set<LocalDay> {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone; calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: day.date(in: timeZone))!.start
        let first = LocalDay(date: start, timeZone: timeZone)
        let end = LocalDay(date: calendar.date(byAdding: .day, value: 7, to: start)!, timeZone: timeZone)
        return Set(entries.filter { $0.cardID == cardID && $0.day >= first && $0.day < end && $0.day <= day }.map(\.day))
    }
}

struct PlannedReminder: Sendable, Equatable {
    let cardID: String
    let date: Date
    let identifier: String
}

enum ReminderPlan {
    // iOS retains a bounded pending queue. Refill at launch, foreground, and every relevant edit.
    static func upcoming(targets: [CardTarget], entries: [CheckInEntry], now: Date, timeZone: TimeZone = .current, limit: Int = 64) -> [PlannedReminder] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let completed = Dictionary(grouping: entries, by: \.cardID).mapValues { Set($0.map(\.day)) }
        var plans: [PlannedReminder] = []
        for offset in 0..<90 {
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            let localDay = LocalDay(date: day, timeZone: timeZone)
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            for target in targets where target.reminderEnabled && target.weekdays.contains(weekday) {
                guard completed[target.cardID]?.contains(localDay) != true,
                      let date = calendar.date(bySettingHour: target.hour, minute: target.minute, second: 0, of: day), date > now else { continue }
                plans.append(.init(cardID: target.cardID, date: date, identifier: "keepup.reminder.\(target.cardID).\(localDay.rawValue)"))
            }
        }
        return Array(plans.sorted { $0.date == $1.date ? $0.identifier < $1.identifier : $0.date < $1.date }.prefix(max(0, limit)))
    }
}
