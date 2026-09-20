import Foundation
import Testing
@testable import KeepUp

private let metricsOrigin = Date(timeIntervalSince1970: 1_800_000_000)
private func metricGPS(_ seconds: Double, latitude: Double = 31, altitude: Double? = nil, accuracy: Double? = nil) -> RunningPoint {
    RunningPoint(latitude: latitude, longitude: 121, horizontalAccuracy: 5,
                 timestamp: metricsOrigin.addingTimeInterval(seconds), altitude: altitude, verticalAccuracy: accuracy)
}

@Test func metricsLegacyJSONDoesNotInventWeightAltitudeOrIndoorSamples() throws {
    var session = RunningSession(startedAt: metricsOrigin)
    session.segments = [[metricGPS(0)]]
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
    for key in ["indoorSegments", "weightKilograms", "energyAlgorithmVersion"] { object.removeValue(forKey: key) }
    let decoded = try JSONDecoder().decode(RunningSession.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.indoorSegments.isEmpty)
    #expect(decoded.weightKilograms == nil)
    #expect(decoded.energyAlgorithmVersion == nil)
    #expect(decoded.segments.first?.first?.altitude == nil)
    let metrics = RunningMetrics(session: decoded)
    #expect(metrics.speedSeries.isEmpty)
    #expect(metrics.cadenceSeries.isEmpty)
    #expect(metrics.altitudeSeries.isEmpty)
    #expect(metrics.maximumSpeedKilometersPerHour == nil)
    #expect(metrics.ascentMeters == nil)
    #expect(metrics.estimatedEnergyKilocalories == nil)
}

@Test func tailSplitNeverWinsBestCompleteKilometerAndUsesRemainingActiveTime() {
    var session = RunningSession(startedAt: metricsOrigin)
    session.distanceMeters = 2_500
    session.splits = [RunningSplit(kilometer: 1, elapsedSeconds: 600), RunningSplit(kilometer: 2, elapsedSeconds: 180)]
    session.finish(at: metricsOrigin.addingTimeInterval(800))
    let metrics = RunningMetrics(session: session)
    #expect(metrics.splits.count == 3)
    #expect(metrics.splits.last?.distanceMeters == 500)
    #expect(metrics.splits.last?.elapsedSeconds == 20)
    #expect(metrics.splits.last?.isComplete == false)
    #expect(metrics.splits.last?.paceSecondsPerKilometer == 40)
    #expect(metrics.bestKilometer?.kilometer == 2)
    #expect(metrics.bestKilometer?.elapsedSeconds == 180)
    session.distanceMeters = 500
    session.splits = []
    #expect(RunningMetrics(session: session).bestKilometer == nil)
}

@Test func indoorMetricsUseRecordedCumulativeSamplesAndKeepPauseSegmentsSeparate() {
    var session = RunningSession(startedAt: metricsOrigin, kind: .indoor)
    session.weightKilograms = 60
    session.energyAlgorithmVersion = RunningMetrics.energyAlgorithmVersion
    session.appendIndoor(distance: 600, steps: 800, from: metricsOrigin,
                         to: metricsOrigin.addingTimeInterval(200), now: metricsOrigin.addingTimeInterval(200))
    session.pause(at: metricsOrigin.addingTimeInterval(200))
    session.resume(at: metricsOrigin.addingTimeInterval(500))
    session.appendIndoor(distance: 200, steps: 300, from: metricsOrigin.addingTimeInterval(500),
                         to: metricsOrigin.addingTimeInterval(600), now: metricsOrigin.addingTimeInterval(600))
    session.finish(at: metricsOrigin.addingTimeInterval(600))
    let metrics = RunningMetrics(session: session)
    #expect(session.indoorSegments.map(\.count) == [2, 2])
    #expect(session.indoorSegments[1][0].distanceMeters == 600)
    #expect(session.indoorSegments[1][0].steps == 800)
    #expect(session.indoorSegments[1][0].elapsedSeconds == 200)
    #expect(metrics.speedSeries.count == 2)
    #expect(metrics.speedSeries[0].segmentIndex != metrics.speedSeries[1].segmentIndex)
    #expect(metrics.speedSeries[1].timeOffsetSeconds == 600)
    #expect(metrics.elapsedSeconds == 300)
    #expect(metrics.maximumCadenceStepsPerMinute == 240)
    #expect(metrics.cadenceSeries[1].value == 180)
    #expect(abs((metrics.maximumSpeedKilometersPerHour ?? 0) - 10.8) < 0.0001)
    #expect(metrics.estimatedEnergyKilocalories != nil)
    #expect(metrics.altitudeSeries.isEmpty)
}

