import CoreMotion
import Foundation
import Testing
@testable import KeepUp

private let stepsZone = TimeZone(identifier: "America/Los_Angeles")!
private func stepsDay(_ value: String) -> LocalDay { LocalDay(rawValue: value)! }

@Test func stepsHistoryUsesCivilDaysAcrossDaylightSaving() throws {
    let now = stepsDay("2026-03-09").date(in: stepsZone)
    let days = StepsDateRange.recentDays(now: now, timeZone: stepsZone)
    #expect(days.count == 7)
    #expect(days.first == stepsDay("2026-03-09"))
    #expect(days.last == stepsDay("2026-03-03"))
    #expect(StepsDateRange.recentDays(now: now, timeZone: stepsZone, earliestDay: stepsDay("2026-03-07")) ==
            [stepsDay("2026-03-09"), stepsDay("2026-03-08"), stepsDay("2026-03-07")])
    let interval = try #require(StepsDateRange.interval(for: stepsDay("2026-03-08"), now: now, timeZone: stepsZone))
    let expectedDuration: TimeInterval = 23 * 3_600
    #expect(interval.duration == expectedDuration)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = stepsZone
    #expect(calendar.component(.hour, from: interval.start) == 0)
    #expect(calendar.component(.hour, from: interval.end) == 0)
    #expect(LocalDay(date: interval.end, timeZone: stepsZone) == stepsDay("2026-03-09"))
    #expect(StepsDateRange.interval(for: stepsDay("2026-03-02"), now: now, timeZone: stepsZone) == nil)
    #expect(StepsDateRange.interval(for: stepsDay("2026-03-10"), now: now, timeZone: stepsZone) == nil)
}

@Test func stepsGoalFirstAppliesTodayAndEditsApplyTomorrow() {
    let today = stepsDay("2026-03-08")
    let now = today.date(in: stepsZone)
    #expect(StepsGoal.value(on: today, changes: [:]) == nil)
    let initial = StepsGoal.updated([:], value: 5_000, now: now, timeZone: stepsZone)
    let changed = StepsGoal.updated(initial, value: 8_000, now: now, timeZone: stepsZone)
    #expect(StepsGoal.value(on: today, changes: changed) == 5_000)
    #expect(StepsGoal.value(on: stepsDay("2026-03-09"), changes: changed) == 8_000)
    #expect(StepsGoal.value(on: stepsDay("2026-03-07"), changes: changed) == nil)
    #expect(StepsGoal.measurementGoal(on: stepsDay("2026-03-07"), today: today, changes: changed) == 5_000)
    #expect(StepsGoal.updated(changed, value: 5_500, now: now, timeZone: stepsZone) == changed)
}

@Test func invalidStepMeasurementsCannotMasqueradeAsZero() {
    let day = stepsDay("2026-03-08")
    #expect(StepReading(day: day, timeZoneID: stepsZone.identifier, steps: 0, distance: nil, measuredAt: day.date()).isValid)
    #expect(!StepReading(day: day, timeZoneID: stepsZone.identifier, steps: -1, distance: nil, measuredAt: day.date()).isValid)
    #expect(!StepReading(day: day, timeZoneID: stepsZone.identifier, steps: 10, distance: .nan, measuredAt: day.date()).isValid)
}

@MainActor
private final class ControlledStepSource: StepSource {
    var access: StepAccess = .available
    var queryCount = 0
    var intradayQueryCount = 0
    var pending: [CheckedContinuation<StepReading, Error>] = []
    var suspendedQueries = 0
    func query(day: LocalDay, now: Date, timeZone: TimeZone) async throws -> StepReading {
        queryCount += 1
        if queryCount <= suspendedQueries {
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        return StepReading(day: day, timeZoneID: timeZone.identifier, steps: 10, distance: nil,
                           measuredAt: StepsDateRange.interval(for: day, now: now, timeZone: timeZone)!.end)
    }
    func updates(day: LocalDay, timeZone: TimeZone) -> AsyncThrowingStream<StepReading, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func queryIntraday(day: LocalDay, through: Date, timeZone: TimeZone) async throws -> StepIntraday? {
        intradayQueryCount += 1
        return nil
    }
    func stop() {}
}

@MainActor
private func waitForSteps(_ condition: () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition())
}

