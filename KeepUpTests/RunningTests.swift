import Foundation
import Testing
@testable import KeepUp

private let runOrigin = Date(timeIntervalSince1970: 1_800_000_000)
private func runPoint(_ seconds: Double, latitude: Double = 31, accuracy: Double = 5, speed: Double = 3) -> RunningPoint {
    RunningPoint(latitude: latitude, longitude: 121, horizontalAccuracy: accuracy,
                 timestamp: runOrigin.addingTimeInterval(seconds), speed: speed)
}

@Test func runningPauseResumeExcludesBreakAndBreaksRoute() throws {
    var session = RunningSession(startedAt: runOrigin)
    let acceptedFirst = session.append(runPoint(0), now: runOrigin)
    #expect(acceptedFirst)
    let acceptedMovement = session.append(runPoint(10, latitude: 31.0003), now: runOrigin.addingTimeInterval(10))
    #expect(acceptedMovement)
    let distance = session.distanceMeters
    session.pause(at: runOrigin.addingTimeInterval(20))
    #expect(session.elapsed(at: runOrigin.addingTimeInterval(90)) == 20)
    session.resume(at: runOrigin.addingTimeInterval(100))
    let acceptedPausedSample = session.append(runPoint(99, latitude: 31.5), now: runOrigin.addingTimeInterval(100))
    #expect(!acceptedPausedSample)
    let acceptedResumedFirst = session.append(runPoint(101, latitude: 32), now: runOrigin.addingTimeInterval(101))
    #expect(acceptedResumedFirst)
    #expect(session.distanceMeters == distance)
    #expect(session.segments.count == 2)
    #expect(session.segments[0].last?.activeElapsedSeconds == 10)
    #expect(session.segments[1].first?.activeElapsedSeconds == 21)
    #expect(session.elapsed(at: runOrigin.addingTimeInterval(105)) == 25)
    let restored = try JSONDecoder().decode(RunningSession.self, from: JSONEncoder().encode(session))
    #expect(restored.segments[1].first?.activeElapsedSeconds == 21)
}

@Test func runningFiltersInvalidStaleAndImpossibleGPS() {
    var session = RunningSession(startedAt: runOrigin)
    let acceptedNaN = session.append(runPoint(0, latitude: .nan), now: runOrigin)
    #expect(!acceptedNaN)
    let acceptedInvalidLatitude = session.append(runPoint(0, latitude: 95), now: runOrigin)
    #expect(!acceptedInvalidLatitude)
    let acceptedInaccurate = session.append(runPoint(0, accuracy: 51), now: runOrigin)
    #expect(!acceptedInaccurate)
    let acceptedNegativeAccuracy = session.append(runPoint(0, accuracy: -1), now: runOrigin)
    #expect(!acceptedNegativeAccuracy)
    let acceptedStale = session.append(runPoint(0), now: runOrigin.addingTimeInterval(16))
    #expect(!acceptedStale)
    let acceptedFuture = session.append(runPoint(3), now: runOrigin)
    #expect(!acceptedFuture)
    let acceptedInitial = session.append(runPoint(0), now: runOrigin)
    #expect(acceptedInitial)
    let acceptedDuplicate = session.append(runPoint(0), now: runOrigin)
    #expect(!acceptedDuplicate)
    let acceptedJump = session.append(runPoint(1, latitude: 31.1), now: runOrigin.addingTimeInterval(1))
    #expect(!acceptedJump)
    let acceptedJitter = session.append(runPoint(2, latitude: 31.00001), now: runOrigin.addingTimeInterval(2))
    #expect(!acceptedJitter)
    let acceptedStationaryDrift = session.append(runPoint(3, latitude: 31.00003, accuracy: 20, speed: 0), now: runOrigin.addingTimeInterval(3))
    #expect(!acceptedStationaryDrift)
    let acceptedUnknownSpeed = session.append(runPoint(10, latitude: 31.0003, speed: -1), now: runOrigin.addingTimeInterval(10))
    #expect(acceptedUnknownSpeed)
    #expect(session.distanceMeters > 30)
}

