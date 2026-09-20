import Foundation
import Testing
@testable import KeepUp

private let settingsRunStart = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor private final class SettingsTestGPS: RunningLocationSource {
    var authorization: RunningAuthorization = .authorized
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    var listening = false
    func requestPermission() {}
    func start(background: Bool) { listening = true }
    func stop() { listening = false }
    func send(_ seconds: Double, latitude: Double, speed: Double = 3) {
        onEvent?(.points([RunningPoint(latitude: latitude, longitude: 121, horizontalAccuracy: 5,
                                     timestamp: settingsRunStart.addingTimeInterval(seconds), speed: speed)]))
    }
}

@MainActor private final class SettingsTestMotion: RunningMotionSource {
    var authorization: RunningAuthorization = .authorized
    var onEvent: (@MainActor (RunningMotionEvent) -> Void)?
    var starts: [Date] = []
    var listening = false
    func requestPermission() {}
    func start(from date: Date) { starts.append(date); listening = true }
    func stop() { listening = false }
    func send(start: Double, end: Double, distance: Double, steps: Int) {
        onEvent?(.reading(RunningMotionReading(startedAt: settingsRunStart.addingTimeInterval(start),
                                              measuredAt: settingsRunStart.addingTimeInterval(end), distanceMeters: distance, steps: steps)))
    }
}

@MainActor private final class CountdownGate {
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { pending = $0 } }
    func release() { let value = pending; pending = nil; value?.resume() }
}

@MainActor private func waitForCountdown(_ gate: CountdownGate) async {
    for _ in 0..<200 {
        if gate.pending != nil { return }
        await Task.yield()
    }
    #expect(gate.pending != nil)
}