@Test func indoorRecordingRejectsOverlappingSamplesWithoutDuplicatingMetrics() {
    var session = RunningSession(startedAt: metricsOrigin, kind: .indoor)
    let first = session.appendIndoor(distance: 30, steps: 45, from: metricsOrigin,
                                     to: metricsOrigin.addingTimeInterval(10), now: metricsOrigin.addingTimeInterval(10))
    let repeated = session.appendIndoor(distance: 30, steps: 45, from: metricsOrigin,
                                        to: metricsOrigin.addingTimeInterval(10), now: metricsOrigin.addingTimeInterval(10))
    #expect(first)
    #expect(!repeated)
    #expect(session.indoorSegments.first?.count == 2)
    #expect(session.steps == 45)
    #expect(RunningMetrics(session: session).speedSeries.count == 1)
}

@Test func gpsMetricsNeverCalculateSpeedOrEnergyAcrossPausedSegments() throws {
    var session = RunningSession(startedAt: metricsOrigin, kind: .cycling)
    session.weightKilograms = 70
    session.energyAlgorithmVersion = RunningMetrics.energyAlgorithmVersion
    session.segments = [
        [metricGPS(0), metricGPS(10, latitude: 31.0005)],
        [metricGPS(1_000, latitude: 40), metricGPS(1_010, latitude: 40.0005)]
    ]
    session.updatedAt = metricsOrigin.addingTimeInterval(1_010)
    let metrics = RunningMetrics(session: session)
    #expect(metrics.speedSeries.count == 2)
    #expect(metrics.speedSeries[0].segmentIndex != metrics.speedSeries[1].segmentIndex)
    #expect((metrics.maximumSpeedKilometersPerHour ?? 0) < 21)
    let energy = try #require(metrics.estimatedEnergyKilocalories)
    #expect(energy < 10)
    #expect(metrics.cadenceSeries.isEmpty)
}

@Test func altitudeMetricsFilterUncertainSamplesAndNeverBridgeMissingDataOrPauses() {
    var session = RunningSession(startedAt: metricsOrigin)
    session.segments = [[
        metricGPS(0, altitude: 100, accuracy: 2),
        metricGPS(5, altitude: 101, accuracy: 2),
        metricGPS(10, altitude: 103, accuracy: 2),
        metricGPS(15, altitude: 500, accuracy: 100),
        metricGPS(20, altitude: 200, accuracy: 2),
        metricGPS(25, altitude: 205, accuracy: 2)
    ], [metricGPS(100, altitude: 1_000, accuracy: 2), metricGPS(110, altitude: 1_000, accuracy: 2)]]
    session.updatedAt = metricsOrigin.addingTimeInterval(110)
    let metrics = RunningMetrics(session: session)
    #expect(metrics.altitudeSeries.count == 7)
    #expect(metrics.minimumAltitudeMeters == 100)
    #expect(metrics.maximumAltitudeMeters == 1_000)
    #expect(metrics.ascentMeters == 8)
    #expect(metrics.altitudeSeries[2].segmentIndex != metrics.altitudeSeries[3].segmentIndex)
    #expect(metrics.altitudeSeries[4].segmentIndex != metrics.altitudeSeries[5].segmentIndex)
    session.segments = [[metricGPS(0, altitude: 100, accuracy: -1)], [metricGPS(20, altitude: 200, accuracy: 5)]]
    #expect(RunningMetrics(session: session).ascentMeters == nil)
}

