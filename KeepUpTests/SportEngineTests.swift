import Foundation
import Testing
@testable import KeepUp

private let sportOrigin = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor private final class SportTestGPS: RunningLocationSource {
    var authorization: RunningAuthorization = .authorized
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    var starts = 0
    var permissionRequests = 0
    func requestPermission() { permissionRequests += 1 }
    func start(background: Bool) { starts += 1 }
    func stop() {}
}

@MainActor private final class SportTestMotion: RunningMotionSource {
    var authorization: RunningAuthorization = .authorized
    var onEvent: (@MainActor (RunningMotionEvent) -> Void)?
    var starts: [Date] = []
    var stops = 0
    var permissionRequests = 0
    func requestPermission() { permissionRequests += 1 }
    func start(from date: Date) { starts.append(date) }
    func stop() { stops += 1 }
    func send(start: Double, end: Double, distance: Double, steps: Int) {
        onEvent?(.reading(RunningMotionReading(startedAt: sportOrigin.addingTimeInterval(start),
                                              measuredAt: sportOrigin.addingTimeInterval(end), distanceMeters: distance, steps: steps)))
    }
}

@Test func sportKindsKeepSeparateCardsThresholdsAndSpeedUnits() {
    #expect(RunningKind.outdoor.cardID == "punchcard.2")
    #expect(RunningKind.indoor.cardID == "punchcard.2")
    #expect(RunningKind.cycling.cardID == "punchcard.96")
    #expect(!RunningKind.indoor.usesGPS)
    #expect(RunningKind.cycling.minimumDistanceMeters == 500)
    #expect(RunningKind.indoor.minimumDistanceMeters == 100)
    var cycling = RunningSession(startedAt: sportOrigin, kind: .cycling)
    cycling.distanceMeters = 1_000
    #expect(cycling.averageSpeedKilometersPerHour(at: sportOrigin.addingTimeInterval(200)) == 18)
}

@Test func cyclingAcceptsCyclingSpeedThatOutdoorRunningRejects() {
    var outdoor = RunningSession(startedAt: sportOrigin)
    var cycling = RunningSession(startedAt: sportOrigin, kind: .cycling)
    let first = RunningPoint(latitude: 31, longitude: 121, horizontalAccuracy: 5, timestamp: sportOrigin)
    let second = RunningPoint(latitude: 31.0003, longitude: 121, horizontalAccuracy: 5,
                              timestamp: sportOrigin.addingTimeInterval(1), speed: 33)
    outdoor.append(first, now: first.timestamp)
    cycling.append(first, now: first.timestamp)
    let outdoorAccepted = outdoor.append(second, now: second.timestamp)
    let cyclingAccepted = cycling.append(second, now: second.timestamp)
    #expect(!outdoorAccepted)
    #expect(cyclingAccepted)
    #expect(cycling.distanceMeters > 30)
    var invalidSpeed = second
    invalidSpeed.speed = .nan
    #expect(!invalidSpeed.isUsable(at: second.timestamp))
}

@Test func indoorDistanceInterpolatesSplitsAndNeverCreatesGPSRoute() {
    var session = RunningSession(startedAt: sportOrigin, kind: .indoor)
    let accepted = session.appendIndoor(distance: 1_200, steps: 1_500, from: sportOrigin,
                                       to: sportOrigin.addingTimeInterval(400), now: sportOrigin.addingTimeInterval(400))
    #expect(accepted)
    #expect(session.splits.count == 1)
    #expect(abs(session.splits[0].elapsedSeconds - 333.3333) < 0.001)
    session.pause(at: sportOrigin.addingTimeInterval(400))
    session.resume(at: sportOrigin.addingTimeInterval(1_000))
    let resumed = session.appendIndoor(distance: 300, steps: 450, from: sportOrigin.addingTimeInterval(1_000),
                                      to: sportOrigin.addingTimeInterval(1_100), now: sportOrigin.addingTimeInterval(1_100))
    #expect(resumed)
    #expect(session.elapsed(at: sportOrigin.addingTimeInterval(1_100)) == 500)
    #expect(session.steps == 1_950)
    #expect(session.distanceMeters == 1_500)
    #expect(session.segments.isEmpty)
    let gps = RunningPoint(latitude: 31, longitude: 121, horizontalAccuracy: 5, timestamp: sportOrigin.addingTimeInterval(1_101))
    let gpsAccepted = session.append(gps, now: gps.timestamp)
    #expect(!gpsAccepted)
}

