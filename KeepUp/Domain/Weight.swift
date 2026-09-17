import Foundation

struct WeightTarget: Codable, Equatable, Sendable {
    var id = UUID().uuidString
    var initial: Double
    var target: Double
    var start: LocalDay
    var end: LocalDay
    func validated(now: Date, timeZone: TimeZone = .current) throws -> Self {
        let today = LocalDay(date: now, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let latest = LocalDay(date: calendar.date(byAdding: .year, value: 1, to: today.date(in: timeZone))!, timeZone: timeZone)
        guard initial.isFinite, target.isFinite, (20...200).contains(initial), (20...200).contains(target),
              initial != target, start == today, end > start, end <= latest else { throw StoreError.invalidWeightTarget }
        var value = self; value.initial = (initial*10).rounded()/10; value.target = (target*10).rounded()/10
        guard value.initial != value.target else { throw StoreError.invalidWeightTarget }
        return value
    }
    func achieved(by value: Double) -> Bool { target < initial ? value <= target : value >= target }
    func progress(at value: Double) -> Double { (value-initial)/(target-initial) }
    var weeklyChange: Double {
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start.date(in: .gmt), to: end.date(in: .gmt)).day ?? 1
        return abs(target-initial)/max(1, ceil(Double(days)/7))
    }
}

struct WeightRecord: Codable, Equatable, Sendable {
    var height: Double?
    var target: WeightTarget?
}

enum WeightMetrics {
    static func bmi(weight: Double, height: Double?) -> Double? {
        guard let height, height.isFinite, height > 0 else { return nil }
        return weight / pow(height/100, 2)
    }
    // PunchCard's existing display bands; this is a UI compatibility mapping.
    static func descriptionKey(bmi: Double) -> String {
        switch bmi { case ..<18.5: "weight.bmi.low"; case ..<25: "weight.bmi.normal"; case ..<28: "weight.bmi.high"; case ...32: "weight.bmi.higher"; default: "weight.bmi.highest" }
    }
}
