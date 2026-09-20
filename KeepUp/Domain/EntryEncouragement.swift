import Foundation

/// Ordinary posters use saved measurements and target snapshots, never the current weight target.
enum EntryEncouragement: Equatable {
    case general
    case checkIns(Int)
    case quantity(Double)
    case streak(Int)
    case weightGoal(losing: Bool, days: Int, change: Double)

    static func candidates(entry: CheckInEntry, card: HabitCard, entries: [CheckInEntry],
                           weight: WeightRecord?, today: LocalDay) -> [Self] {
        if entry.cardID == "punchcard.50", entry.unit == .kilograms,
           let value = entry.quantity, value.isFinite, (5...200).contains(value),
           let target = weight?.target, target.initial.isFinite, target.target.isFinite,
           (20...200).contains(target.initial), (20...200).contains(target.target), target.initial != target.target,
           target.end > target.start, entry.day >= target.start, target.achieved(by: value) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let days = calendar.dateComponents([.day], from: target.start.date(in: .gmt), to: entry.day.date(in: .gmt)).day ?? 0
            return [.weightGoal(losing: target.target < target.initial, days: max(1, days), change: abs(value - target.initial))]
        }

        let matching = entries.filter { $0.cardID == card.id }
        var result: [Self] = []
        if matching.count > 1 { result.append(.checkIns(matching.count)) }
        if card.unit != .none, card.unit != .kilograms {
            // Unit mismatches and missing/invalid measurements must not inflate the total.
            let values = matching.compactMap { record -> Double? in
                guard record.unit == card.unit, let value = record.quantity, value.isFinite, value > 0 else { return nil }
                return value
            }
            // Sort for reproducible floating-point addition regardless of snapshot ordering.
            let total = values.sorted().reduce(0, +)
            if total.isFinite, total > 0 { result.append(.quantity(total)) }
        }
        let streak = RecordStatistics.streak(entries: entries, today: today, timeZone: .gmt)
        if streak > 1 { result.append(.streak(streak)) }
        result.append(.general)
        return result
    }

    static func selected(entry: CheckInEntry, card: HabitCard, entries: [CheckInEntry],
                         weight: WeightRecord?, today: LocalDay) -> Self {
        let choices = candidates(entry: entry, card: card, entries: entries, weight: weight, today: today)
        // Unlike Swift's randomized Hasher, this is stable across redraws, exports and relaunches.
        let seed = entry.id.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        return choices[Int(seed % UInt64(choices.count))]
    }

    func text(card: HabitCard, locale: Locale) -> String {
        let name = localized(card.titleKey, locale)
        switch self {
        case .general:
            return localized("entry.encouragement.general", locale)
        case .checkIns(let count):
            return String(format: localized("entry.encouragement.count", locale), name, count.formatted(.number.locale(locale)))
        case .quantity(let total):
            return String(format: localized("entry.encouragement.total", locale), name,
                          total.formatted(.number.precision(.fractionLength(0...1)).locale(locale)), localized(card.unit.titleKey, locale))
        case .streak(let days):
            return String(format: localized("entry.encouragement.streak", locale), days.formatted(.number.locale(locale)))
        case .weightGoal(let losing, let days, let change):
            let key: String
            if losing { key = days == 1 ? "entry.encouragement.weightLossOne" : "entry.encouragement.weightLoss" }
            else { key = days == 1 ? "entry.encouragement.weightGainOne" : "entry.encouragement.weightGain" }
            return String(format: localized(key, locale), days.formatted(.number.locale(locale)),
                          change.formatted(.number.precision(.fractionLength(1)).locale(locale)))
        }
    }
}