@Test @MainActor func stepSyncBackfillsOnlySinceProfileCreation() async {
    let now = stepsDay("2026-03-09").date(in: stepsZone)
    let source = ControlledStepSource()
    let controller = StepsController(day: stepsDay("2026-03-09"), source: source, now: now)
    var saved: [LocalDay] = []
    controller.refresh(now: now, timeZone: stepsZone, earliestDay: stepsDay("2026-03-07")) {
        saved.append($0.day)
        return true
    }
    await waitForSteps { saved.count == 3 }
    #expect(saved == [stepsDay("2026-03-09"), stepsDay("2026-03-08"), stepsDay("2026-03-07")])
    #expect(source.queryCount == 3)
    controller.stop()
}

@Test @MainActor func deniedStepsNeverQueryOrPersistZero() async {
    let source = ControlledStepSource()
    source.access = .denied
    let controller = StepsController(day: LocalDay(date: .now), source: source)
    var saved = 0
    controller.refresh { _ in saved += 1; return true }
    #expect(controller.state == .denied)
    #expect(source.queryCount == 0)
    #expect(saved == 0)
    source.access = .needsPermission
    controller.refresh { _ in saved += 1; return true }
    #expect(controller.state == .permission)
    #expect(source.queryCount == 0)
    source.access = .unsupported
    controller.refresh { _ in saved += 1; return true }
    #expect(controller.state == .unsupported)
    #expect(saved == 0)
}

@Test @MainActor func futureSensorTimestampIsRetriedWithoutSaving() async {
    let now = Date.now
    let day = LocalDay(date: now)
    let source = ControlledStepSource()
    source.suspendedQueries = 1
    let controller = StepsController(day: day, source: source)
    var saved: [StepReading] = []
    controller.refresh(now: now) { saved.append($0); return true }
    await waitForSteps { source.pending.count == 1 }
    source.pending[0].resume(returning: StepReading(day: day, timeZoneID: TimeZone.current.identifier,
        steps: 10, distance: nil, measuredAt: now.addingTimeInterval(60)))
    await waitForSteps { source.queryCount == 7 }
    #expect(saved.allSatisfy { $0.day != day })
    #expect(controller.state == .failed)
    controller.stop()
}

@Test @MainActor func oldStepQueryCannotOverwriteNewRefresh() async {
    let now = stepsDay("2026-03-09").date(in: stepsZone)
    let source = ControlledStepSource()
    source.suspendedQueries = 2
    let day = LocalDay(date: now, timeZone: stepsZone)
    let controller = StepsController(day: day, source: source, now: now)
    var saved: [StepReading] = []
    controller.refresh(now: now, timeZone: stepsZone) { saved.append($0); return true }
    await waitForSteps { source.pending.count == 1 }
    controller.refresh(now: now, timeZone: stepsZone) { saved.append($0); return true }
    await waitForSteps { source.pending.count == 2 }
    let recent = StepReading(day: day, timeZoneID: stepsZone.identifier, steps: 300, distance: nil, measuredAt: now)
    source.pending[1].resume(returning: recent)
    await waitForSteps { saved.count == 7 }
    source.pending[0].resume(returning: StepReading(day: day, timeZoneID: stepsZone.identifier, steps: 99, distance: nil, measuredAt: now.addingTimeInterval(-60)))
    await Task.yield()
    #expect(controller.readings[day]?.steps == 300)
    #expect(saved.filter { $0.day == day }.count == 1)
    #expect(controller.state == .ready)
    controller.stop()
}