@Test func runningLongGPSGapStartsANewSegment() {
    var session = RunningSession(startedAt: runOrigin)
    _ = session.append(runPoint(0), now: runOrigin)
    _ = session.append(runPoint(31, latitude: 35), now: runOrigin.addingTimeInterval(31))
    #expect(session.distanceMeters == 0)
    #expect(session.segments.count == 2)
}

@Test func runningKilometerSplitsUseInterpolatedActiveTime() {
    var session = RunningSession(startedAt: runOrigin)
    for index in 0...200 {
        let point = runPoint(Double(index) * 10, latitude: 31 + Double(index) * 0.0001)
        _ = session.append(point, now: point.timestamp)
    }
    #expect(session.splits.count == 2)
    #expect(abs(session.splits[0].elapsedSeconds - 899.32) < 1)
    #expect(abs(session.splits[1].elapsedSeconds - session.splits[0].elapsedSeconds) < 1)
    #expect(session.splits[0].kilometer == 1)
}

@Test func runningRecoveryCapsElapsedAtDurableCheckpoint() throws {
    var saved = RunningSession(startedAt: runOrigin)
    saved.updatedAt = runOrigin.addingTimeInterval(15)
    saved.recover()
    #expect(saved.phase == .paused)
    #expect(saved.elapsed(at: runOrigin.addingTimeInterval(10_000)) == 15)
    #expect(saved.activeSince == nil)
    #expect(saved.revision > 0)
    #expect(try JSONDecoder().decode(RunningSession.self, from: JSONEncoder().encode(saved)) == saved)
}

@MainActor private final class TestRunningSource: RunningLocationSource {
    var authorization: RunningAuthorization = .authorized
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    var started = false
    func requestPermission() {}
    func start(background: Bool) { started = true }
    func stop() { started = false }
}

@Test func preparationGPSMatchesPunchCardAccuracyBoundaries() {
    let cases: [(Double, RunningPreparationGPSQuality)] = [
        (-1, .poor), (0, .poor), (5, .good), (9.99, .good),
        (10, .fair), (50, .fair), (80, .fair), (100, .fair), (100.01, .poor), (.nan, .poor)
    ]
    for (accuracy, expected) in cases {
        #expect(RunningPreparationGPSQuality(point: runPoint(0, accuracy: accuracy), now: runOrigin) == expected)
    }
    #expect(RunningPreparationGPSQuality(point: runPoint(-16), now: runOrigin) == .poor)
    #expect(RunningPreparationGPSQuality(point: runPoint(3), now: runOrigin) == .poor)
}

@Test @MainActor func preparationGPSUpdatesBeforeTrackFilteringAndExpires() async {
    let source = TestRunningSource()
    var date = runOrigin
    let controller = RunningController(source: source, now: { date })
    controller.prepare()
    defer { controller.stopPreparing() }
    #expect(controller.preparationGPSQuality == .waiting)
    source.onEvent?(.points([runPoint(0, accuracy: 80)]))
    #expect(controller.preparationGPSQuality == .fair)
    #expect(controller.locationReady)
    #expect(controller.latestLocationPoint?.horizontalAccuracy == 80)
    date = runOrigin.addingTimeInterval(1)
    source.onEvent?(.points([runPoint(1, accuracy: 150)]))
    #expect(controller.preparationGPSQuality == .poor)
    #expect(!controller.locationReady)
    #expect(controller.latestLocationPoint?.horizontalAccuracy == 80)
    source.onEvent?(.points([runPoint(0, accuracy: 5)]))
    #expect(controller.preparationGPSQuality == .poor)
    date = runOrigin.addingTimeInterval(2)
    source.onEvent?(.points([runPoint(2)]))
    #expect(controller.preparationGPSQuality == .good)
    date = runOrigin.addingTimeInterval(18)
    await controller.tick()
    #expect(controller.preparationGPSQuality == .poor)
    #expect(!controller.locationReady)
    source.onEvent?(.failed)
    await controller.tick()
    #expect(controller.preparationGPSQuality == .poor)
    #expect(!controller.locationReady)
}

