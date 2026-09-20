import Foundation

struct RunningMetricPoint: Identifiable, Sendable, Equatable {
    var id: Int
    var segmentIndex: Int
    var timestamp: Date
    /// Wall-clock offset preserves gaps between separately recorded segments.
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

/// All detail, list and share surfaces use these measured values and the same historical weight snapshot.
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
        var ascent: Double = 0
        var altitudePairs = 0
        var altitudeGroup = 0
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
                    let steps = sample.steps - previous.steps
                    speeds.append(point(value: distance / duration * 3.6, date: sample.timestamp, segment: segmentIndex, index: speeds.count))
                    cadences.append(point(value: Double(steps) / duration * 60, date: sample.timestamp, segment: segmentIndex, index: cadences.count))
                    recordEnergy(duration: duration, distance: distance)
                }
            }
        } else {
            for (segmentIndex, samples) in session.segments.enumerated() {
                var altitudeAnchor: RunningPoint?
                altitudeGroup += 1
                for sample in samples {
                    guard let altitude = sample.validAltitude else { altitudeAnchor = nil; altitudeGroup += 1; continue }
                    altitudes.append(point(value: altitude, date: sample.timestamp, segment: altitudeGroup, index: altitudes.count))
                    if let anchor = altitudeAnchor, let previousAltitude = anchor.validAltitude, sample.timestamp > anchor.timestamp {
                        altitudePairs += 1
                        let difference = altitude - previousAltitude
                        let uncertainty = max(3, max(anchor.verticalAccuracy ?? 0, sample.verticalAccuracy ?? 0))
                        if abs(difference) >= uncertainty {
                            if difference > 0 { ascent += difference }
                            altitudeAnchor = sample
                        }
                    } else { altitudeAnchor = sample }
                }
                for (previous, sample) in zip(samples, samples.dropFirst()) {
                    let duration = sample.timestamp.timeIntervalSince(previous.timestamp)
                    let distance = previous.distance(to: sample)
                    guard duration.isFinite, duration > 0, duration <= 30, distance.isFinite, distance >= 0,
                          distance <= session.kind.maximumSpeedMetersPerSecond * duration + max(10, sample.horizontalAccuracy + previous.horizontalAccuracy) else { continue }
                    speeds.append(point(value: distance / duration * 3.6, date: sample.timestamp, segment: segmentIndex, index: speeds.count))
                    recordEnergy(duration: duration, distance: distance)
                }
            }
        }
        speedSeries = speeds
        cadenceSeries = cadences
        altitudeSeries = altitudes
        maximumSpeedKilometersPerHour = speeds.map(\.value).max()
        maximumCadenceStepsPerMinute = cadences.map(\.value).max()
        minimumAltitudeMeters = altitudes.map(\.value).min()
        maximumAltitudeMeters = altitudes.map(\.value).max()
        ascentMeters = altitudePairs > 0 ? ascent : nil
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