@Test @MainActor func stepsPersistenceFailureKeepsReadingAndExposesRetryState() async {
    let now = stepsDay("2026-03-09").date(in: stepsZone)
    let source = ControlledStepSource()
    let day = LocalDay(date: now, timeZone: stepsZone)
    let controller = StepsController(day: day, source: source, now: now)
    var saves = 0
    controller.refresh(now: now, timeZone: stepsZone) { _ in saves += 1; return false }
    await waitForSteps { saves == 7 }
    #expect(controller.storageFailed)
    #expect(controller.readings[day]?.steps == 10)
    #expect(controller.state == .ready)
    controller.stop()
}

@Test @MainActor func stepsTodayFollowsMidnightAndDetectsTimeZoneChange() async {
    // Use the device zone because following-today is a presentation choice at initialization.
    let zone = TimeZone.current
    let now = stepsDay("2026-09-20").date(in: zone)
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
    let source = ControlledStepSource()
    let controller = StepsController(day: LocalDay(date: now), source: source, now: now)
    controller.refresh(now: now, timeZone: zone) { _ in true }
    #expect(!controller.needsDateRefresh(now: now, timeZone: zone))
    #expect(controller.needsDateRefresh(now: tomorrow, timeZone: zone))
    controller.refresh(now: tomorrow, timeZone: zone) { _ in true }
    #expect(controller.selectedDay == LocalDay(date: tomorrow, timeZone: zone))
    let otherZone = TimeZone(secondsFromGMT: zone.secondsFromGMT() == 0 ? 3_600 : 0)!
    #expect(controller.needsDateRefresh(now: tomorrow, timeZone: otherZone))
    controller.stop()
}

