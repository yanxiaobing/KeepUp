import Foundation

struct RunningMetricPoint: Identifiable, Sendable, Equatable {
    var id: Int
    var segmentIndex: Int
    var timestamp: Date
    /// Raw speed uses wall time; detail chart minute points use active time.
    var timeOffsetSeconds: Double
    var value: Double
}

struct RunningMetricSplit: Identifiable, Sendable, Equatable {
    var kilometer: Int
    var distanceMeters: Double
    var elapsedSeconds: Double
    var isComplete: Bool
    var id: Int { kilometer }
    var paceSecondsPerKilometer: Double? { distanceMeters > 0 && elapsedSeconds > 0 ? elapsedSeconds * 1_000 / distanceMeters : nil }
    var speedKilometersPerHour: Double? { elapsedSeconds > 0 ? distanceMeters / elapsedSeconds * 3.6 : nil }
}

/// All detail, list and share surfaces use the same recorded samples and historical weight snapshot.
struct RunningMetrics: Sendable {
    static let energyAlgorithmVersion = 1
    let elapsedSeconds: Double
    let distanceMeters: Double
    let averageSpeedKilometersPerHour: Double?
    let averagePaceSecondsPerKilometer: Double?
    let splits: [RunningMetricSplit]
    let bestKilometer: RunningMetricSplit?
    let speedSeries: [RunningMetricPoint]
    let cadenceSeries: [RunningMetricPoint]
    let altitudeSeries: [RunningMetricPoint]
    let maximumSpeedKilometersPerHour: Double?
    let maximumCadenceStepsPerMinute: Double?
    let averageCadenceStepsPerMinute: Double?
    let minimumAltitudeMeters: Double?
    let maximumAltitudeMeters: Double?
    let ascentMeters: Double?
    let estimatedEnergyKilocalories: Double?
    var roundedEnergyKilocalories: Int? { Self.roundedEnergy(estimatedEnergyKilocalories) }

    static func roundedEnergy(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0, value.rounded() < Double(Int.max) else { return nil }
        return Int(value.rounded())
    }

