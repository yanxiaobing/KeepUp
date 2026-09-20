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