@Test @MainActor func stepsHistoryOpenedTodayKeepsItsDateAcrossMidnight() async {
    let zone = TimeZone.current
    let day = stepsDay("2026-09-20")
    let now = day.date(in: zone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let source = ControlledStepSource()
    let controller = StepsController(day: day, source: source, now: now, followsToday: false)
    var saves = 0
    controller.refresh(now: now, timeZone: zone) { _ in saves += 1; return true }
    await waitForSteps { saves == 7 }
    #expect(controller.selectedDay == day)
    #expect(controller.needsDateRefresh(now: tomorrow, timeZone: zone))
    controller.refresh(now: tomorrow, timeZone: zone) { _ in saves += 1; return true }
    await waitForSteps { saves == 14 }
    #expect(controller.selectedDay == day)
    #expect(controller.readings[day]?.day == day)
    #expect(!controller.needsDateRefresh(now: tomorrow, timeZone: zone))
    controller.stop()
}

@Test @MainActor func homeStepPermissionWaitsForSavedProfileAndVisibleHome() async {
    let source = ControlledStepSource()
    source.access = .needsPermission
    var created = 0
    let permission = HomeStepPermission { created += 1; return source }
    await permission.requestIfNeeded(profileComplete: false, homeVisible: false)
    await permission.requestIfNeeded(profileComplete: false, homeVisible: true)
    // Saving has completed, but the welcome membership still covers the home screen.
    await permission.requestIfNeeded(profileComplete: true, homeVisible: false)
    #expect(created == 0)
    #expect(source.queryCount == 0)
    await permission.requestIfNeeded(profileComplete: true, homeVisible: true)
    #expect(source.queryCount == 1)
    await permission.requestIfNeeded(profileComplete: true, homeVisible: false)
    await permission.requestIfNeeded(profileComplete: true, homeVisible: true)
    #expect(created == 1)
    #expect(source.queryCount == 1)
}

@Test @MainActor func homeStepPermissionDoesNotQueryWhenAuthorizationIsResolved() async {
    for access in [StepAccess.available, .denied, .unsupported] {
        let source = ControlledStepSource()
        source.access = access
        let permission = HomeStepPermission { source }
        await permission.requestIfNeeded(profileComplete: true, homeVisible: true)
        #expect(source.queryCount == 0)
    }
}

@Test @MainActor func startupAndStopDoNotConstructSystemPedometers() {
    // Exercise the real adapters, not ControlledStepSource: eager CMPedometer
    // construction was invisible to the previous permission-query tests.
    var constructed = 0
    let steps = CoreMotionStepSource(makePedometer: {
        constructed += 1
        return CMPedometer()
    })
    let motion = CoreRunningMotionSource(makePedometer: {
        constructed += 1
        return CMPedometer()
    })
    let monitor = StepsController(day: LocalDay(date: .now), source: steps)
    monitor.stop()
    monitor.stop()
    let running = RunningController(motionSource: motion)
    running.stopPreparing()
    motion.stop()
    #expect(constructed == 0)
}

// Core Motion's Objective-C handler is not annotated Sendable, but the framework
// invokes it on its private queue. Model that contract instead of a main-actor fake.
private struct BackgroundPedometerCallback: @unchecked Sendable {
    let handler: CMPedometerHandler
    func deliver() {
        handler(nil, NSError(domain: "KeepUp.CallbackRegression", code: 1))
    }
}

private final class BackgroundCallbackPedometer: CMPedometer {
    override func queryPedometerData(from start: Date, to end: Date, withHandler handler: @escaping CMPedometerHandler) {
        let callback = BackgroundPedometerCallback(handler: handler)
        DispatchQueue.global().async { callback.deliver() }
    }
    override func startUpdates(from start: Date, withHandler handler: @escaping CMPedometerHandler) {
        let callback = BackgroundPedometerCallback(handler: handler)
        DispatchQueue.global().async { callback.deliver() }
    }
    override func stopUpdates() {}
}

@Test @MainActor func systemPedometerQueryCallbackCanArriveOffMainActor() async {
    let source = CoreMotionStepSource(makePedometer: { BackgroundCallbackPedometer() })
    do {
        _ = try await source.query(day: LocalDay(date: .now), now: .now, timeZone: .current)
        Issue.record("Expected the source error")
    } catch {
        #expect((error as NSError).domain == "KeepUp.CallbackRegression")
    }
}

@Test @MainActor func systemPedometerUpdateCallbackCanArriveOffMainActor() async {
    let source = CoreMotionStepSource(makePedometer: { BackgroundCallbackPedometer() })
    do {
        for try await _ in source.updates(day: LocalDay(date: .now), timeZone: .current) {
            Issue.record("An error must not become a step reading")
        }
        Issue.record("Expected the stream to throw")
    } catch {
        #expect((error as NSError).domain == "KeepUp.CallbackRegression")
    }
    source.stop()
}

@Test func intradayUsesRealBinsAndDistinguishesMissingFromZero() throws {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let day = LocalDay(date: Date(timeIntervalSince1970: 1_789_516_800), timeZone: zone)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let start = calendar.startOfDay(for: day.date(in: zone))
    let through = start.addingTimeInterval(750)
    let ranges = StepIntraday.ranges(day: day, through: through, timeZone: zone)
    #expect(ranges.map(\.duration) == [300, 300, 150])
    let detail = StepIntraday(intervals: zip(ranges, [0, 5, 6]).map {
        StepInterval(start: $0.0.start, end: $0.0.end, steps: $0.1)
    }, measuredThrough: through)
    #expect(detail.isValid(day: day, timeZoneID: zone.identifier))
    #expect(detail.estimatedActiveMinutes == 2)
    #expect(detail.hours(timeZoneID: zone.identifier).first?.steps == 11)
    let missing = StepIntraday(intervals: ranges.map { StepInterval(start: $0.start, end: $0.end, steps: nil) }, measuredThrough: through)
    #expect(missing.estimatedActiveMinutes == nil)
    #expect(missing.hours(timeZoneID: zone.identifier).first?.steps == nil)
    let zero = StepIntraday(intervals: ranges.map { StepInterval(start: $0.start, end: $0.end, steps: 0) }, measuredThrough: through)
    #expect(zero.estimatedActiveMinutes == 0)
    #expect(zero.hours(timeZoneID: zone.identifier).first?.steps == 0)
    #expect(!StepIntraday(intervals: Array(detail.intervals.reversed()), measuredThrough: through).isValid(day: day, timeZoneID: zone.identifier))
}

@Test func intradayRespectsDaylightSavingAndLegacyRecords() throws {
    let zone = TimeZone(identifier: "America/New_York")!
    let decoder = JSONDecoder()
    let old = StepRecord(day: LocalDay(date: .now), timeZoneID: "Asia/Shanghai", steps: 42, distance: nil, measuredAt: .now, goal: nil)
    #expect(try decoder.decode(StepRecord.self, from: JSONEncoder().encode(old)).intraday == nil)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    for (month, date, hours) in [(3, 8, 23), (11, 1, 25)] {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: date)))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let day = LocalDay(date: start, timeZone: zone)
        let ranges = StepIntraday.ranges(day: day, through: end, timeZone: zone)
        #expect(ranges.count == hours * 12)
        let detail = StepIntraday(intervals: ranges.map { StepInterval(start: $0.start, end: $0.end, steps: 10) }, measuredThrough: end)
        #expect(detail.isValid(day: day, timeZoneID: zone.identifier))
        #expect(detail.hours(timeZoneID: zone.identifier).count == hours)
    }
}