    init(session: RunningSession) {
        let end = session.finishedAt ?? session.updatedAt
        elapsedSeconds = session.elapsed(at: end)
        distanceMeters = session.distanceMeters
        averageSpeedKilometersPerHour = elapsedSeconds > 0 && distanceMeters > 0 ? distanceMeters / elapsedSeconds * 3.6 : nil
        averagePaceSecondsPerKilometer = elapsedSeconds > 0 && distanceMeters > 0 ? elapsedSeconds * 1_000 / distanceMeters : nil
        var rows: [RunningMetricSplit] = []
        for split in session.splits {
            guard split.kilometer == rows.count + 1, split.elapsedSeconds.isFinite, split.elapsedSeconds > 0 else { break }
            rows.append(RunningMetricSplit(kilometer: split.kilometer, distanceMeters: 1_000,
                                           elapsedSeconds: split.elapsedSeconds, isComplete: true))
        }
        bestKilometer = rows.min { $0.elapsedSeconds < $1.elapsedSeconds }
        let tailDistance = distanceMeters - Double(rows.count) * 1_000
        if tailDistance > 0.01, tailDistance < 1_000 {
            rows.append(RunningMetricSplit(kilometer: rows.count + 1, distanceMeters: tailDistance,
                                           elapsedSeconds: max(0, elapsedSeconds - rows.reduce(0) { $0 + $1.elapsedSeconds }), isComplete: false))
        }
        splits = rows

        var speeds: [RunningMetricPoint] = []
        var cadences: [RunningMetricPoint] = []
        var altitudes: [RunningMetricPoint] = []
        var energy: Double = 0
        var energySamples = 0
        let minuteCount = elapsedSeconds.isFinite && elapsedSeconds > 0
            ? Int(min(10_000, ceil(elapsedSeconds / 60))) : 0
        func minute(for elapsed: Double) -> Int? {
            guard minuteCount > 0, elapsed.isFinite, elapsed >= 0 else { return nil }
            return max(1, min(minuteCount, Int(min(Double(minuteCount), ceil(elapsed / 60)))))
        }
        func minutePoint(_ value: Double, minute: Int, index: Int) -> RunningMetricPoint {
            let date = session.startedAt.addingTimeInterval(Double(minute) * 60)
            return point(value: value, date: date, segment: 0, index: index)
        }
        var altitudeBuckets: [Int: (sum: Double, count: Int)] = [:]
        var altitudeSum: Double = 0
        var altitudeCount = 0
        var outdoorEndpoints: [Int: (distance: Double, elapsed: Double)] = [:]
        var outdoorDistance: Double = 0
        var indoorRecords: [Int: Double] = [:]
        var lastIndoorRecordElapsed: Double = 0
        var lastIndoorRecordSteps = 0
        let recordedWeight: Double? = {
            guard session.energyAlgorithmVersion == Self.energyAlgorithmVersion,
                  let value = session.weightKilograms, value.isFinite, (5...200).contains(value) else { return nil }
            return value
        }()
        func point(value: Double, date: Date, segment: Int, index: Int) -> RunningMetricPoint {
            RunningMetricPoint(id: index, segmentIndex: segment, timestamp: date,
                               timeOffsetSeconds: max(0, date.timeIntervalSince(session.startedAt)), value: value)
        }
        func recordEnergy(duration: Double, distance: Double) {
            guard let recordedWeight,
                  let value = RunningEnergy.estimateKilocalories(kind: session.kind, weightKilograms: recordedWeight,
                                                               elapsedSeconds: duration, distanceMeters: distance) else { return }
            energy += value
            energySamples += 1
        }

        if session.kind == .indoor {
            for (segmentIndex, samples) in session.indoorSegments.enumerated() {
                for (previous, sample) in zip(samples, samples.dropFirst()) {
                    let duration = sample.elapsedSeconds - previous.elapsedSeconds
                    let distance = sample.distanceMeters - previous.distanceMeters
                    guard sample.timestamp > previous.timestamp, duration.isFinite, duration > 0,
                          distance.isFinite, distance >= 0, distance <= 15 * duration + 10,
                          previous.steps >= 0, sample.steps >= previous.steps else { continue }
                    speeds.append(point(value: distance / duration * 3.6, date: sample.timestamp, segment: segmentIndex, index: speeds.count))
                    // PunchCard records the step delta whenever at least another minute has elapsed.
                    if sample.elapsedSeconds - lastIndoorRecordElapsed >= 60, minuteCount > 0 {
                        let minute = max(1, min(minuteCount, Int(min(Double(minuteCount), floor(sample.elapsedSeconds / 60)))))
                        indoorRecords[minute] = Double(sample.steps - lastIndoorRecordSteps)
                        lastIndoorRecordElapsed = sample.elapsedSeconds
                        lastIndoorRecordSteps = sample.steps
                    }
                    recordEnergy(duration: duration, distance: distance)
                }
            }
        } else {
            // PunchCard stores active elapsed time on every GPS point. Existing KeepUp
            // records have only timestamps, so allocate the session's known paused
            // time to gaps between route segments before assigning chart minutes.
            let occupiedSegments = session.segments.enumerated().compactMap { index, samples -> (index: Int, first: Date, last: Date)? in
                guard let first = samples.first?.timestamp, let last = samples.last?.timestamp else { return nil }
                return (index, first, last)
            }
            var pausedAtSegment = Array(repeating: 0.0, count: session.segments.count)
            let activeDuration = elapsedSeconds
            var pauseRemaining = max(0, end.timeIntervalSince(session.startedAt) - activeDuration)
            var gaps: [(index: Int, duration: Double)] = []
            if occupiedSegments.count > 1 {
                for position in 1..<occupiedSegments.count {
                    let previous = occupiedSegments[position - 1]
                    let next = occupiedSegments[position]
                    gaps.append((next.index, max(0, next.first.timeIntervalSince(previous.last))))
                }
            }
            gaps.sort { $0.duration == $1.duration ? $0.index < $1.index : $0.duration > $1.duration }
            for gap in gaps where pauseRemaining > 0 {
                let paused = min(gap.duration, pauseRemaining)
                pausedAtSegment[gap.index] = paused
                pauseRemaining -= paused
            }
            var pauseBeforeSegment = Array(repeating: 0.0, count: session.segments.count)
            var pauseSoFar: Double = 0
            for index in session.segments.indices {
                pauseSoFar += pausedAtSegment[index]
                pauseBeforeSegment[index] = pauseSoFar
            }
            func activeOffset(_ sample: RunningPoint, segment: Int) -> Double {
                if let measured = sample.activeElapsedSeconds, measured.isFinite, measured >= 0 {
                    return min(activeDuration, measured)
                }
                return min(activeDuration, max(0, sample.timestamp.timeIntervalSince(session.startedAt) - pauseBeforeSegment[segment]))
            }
            for (segmentIndex, samples) in session.segments.enumerated() {
                for sample in samples {
                    guard let altitude = sample.validAltitude,
                          let minute = minute(for: activeOffset(sample, segment: segmentIndex)) else { continue }
                    var bucket = altitudeBuckets[minute] ?? (sum: 0, count: 0)
                    bucket.sum += altitude
                    bucket.count += 1
                    altitudeBuckets[minute] = bucket
                    altitudeSum += altitude
                    altitudeCount += 1
                }
                for (previous, sample) in zip(samples, samples.dropFirst()) {
                    let duration = sample.timestamp.timeIntervalSince(previous.timestamp)
                    let distance = previous.distance(to: sample)
                    guard duration.isFinite, duration > 0, duration <= 30, distance.isFinite, distance >= 0,
                          distance <= session.kind.maximumSpeedMetersPerSecond * duration + max(10, sample.horizontalAccuracy + previous.horizontalAccuracy) else { continue }
                    speeds.append(point(value: distance / duration * 3.6, date: sample.timestamp, segment: segmentIndex, index: speeds.count))
                    if session.kind == .outdoor {
                        outdoorDistance += distance
                        let elapsed = activeOffset(sample, segment: segmentIndex)
                        if let minute = minute(for: elapsed) {
                            outdoorEndpoints[minute] = (distance: outdoorDistance, elapsed: elapsed)
                        }
                    }
                    recordEnergy(duration: duration, distance: distance)
                }
            }
        }
        if altitudeCount > 0 {
            let fallback = ceil(altitudeSum / Double(altitudeCount))
            for minute in 1...minuteCount {
                let value = altitudeBuckets[minute].map { ceil($0.sum / Double($0.count)) } ?? fallback
                altitudes.append(minutePoint(value, minute: minute, index: altitudes.count))
            }
        }
        if session.kind == .outdoor, !outdoorEndpoints.isEmpty {
            var previous = (distance: 0.0, elapsed: 0.0)
            for minute in 1...minuteCount {
                var value: Double = 0
                if let endpoint = outdoorEndpoints[minute] {
                    let duration = endpoint.elapsed - previous.elapsed
                    let distance = endpoint.distance - previous.distance
                    if duration > 0, distance >= 0 {
                        let estimate = distance / 0.8 / duration * 60
                        if estimate.isFinite { value = ceil(estimate) }
                    }
                    previous = endpoint
                }
                cadences.append(minutePoint(value, minute: minute, index: cadences.count))
            }
        } else if session.kind == .indoor, !indoorRecords.isEmpty {
            for minute in 1...minuteCount {
                cadences.append(minutePoint(indoorRecords[minute] ?? 0, minute: minute, index: cadences.count))
            }
        }
        speedSeries = speeds
        cadenceSeries = cadences
        altitudeSeries = altitudes
        maximumSpeedKilometersPerHour = speeds.map(\.value).max()
        maximumCadenceStepsPerMinute = cadences.map(\.value).max()
        if cadences.isEmpty {
            averageCadenceStepsPerMinute = nil
        } else {
            let divisor = session.kind == .indoor ? indoorRecords.keys.max() ?? minuteCount : minuteCount
            averageCadenceStepsPerMinute = floor(cadences.reduce(0) { $0 + $1.value } / Double(max(1, divisor)))
        }
        minimumAltitudeMeters = altitudes.map(\.value).min()
        maximumAltitudeMeters = altitudes.map(\.value).max()
        ascentMeters = altitudes.isEmpty ? nil : ceil(zip(altitudes, altitudes.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1.value - pair.0.value)
        })
        estimatedEnergyKilocalories = energySamples > 0 && energy.isFinite ? energy : nil
    }
}