@Test @MainActor func indoorCumulativeCallbacksIgnoreDuplicatesRegressionsAndPausedEpoch() async {
    let gps = SportTestGPS()
    gps.authorization = .denied
    let motion = SportTestMotion()
    var date = sportOrigin
    let controller = RunningController(source: gps, motionSource: motion, now: { date })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    controller.selectKind(.indoor)
    controller.prepare()
    #expect(controller.motionReady)
    #expect(gps.starts == 0)
    await controller.start()
    #expect(controller.session?.kind == .indoor)
    controller.selectKind(.cycling)
    #expect(controller.selectedKind == .indoor)
    date = sportOrigin.addingTimeInterval(10)
    motion.send(start: 0, end: 10, distance: 30, steps: 45)
    motion.send(start: 0, end: 10, distance: 30, steps: 45)
    motion.send(start: 0, end: 9, distance: 35, steps: 50)
    date = sportOrigin.addingTimeInterval(11)
    motion.send(start: 0, end: 11, distance: 20, steps: 30)
    motion.send(start: 0, end: 11, distance: 10_000, steps: 45)
    #expect(controller.session?.distanceMeters == 30)
    #expect(controller.session?.steps == 45)
    date = sportOrigin.addingTimeInterval(20)
    await controller.pause()
    motion.send(start: 0, end: 20, distance: 60, steps: 90)
    date = sportOrigin.addingTimeInterval(100)
    await controller.resume()
    date = sportOrigin.addingTimeInterval(110)
    motion.send(start: 0, end: 110, distance: 500, steps: 700)
    motion.send(start: 100, end: 110, distance: 40, steps: 60)
    #expect(controller.session?.distanceMeters == 70)
    #expect(controller.session?.steps == 105)
    #expect(controller.session?.elapsed(at: date) == 30)
    #expect(controller.session?.segments.isEmpty == true)
    #expect(gps.starts == 0)
    #expect(motion.starts == [sportOrigin, sportOrigin.addingTimeInterval(100)])
    await controller.discard()
}

@Test @MainActor func indoorUnavailableOrDeniedNeverStartsGPSOrMotion() async {
    let gps = SportTestGPS()
    let motion = SportTestMotion()
    motion.authorization = .notDetermined
    let controller = RunningController(source: gps, motionSource: motion)
    controller.selectKind(.indoor)
    controller.requestPermission()
    #expect(motion.permissionRequests == 1)
    #expect(gps.permissionRequests == 0)
    motion.authorization = .denied
    await controller.start()
    #expect(controller.session == nil)
    #expect(controller.errorKey == "running.motionPermissionRequired")
    motion.authorization = .unavailable
    controller.prepare()
    await controller.start()
    #expect(!controller.motionReady)
    #expect(controller.authorization == .unavailable)
    #expect(motion.starts.isEmpty)
    #expect(gps.starts == 0)
}

@Test @MainActor func indoorPermissionRevokedInSettingsPausesOnPrepareWithoutSensorCallback() async {
    let motion = SportTestMotion()
    var date = sportOrigin
    let controller = RunningController(source: SportTestGPS(), motionSource: motion, now: { date })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    controller.selectKind(.indoor)
    await controller.start()
    date = sportOrigin.addingTimeInterval(15)
    motion.authorization = .denied
    controller.prepare()
    #expect(controller.session?.phase == .paused)
    #expect(controller.session?.elapsedSeconds == 15)
    #expect(controller.errorKey == "running.motionPermissionRequired")
    #expect(!controller.motionReady)
    await controller.discard()
}

@Test @MainActor func indoorRecoveredSessionResumesWithNewSensorBaseline() async {
    var saved = RunningSession(startedAt: sportOrigin, kind: .indoor)
    saved.distanceMeters = 100
    saved.steps = 150
    saved.updatedAt = sportOrigin.addingTimeInterval(15)
    let motion = SportTestMotion()
    var date = sportOrigin.addingTimeInterval(100)
    let controller = RunningController(source: SportTestGPS(), motionSource: motion, now: { date })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    controller.restore(saved)
    #expect(controller.selectedKind == .indoor)
    #expect(controller.session?.phase == .paused)
    await controller.resume()
    date = sportOrigin.addingTimeInterval(110)
    motion.send(start: 100, end: 110, distance: 20, steps: 30)
    #expect(controller.session?.elapsed(at: date) == 25)
    #expect(controller.session?.distanceMeters == 120)
    #expect(controller.session?.steps == 180)
    motion.onEvent?(.failed)
    #expect(controller.errorKey == "running.motionFailed")
    #expect(controller.session?.distanceMeters == 120)
    date = sportOrigin.addingTimeInterval(120)
    motion.send(start: 100, end: 120, distance: 40, steps: 60)
    #expect(controller.session?.distanceMeters == 140)
    #expect(controller.errorKey == nil)
    await controller.finish()
    #expect(controller.lastFinishedSession?.kind == .indoor)
    #expect(controller.lastFinishedSession?.steps == 210)
}

@Test @MainActor func cyclingUsesFiveHundredMeterFinishThreshold() async {
    let controller = RunningController(source: SportTestGPS(), motionSource: SportTestMotion(), now: { sportOrigin.addingTimeInterval(20) })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    var saved = RunningSession(startedAt: sportOrigin, kind: .cycling)
    saved.distanceMeters = 499
    saved.updatedAt = sportOrigin.addingTimeInterval(20)
    controller.restore(saved)
    await controller.finish()
    #expect(controller.errorKey == "running.cyclingTooShort")
    #expect(controller.session != nil)
    await controller.discard()
    saved.distanceMeters = 500
    controller.restore(saved)
    await controller.finish()
    #expect(controller.session == nil)
    #expect(controller.lastFinishedSession?.distanceMeters == 500)
}