@Test @MainActor func countdownEmitsThreeTwoOneBeforeCreatingExactlyOneWorkout() async {
    var settings = RunningSettings()
    settings.countdown = true
    var date = settingsRunStart
    var counts: [Int] = []
    var starts = 0
    var saves = 0
    let controller = RunningController(source: SettingsTestGPS(), motionSource: SettingsTestMotion(), now: { date },
                                       settings: { settings }, sleep: { _ in date = date.addingTimeInterval(1) })
    controller.onEvent = { event in
        if case .countdown(let number) = event { counts.append(number); #expect(controller.session == nil) }
        if case .started = event { starts += 1 }
    }
    controller.configure(checkpoint: { _ in saves += 1; return true }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    await controller.start()
    #expect(counts == [3, 2, 1])
    #expect(starts == 1)
    #expect(saves == 1)
    #expect(controller.session?.startedAt == settingsRunStart.addingTimeInterval(3))
    #expect(controller.countdownRemaining == nil)
    await controller.discard()
    controller.onEvent = nil
}

@Test @MainActor func cancelledCountdownAndLeavingPreparationNeverWriteDraft() async {
    for leavingPreparation in [false, true] {
        var settings = RunningSettings()
        settings.countdown = true
        let gate = CountdownGate()
        let controller = RunningController(source: SettingsTestGPS(), motionSource: SettingsTestMotion(), settings: { settings },
                                           sleep: { _ in await gate.wait() })
        var saves = 0
        var cancellations = 0
        controller.configure(checkpoint: { _ in saves += 1; return true }, finish: { _ in true }, discard: { _ in true })
        controller.onEvent = { if case .countdownCancelled = $0 { cancellations += 1 } }
        let first = Task { await controller.start() }
        await waitForCountdown(gate)
        await controller.start()
        if leavingPreparation { controller.stopPreparing() } else { controller.cancelCountdown() }
        #expect(controller.countdownRemaining == nil)
        #expect(!controller.isBusy)
        gate.release()
        await first.value
        #expect(controller.session == nil)
        #expect(saves == 0)
        #expect(cancellations == 1)
        settings.countdown = false
        await controller.start()
        #expect(controller.session != nil)
        #expect(saves == 1)
        await controller.discard()
    }
}

@Test @MainActor func automaticGPSPauseKeepsListeningAndResumesWithoutCountingPausedDisplacement() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let gps = SettingsTestGPS()
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    var automaticResumes = 0
    controller.onEvent = { if case .resumed(_, automatic: true) = $0 { automaticResumes += 1 } }
    await controller.start()
    date = settingsRunStart.addingTimeInterval(15)
    await controller.tick()
    #expect(controller.isAutoPaused)
    #expect(controller.session?.phase == .paused)
    #expect(gps.listening)
    #expect(controller.session?.distanceMeters == 0)
    date = settingsRunStart.addingTimeInterval(16)
    gps.send(16, latitude: 31, speed: 0)
    date = settingsRunStart.addingTimeInterval(17)
    gps.send(17, latitude: 31.0001)
    #expect(!controller.isAutoPaused)
    #expect(controller.session?.phase == .running)
    #expect(controller.session?.distanceMeters == 0)
    date = settingsRunStart.addingTimeInterval(18)
    gps.send(18, latitude: 31.0002)
    #expect((controller.session?.distanceMeters ?? 0) > 10)
    #expect((controller.session?.distanceMeters ?? 100) < 12)
    #expect(controller.session?.elapsed(at: date) == 16)
    #expect(automaticResumes == 1)
    date = settingsRunStart.addingTimeInterval(32)
    await controller.tick()
    #expect(!controller.isAutoPaused)
    date = settingsRunStart.addingTimeInterval(33)
    await controller.tick()
    #expect(controller.isAutoPaused)
    await controller.discard()
}

@Test @MainActor func indoorAutomaticResumeRebasesSensorAndExcludesPausedSteps() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let motion = SettingsTestMotion()
    let controller = RunningController(source: SettingsTestGPS(), motionSource: motion, now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    controller.selectKind(.indoor)
    await controller.start()
    date = settingsRunStart.addingTimeInterval(5)
    motion.send(start: 0, end: 5, distance: 10, steps: 15)
    date = settingsRunStart.addingTimeInterval(20)
    await controller.tick()
    #expect(controller.isAutoPaused)
    #expect(motion.listening)
    date = settingsRunStart.addingTimeInterval(21)
    motion.send(start: 0, end: 21, distance: 10, steps: 15)
    #expect(controller.isAutoPaused)
    date = settingsRunStart.addingTimeInterval(22)
    motion.send(start: 0, end: 22, distance: 20, steps: 30)
    #expect(!controller.isAutoPaused)
    #expect(controller.session?.distanceMeters == 10)
    #expect(controller.session?.steps == 15)
    #expect(motion.starts.last == date)
    date = settingsRunStart.addingTimeInterval(27)
    motion.send(start: 0, end: 27, distance: 50, steps: 75)
    motion.send(start: 22, end: 27, distance: 10, steps: 15)
    #expect(controller.session?.distanceMeters == 20)
    #expect(controller.session?.steps == 30)
    #expect(controller.session?.elapsed(at: date) == 25)
    await controller.discard()
}

@Test @MainActor func manualPauseAndDisablingAutoPauseCannotAutomaticallyRestartWorkout() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let gps = SettingsTestGPS()
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    date = settingsRunStart.addingTimeInterval(15)
    await controller.tick()
    await controller.pause()
    #expect(!controller.isAutoPaused)
    #expect(!gps.listening)
    controller.prepare()
    #expect(!gps.listening)
    gps.send(16, latitude: 31)
    gps.send(17, latitude: 31.0001)
    #expect(controller.session?.phase == .paused)
    date = settingsRunStart.addingTimeInterval(20)
    await controller.resume()
    date = settingsRunStart.addingTimeInterval(35)
    await controller.tick()
    #expect(controller.isAutoPaused)
    settings.autoPause = false
    controller.settingsDidChange()
    #expect(!controller.isAutoPaused)
    #expect(!gps.listening)
    #expect(controller.session?.phase == .paused)
    gps.send(36, latitude: 31)
    gps.send(37, latitude: 31.0001)
    #expect(controller.session?.phase == .paused)
    await controller.discard()
}

@Test @MainActor func permissionLossAndProcessRecoveryAlwaysProduceManualPause() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let gps = SettingsTestGPS()
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    date = settingsRunStart.addingTimeInterval(15)
    await controller.tick()
    gps.authorization = .denied
    gps.onEvent?(.authorization(.denied))
    #expect(!controller.isAutoPaused)
    #expect(controller.session?.phase == .paused)
    #expect(!gps.listening)
    await controller.discard()
    gps.authorization = .authorized
    var restored = 0
    controller.onEvent = { if case .restored = $0 { restored += 1 } }
    var saved = RunningSession(startedAt: settingsRunStart)
    saved.updatedAt = settingsRunStart.addingTimeInterval(10)
    controller.restore(saved)
    #expect(restored == 1)
    #expect(!controller.isAutoPaused)
    controller.prepare()
    gps.send(16, latitude: 31)
    gps.send(17, latitude: 31.0001)
    #expect(controller.session?.phase == .paused)
    #expect(controller.session?.elapsedSeconds == 10)
    await controller.discard()
}