/// Version 1 ports PunchCard's speed/MET tables and its current flat-gradient callers.
/// Endpoint clamping fixes the original running table's exact-maximum/above-maximum discontinuity.
enum RunningEnergy {
    static func estimateKilocalories(kind: RunningKind, weightKilograms: Double, elapsedSeconds: Double, distanceMeters: Double) -> Double? {
        guard weightKilograms.isFinite, (5...200).contains(weightKilograms),
              elapsedSeconds.isFinite, elapsedSeconds > 0, distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        if kind == .cycling, distanceMeters == 0 { return 0 }
        let speed = distanceMeters / elapsedSeconds
        let speeds: [Double]
        let mets: [Double]
        if kind == .cycling {
            speeds = [0, 4.5, 5.4, 6.3, 7.2, 8.9]
            mets = [4, 6, 8, 10, 12, 16]
        } else {
            speeds = [0, 0.223, 0.447, 0.67, 0.894, 1.117, 1.341, 1.564, 1.788, 2.011, 2.235, 2.332, 2.682, 2.98, 3.155, 3.352, 3.576, 3.831, 4.126, 4.47, 4.876]
            mets = [1.2, 1.5, 1.8, 2.1, 2.5, 3, 3.3, 3.8, 5, 6.3, 8, 9, 10, 11, 11.5, 12.5, 13.5, 14, 15, 16, 18]
        }
        let met: Double
        if speed <= speeds[0] || (kind != .cycling && speed < speeds[1]) { met = mets[0] }
        else if speed >= speeds[speeds.count - 1] { met = mets[mets.count - 1] }
        else {
            guard let upper = speeds.firstIndex(where: { $0 > speed }), upper > 0 else { return nil }
            let lower = upper - 1
            let fraction = (speed - speeds[lower]) / (speeds[upper] - speeds[lower])
            met = mets[lower] + fraction * (mets[upper] - mets[lower])
        }
        let value = met * weightKilograms * elapsedSeconds / 3_600
        return value.isFinite ? value : nil
    }
}
