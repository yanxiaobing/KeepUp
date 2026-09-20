import Foundation
import Observation

enum StepsState: Equatable { case loading, permission, denied, unsupported, failed, unavailable, ready }

@MainActor @Observable
final class StepsController {
    private(set) var state = StepsState.loading
    private(set) var readings: [LocalDay: StepReading] = [:]
    private(set) var selectedDay: LocalDay
    private(set) var storageFailed = false
    private let followsToday: Bool
    private let source: any StepSource
    private var generation = 0
    private var task: Task<Void, Never>?
    private var refreshedDay: LocalDay?
    private var refreshedZone: String?

    init(day: LocalDay, source: any StepSource = StepSources.make(), now: Date = .now, followsToday: Bool? = nil) {
        selectedDay = day
        self.followsToday = followsToday ?? (day == LocalDay(date: now))
        self.source = source
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        source.stop()
    }

    func needsDateRefresh(now: Date = .now, timeZone: TimeZone = .current) -> Bool {
        refreshedDay != LocalDay(date: now, timeZone: timeZone) || refreshedZone != timeZone.identifier
    }

    func refresh(requestPermission: Bool = false, now: Date = .now, timeZone: TimeZone = .current,
                 save: @escaping @MainActor (StepReading) async -> Bool) {
        stop()
        let token = generation
        let today = LocalDay(date: now, timeZone: timeZone)
        refreshedDay = today
        refreshedZone = timeZone.identifier
        if followsToday { selectedDay = today }
        storageFailed = false
        switch source.access {
        case .unsupported: state = .unsupported; return
        case .denied: state = .denied; return
        case .needsPermission where !requestPermission: state = .permission; return
        default: break
        }
        state = .loading
        task = Task { [weak self] in
            guard let self else { return }
            let days = StepsDateRange.recentDays(now: now, timeZone: timeZone)
            let requested = days.contains(selectedDay) ? [selectedDay] + days.filter { $0 != selectedDay } : days
            for day in requested {
                guard generation == token, !Task.isCancelled else { return }
                do {
                    let reading = try await source.query(day: day, now: now, timeZone: timeZone)
                    guard generation == token, !Task.isCancelled else { return }
                    await receive(reading, token: token, save: save)
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    if source.access == .denied { state = .denied; return }
                    if day == selectedDay { state = .failed }
                }
            }
            guard generation == token, !Task.isCancelled else { return }
            if !days.contains(selectedDay) { state = .unavailable }
            guard selectedDay == today else { return }
            do {
                for try await reading in source.updates(day: today, timeZone: timeZone) {
                    guard generation == token, !Task.isCancelled else { return }
                    // An update spanning midnight belongs to an expired query session.
                    guard LocalDay(date: reading.measuredAt, timeZone: timeZone) == today else { continue }
                    await receive(reading, token: token, save: save)
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                state = source.access == .denied ? .denied : .failed
            }
        }
    }

    private func receive(_ reading: StepReading, token: Int, save: @MainActor (StepReading) async -> Bool) async {
        guard reading.isValid, generation == token else { return }
        if let existing = readings[reading.day], existing.timeZoneID == reading.timeZoneID,
           existing.measuredAt > reading.measuredAt { return }
        readings[reading.day] = reading
        if reading.day == selectedDay { state = .ready }
        let saved = await save(reading)
        guard generation == token else { return }
        if !saved { storageFailed = true }
    }
}
