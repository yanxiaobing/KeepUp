import Foundation

/// 汇总已完成运动的轻量记录，不读取轨迹，也不重新估算历史热量。
struct RunningStatistics: Sendable {
    let entries: [CheckInEntry]
    let count: Int
    let dayCount: Int
    let distanceMeters: Double
    let elapsedSeconds: Double
    let missingDurationCount: Int
    let kilocalories: Int
    let missingEnergyCount: Int
    let averageSpeedKilometersPerHour: Double?
    let averagePaceSecondsPerKilometer: Double?
    let longestDistanceMeters: Double?
    let days: [LocalDay]
    /// 始终来自全部运动记录，切换模式或月份不会丢失月份筛选项。
    let availableMonths: [LocalDay]

    init(entries allEntries: [CheckInEntry], kind: RunningKind? = nil, month: LocalDay? = nil) {
        let recorded = allEntries.filter { $0.runningKind != nil }
        availableMonths = Set(recorded.map { Self.month(of: $0.day) }).sorted(by: >)
        let selectedMonth = month.map(Self.month(of:))
        entries = recorded.filter { entry in
            (kind == nil || entry.runningKind == kind)
                && (selectedMonth == nil || Self.month(of: entry.day) == selectedMonth)
        }.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
        count = entries.count
        days = Set(entries.map(\.day)).sorted(by: >)
        dayCount = days.count

        let distances = entries.compactMap { entry -> Double? in
            guard entry.unit == .kilometers, let quantity = entry.quantity,
                  quantity.isFinite, quantity >= 0, (quantity * 1_000).isFinite else { return nil }
            return quantity * 1_000
        }
        distanceMeters = distances.reduce(0, +)
        longestDistanceMeters = distances.max()

        let durations = entries.compactMap { entry -> Double? in
            guard let seconds = entry.runningElapsedSeconds, seconds.isFinite, seconds >= 0 else { return nil }
            return seconds
        }
        elapsedSeconds = durations.reduce(0, +)
        missingDurationCount = count - durations.count

        let energies = entries.compactMap { RunningMetrics.roundedEnergy($0.runningKilocalories) }
        // 与每条记录显示的整数热量相加一致，不能先加浮点数再取整。
        kilocalories = energies.reduce(0, +)
        missingEnergyCount = count - energies.count

        let canAverage = count > 0 && missingDurationCount == 0 && distances.count == count
            && elapsedSeconds.isFinite && elapsedSeconds > 0 && distanceMeters.isFinite && distanceMeters > 0
        averageSpeedKilometersPerHour = canAverage ? distanceMeters / elapsedSeconds * 3.6 : nil
        averagePaceSecondsPerKilometer = canAverage ? elapsedSeconds * 1_000 / distanceMeters : nil
    }

    private static func month(of day: LocalDay) -> LocalDay {
        // LocalDay 已校验年月日；直接使用记录年月，避免当前时区参与分组。
        LocalDay(rawValue: String(day.rawValue.prefix(7)) + "-01")!
    }
}
