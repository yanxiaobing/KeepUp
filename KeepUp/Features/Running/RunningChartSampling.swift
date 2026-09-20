import Foundation

/// Rendering-only reduction. Statistics always use the complete RunningMetrics series.
enum RunningChartSampling {
    static func points(_ points: [RunningMetricPoint], budget: Int = 500) -> [RunningMetricPoint] {
        guard points.count > max(4, budget) else { return points }
        var groups: [[RunningMetricPoint]] = []
        var positions: [Int: Int] = [:]
        for point in points {
            if let index = positions[point.segmentIndex] { groups[index].append(point) }
            else { positions[point.segmentIndex] = groups.count; groups.append([point]) }
        }
        // Each recorded segment keeps both endpoints and its extrema, even when an
        // unusually fragmented session needs more than the normal overall budget.
        let minimums = groups.map { min(4, $0.count) }
        let minimumTotal = minimums.reduce(0, +)
        let target = max(budget, minimumTotal)
        let spare = groups.map { max(0, $0.count - 4) }
        let totalSpare = spare.reduce(0, +)
        let remaining = min(totalSpare, max(0, target - minimumTotal))
        var allocations = minimums
        if totalSpare > 0, remaining > 0 {
            var fractions: [(index: Int, fraction: Double)] = []
            var allocated = 0
            for index in groups.indices {
                let portion = Double(remaining) * Double(spare[index]) / Double(totalSpare)
                let whole = Int(portion)
                allocations[index] += whole
                allocated += whole
                fractions.append((index, portion - Double(whole)))
            }
            fractions.sort { $0.fraction == $1.fraction ? $0.index < $1.index : $0.fraction > $1.fraction }
            for value in fractions.prefix(remaining - allocated) { allocations[value.index] += 1 }
        }
        return groups.indices.flatMap { reduce(groups[$0], to: allocations[$0]) }
    }

    private static func reduce(_ points: [RunningMetricPoint], to budget: Int) -> [RunningMetricPoint] {
        guard points.count > budget, points.count > 4 else { return points }
        let bucketCount = max(1, (budget - 2) / 2)
        let interiorCount = points.count - 2
        var selected = Set([0, points.count - 1])
        for bucket in 0..<bucketCount {
            let start = 1 + bucket * interiorCount / bucketCount
            let end = 1 + (bucket + 1) * interiorCount / bucketCount
            guard start < end else { continue }
            var minimum = start
            var maximum = start
            for index in start..<end {
                if points[index].value < points[minimum].value { minimum = index }
                if points[index].value > points[maximum].value { maximum = index }
            }
            selected.insert(minimum)
            selected.insert(maximum)
        }
        return selected.sorted().map { points[$0] }
    }
}