@Test func historicalEnergyRequiresCapturedWeightVersionAndMeasurements() {
    var session = RunningSession(startedAt: metricsOrigin, kind: .indoor)
    session.appendIndoor(distance: 2_235, steps: 3_000, from: metricsOrigin,
                         to: metricsOrigin.addingTimeInterval(1_000), now: metricsOrigin.addingTimeInterval(1_000))
    session.finish(at: metricsOrigin.addingTimeInterval(1_000))
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories == nil)
    session.weightKilograms = 60
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories == nil)
    session.energyAlgorithmVersion = 1
    #expect(abs((RunningMetrics(session: session).estimatedEnergyKilocalories ?? 0) - 133.333333) < 0.001)
    #expect(RunningMetrics(session: session).roundedEnergyKilocalories == 133)
    session.energyAlgorithmVersion = 99
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories == nil)
    session.energyAlgorithmVersion = 1
    session.indoorSegments = []
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories == nil)
}

@Test func energyTablesInterpolateAndClampEndpointsInsteadOfDroppingFastRunningCalories() throws {
    let running = try #require(RunningEnergy.estimateKilocalories(kind: .outdoor, weightKilograms: 60, elapsedSeconds: 3_600, distanceMeters: 2.235 * 3_600))
    let maximum = try #require(RunningEnergy.estimateKilocalories(kind: .indoor, weightKilograms: 60, elapsedSeconds: 3_600, distanceMeters: 4.876 * 3_600))
    let aboveMaximum = try #require(RunningEnergy.estimateKilocalories(kind: .outdoor, weightKilograms: 60, elapsedSeconds: 3_600, distanceMeters: 10 * 3_600))
    #expect(abs(running - 480) < 0.001)
    #expect(abs(maximum - 1_080) < 0.001)
    #expect(abs(aboveMaximum - 1_080) < 0.001)
    let interpolated = try #require(RunningEnergy.estimateKilocalories(kind: .cycling, weightKilograms: 60, elapsedSeconds: 3_600, distanceMeters: 4.95 * 3_600))
    #expect(abs(interpolated - 420) < 0.001)
    #expect(RunningEnergy.estimateKilocalories(kind: .cycling, weightKilograms: 60, elapsedSeconds: 3_600, distanceMeters: 12 * 3_600) == 960)
    #expect(RunningEnergy.estimateKilocalories(kind: .cycling, weightKilograms: 60, elapsedSeconds: 60, distanceMeters: 0) == 0)
    #expect(RunningEnergy.estimateKilocalories(kind: .outdoor, weightKilograms: .nan, elapsedSeconds: 60, distanceMeters: 100) == nil)
    #expect(RunningMetrics.roundedEnergy(123.6) == 124)
    #expect(RunningMetrics.roundedEnergy(.infinity) == nil)
}

@Test func futureIndoorSampleIsRejectedBeforePauseResumeCanCreateReversedSegments() {
    var session = RunningSession(startedAt: metricsOrigin, kind: .indoor)
    let futureAccepted = session.appendIndoor(distance: 30, steps: 45, from: metricsOrigin,
                                              to: metricsOrigin.addingTimeInterval(11), now: metricsOrigin.addingTimeInterval(10))
    #expect(!futureAccepted)
    #expect(session.indoorSegments.isEmpty)
    let firstAccepted = session.appendIndoor(distance: 30, steps: 45, from: metricsOrigin,
                                             to: metricsOrigin.addingTimeInterval(10), now: metricsOrigin.addingTimeInterval(10))
    #expect(firstAccepted)
    session.pause(at: metricsOrigin.addingTimeInterval(10))
    session.resume(at: metricsOrigin.addingTimeInterval(10))
    let resumedAccepted = session.appendIndoor(distance: 3, steps: 4, from: metricsOrigin.addingTimeInterval(10),
                                               to: metricsOrigin.addingTimeInterval(11), now: metricsOrigin.addingTimeInterval(11))
    #expect(resumedAccepted)
    #expect(session.indoorSegments.count == 2)
    let previous = session.indoorSegments[0].last!
    let next = session.indoorSegments[1].first!
    #expect(next.timestamp >= previous.timestamp)
    #expect(next.elapsedSeconds >= previous.elapsedSeconds)
    #expect(session.distanceMeters == 33)
    #expect(session.steps == 49)
}