@Test @MainActor func runningStartPermissionAndShortFinishDoNotCreateRecord() async {
    let source = TestRunningSource()
    let controller = RunningController(source: source, now: { runOrigin })
    var finished = 0
    controller.configure(checkpoint: { _ in true }, finish: { _ in finished += 1; return true }, discard: { _ in true })
    source.authorization = .denied
    await controller.start()
    #expect(controller.session == nil)
    #expect(!source.started)
    source.authorization = .authorized
    await controller.start()
    await controller.finish()
    #expect(controller.errorKey == "running.tooShort")
    #expect(controller.session?.phase == .running)
    #expect(finished == 0)
    await controller.discard()
}

@Test @MainActor func runningSaveFailureRetriesAndPermissionRevocationPauses() async {
    let source = TestRunningSource()
    var date = runOrigin
    let controller = RunningController(source: source, now: { date })
    var canSave = false
    controller.configure(checkpoint: { _ in canSave }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    #expect(controller.errorKey == "running.saveFailed")
    canSave = true
    date = runOrigin.addingTimeInterval(10)
    await controller.tick()
    #expect(controller.errorKey == nil)
    source.authorization = .denied
    source.onEvent?(.authorization(.denied))
    #expect(controller.session?.phase == .paused)
    #expect(controller.session?.elapsedSeconds == 10)
    #expect(!source.started)
    await controller.discard()
}

@Test @MainActor func runningTerminalWriteWaitsForOlderCheckpointAndCanRetry() async {
    let source = TestRunningSource()
    let controller = RunningController(source: source, now: { runOrigin.addingTimeInterval(20) })
    var checkpointGate: CheckedContinuation<Bool, Never>?
    var order: [String] = []
    var finishWorks = false
    controller.configure(checkpoint: { _ in
        order.append("checkpoint")
        return await withCheckedContinuation { checkpointGate = $0 }
    }, finish: { _ in order.append("finish"); return finishWorks }, discard: { _ in true })
    var saved = RunningSession(startedAt: runOrigin)
    saved.distanceMeters = 120
    saved.updatedAt = runOrigin.addingTimeInterval(10)
    controller.restore(saved)
    for _ in 0..<100 where checkpointGate == nil { await Task.yield() }
    #expect(checkpointGate != nil)
    let finishTask = Task { await controller.finish() }
    for _ in 0..<10 { await Task.yield() }
    #expect(order == ["checkpoint"])
    checkpointGate?.resume(returning: true)
    await finishTask.value
    #expect(order == ["checkpoint", "finish"])
    #expect(controller.session?.phase == .finished)
    #expect(controller.session?.elapsedSeconds == 10)
    #expect(controller.errorKey == "running.saveFailed")
    finishWorks = true
    await controller.finish()
    #expect(controller.session == nil)
    #expect(controller.lastFinishedSession?.distanceMeters == 120)
    #expect(controller.errorKey == nil)
}

@Test @MainActor func runningCheckpointFailureRemainsVisibleWhenGPSAdvances() async {
    let source = TestRunningSource()
    var date = runOrigin
    let controller = RunningController(source: source, now: { date })
    var gate: CheckedContinuation<Bool, Never>?
    var shouldSuspend = false
    controller.configure(checkpoint: { _ in
        if shouldSuspend { return await withCheckedContinuation { gate = $0 } }
        return true
    }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    shouldSuspend = true
    let checkpoint = Task { await controller.tick() }
    for _ in 0..<100 where gate == nil { await Task.yield() }
    #expect(gate != nil)
    date = runOrigin.addingTimeInterval(1)
    source.onEvent?(.points([runPoint(1)]))
    gate?.resume(returning: false)
    await checkpoint.value
    #expect(controller.session?.segments.first?.count == 1)
    #expect(controller.errorKey == "running.saveFailed")
    shouldSuspend = false
    await controller.tick()
    #expect(controller.errorKey == nil)
    await controller.discard()
}