@Test @MainActor func intradaySystemCallbacksPreserveUnknownAndCancellation() async throws {
    let source = CoreMotionStepSource(makePedometer: { BackgroundCallbackPedometer() })
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let day = stepsDay("2026-09-22")
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let through = calendar.startOfDay(for: day.date(in: zone)).addingTimeInterval(600)
    let detail = try #require(try await source.queryIntraday(day: day, through: through, timeZone: zone))
    #expect(detail.intervals.count == 2)
    #expect(detail.intervals.allSatisfy { $0.steps == nil })
    #expect(detail.estimatedActiveMinutes == nil)
    let task = Task { try await source.queryIntraday(day: day, through: through, timeZone: zone) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled interval query should throw") }
    catch { #expect(error is CancellationError) }
}

@Test @MainActor func intradayIsOptInAndDoesNotStartAfterPageClosesDuringSave() async {
    let day = stepsDay("2026-09-22")
    let now = day.date(in: stepsZone)
    let source = ControlledStepSource()
    let controller = StepsController(day: day, source: source, now: now)
    controller.refresh(now: now, timeZone: stepsZone) { _ in true }
    await waitForSteps { source.queryCount == 7 }
    #expect(source.intradayQueryCount == 0)
    controller.refresh(includeIntraday: true, now: now, timeZone: stepsZone) { _ in
        controller.stop()
        return true
    }
    await waitForSteps { source.queryCount == 8 }
    await Task.yield()
    #expect(source.intradayQueryCount == 0)
    controller.refresh(includeIntraday: true, now: now, timeZone: stepsZone) { _ in true }
    await waitForSteps { source.intradayQueryCount == 1 }
    #expect(source.intradayQueryCount == 1)
    controller.stop()
}

@Test func savingUnchangedStepGoalDoesNotCreateAnotherEffectiveDate() {
    let now = stepsDay("2026-03-08").date(in: stepsZone)
    let initial = StepsGoal.updated([:], value: 5_000, now: now, timeZone: stepsZone)
    #expect(StepsGoal.updated(initial, value: 5_000, now: now, timeZone: stepsZone) == initial)
    let scheduled = StepsGoal.updated(initial, value: 8_000, now: now, timeZone: stepsZone)
    #expect(StepsGoal.updated(scheduled, value: 8_000, now: now, timeZone: stepsZone) == scheduled)
}