@Test @MainActor func workoutEventsReportAppliedDistanceAndOnlyDurableFinish() async {
    var date = settingsRunStart
    let gps = SettingsTestGPS()
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { RunningSettings() })
    var canFinish = false
    var finishes = 0
    var updates: [RunningSession] = []
    controller.configure(checkpoint: { _ in true }, finish: { _ in canFinish }, discard: { _ in true })
    controller.onEvent = {
        if case .updated(let snapshot) = $0 { updates.append(snapshot) }
        if case .finished = $0 { finishes += 1 }
    }
    await controller.start()
    gps.send(0, latitude: 31)
    date = settingsRunStart.addingTimeInterval(20)
    gps.send(20, latitude: 31.0012)
    #expect(updates.count == 1)
    #expect(updates.first?.distanceMeters == controller.session?.distanceMeters)
    await controller.finish()
    #expect(finishes == 0)
    canFinish = true
    await controller.finish()
    #expect(finishes == 1)
    #expect(controller.session == nil)
}

@Test @MainActor func delayedIndoorSampleBeforeAutomaticPauseCannotTriggerResumeLater() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let motion = SettingsTestMotion()
    let controller = RunningController(source: SettingsTestGPS(), motionSource: motion, now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    controller.selectKind(.indoor)
    await controller.start()
    date = settingsRunStart.addingTimeInterval(15)
    await controller.tick()
    motion.send(start: 0, end: 10, distance: 20, steps: 30)
    #expect(controller.isAutoPaused)
    date = settingsRunStart.addingTimeInterval(16)
    motion.send(start: 0, end: 16, distance: 20, steps: 30)
    #expect(controller.isAutoPaused)
    #expect(controller.session?.distanceMeters == 0)
    #expect(controller.session?.steps == 0)
    date = settingsRunStart.addingTimeInterval(17)
    motion.send(start: 0, end: 17, distance: 22, steps: 33)
    #expect(!controller.isAutoPaused)
    #expect(controller.session?.distanceMeters == 0)
    await controller.discard()
}

@Test @MainActor func stationaryGPSJitterDoesNotAutomaticallyResume() async {
    var settings = RunningSettings()
    settings.autoPause = true
    var date = settingsRunStart
    let gps = SettingsTestGPS()
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { settings })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    await controller.start()
    date = settingsRunStart.addingTimeInterval(15)
    await controller.tick()
    date = settingsRunStart.addingTimeInterval(16)
    gps.send(16, latitude: 31, speed: -1)
    date = settingsRunStart.addingTimeInterval(17)
    gps.send(17, latitude: 31.00004, speed: -1)
    date = settingsRunStart.addingTimeInterval(18)
    gps.send(18, latitude: 30.99996, speed: -1)
    #expect(controller.isAutoPaused)
    #expect(controller.session?.distanceMeters == 0)
    await controller.discard()
}

@Test @MainActor func GPSBatchEmitsOneDistanceUpdateWithTheFinalSession() async {
    let gps = SettingsTestGPS()
    var date = settingsRunStart
    let controller = RunningController(source: gps, motionSource: SettingsTestMotion(), now: { date }, settings: { RunningSettings() })
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true })
    var updates: [RunningSession] = []
    controller.onEvent = { if case .updated(let snapshot) = $0 { updates.append(snapshot) } }
    await controller.start()
    date = settingsRunStart.addingTimeInterval(12)
    let points = (0...12).map { index in
        RunningPoint(latitude: 31 + Double(index) * 0.0001, longitude: 121, horizontalAccuracy: 5,
                     timestamp: settingsRunStart.addingTimeInterval(Double(index)), speed: 11)
    }
    gps.onEvent?(.points(points))
    #expect(updates.count == 1)
    #expect(updates.first == controller.session)
    #expect((updates.first?.distanceMeters ?? 0) > 100)
    await controller.discard()
}
