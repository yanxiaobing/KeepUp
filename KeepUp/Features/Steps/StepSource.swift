import CoreMotion
import Foundation

enum StepAccess: Sendable, Equatable { case available, needsPermission, denied, unsupported }
enum StepSourceError: Error { case unavailable, invalidReading }

@MainActor enum StepSources {
    static func make() -> any StepSource {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), let index = arguments.firstIndex(of: "-ui-testing-steps"),
           arguments.indices.contains(index + 1) {
            return UITestStepSource(mode: arguments[index + 1])
        }
        #endif
        return CoreMotionStepSource()
    }
}

#if DEBUG
/// Explicit opt-in fixture, reachable only in debug UI test launches.
@MainActor private final class UITestStepSource: StepSource {
    let mode: String
    init(mode: String) { self.mode = mode }
    var access: StepAccess {
        switch mode {
        case "denied": .denied
        case "unsupported": .unsupported
        default: .available
        }
    }
    func query(day: LocalDay, now: Date, timeZone: TimeZone) async throws -> StepReading {
        if mode == "error" { throw StepSourceError.unavailable }
        guard let interval = StepsDateRange.interval(for: day, now: now, timeZone: timeZone) else { throw StepSourceError.unavailable }
        let count = day == LocalDay(date: now, timeZone: timeZone) ? (mode == "zero" ? 0 : 6_500) : 0
        return StepReading(day: day, timeZoneID: timeZone.identifier, steps: count, distance: Double(count) * 0.65, measuredAt: interval.end)
    }
    func updates(day: LocalDay, timeZone: TimeZone) -> AsyncThrowingStream<StepReading, Error> { AsyncThrowingStream { $0.finish() } }
    func stop() {}
}
#endif

@MainActor
protocol StepSource: AnyObject {
    var access: StepAccess { get }
    func query(day: LocalDay, now: Date, timeZone: TimeZone) async throws -> StepReading
    func updates(day: LocalDay, timeZone: TimeZone) -> AsyncThrowingStream<StepReading, Error>
    func stop()
}

@MainActor
final class CoreMotionStepSource: StepSource {
    private let pedometer = CMPedometer()
    private let queryPedometer = CMPedometer()
    private var continuation: AsyncThrowingStream<StepReading, Error>.Continuation?

    var access: StepAccess {
        guard CMPedometer.isStepCountingAvailable() else { return .unsupported }
        switch CMPedometer.authorizationStatus() {
        case .authorized: return .available
        case .notDetermined: return .needsPermission
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func query(day: LocalDay, now: Date, timeZone: TimeZone) async throws -> StepReading {
        guard let interval = StepsDateRange.interval(for: day, now: now, timeZone: timeZone) else {
            throw StepSourceError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            queryPedometer.queryPedometerData(from: interval.start, to: interval.end) { data, error in
                continuation.resume(with: Self.reading(data, error: error, day: day, timeZoneID: timeZone.identifier))
            }
        }
    }

    func updates(day: LocalDay, timeZone: TimeZone) -> AsyncThrowingStream<StepReading, Error> {
        stop()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day.date(in: timeZone))
        let (stream, continuation) = AsyncThrowingStream<StepReading, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        pedometer.startUpdates(from: start) { data, error in
            switch Self.reading(data, error: error, day: day, timeZoneID: timeZone.identifier) {
            case .success(let reading): continuation.yield(reading)
            case .failure(let error): continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func stop() {
        pedometer.stopUpdates()
        continuation?.finish()
        continuation = nil
    }

    nonisolated private static func reading(_ data: CMPedometerData?, error: Error?, day: LocalDay, timeZoneID: String) -> Result<StepReading, Error> {
        if let error { return .failure(error) }
        guard let data else { return .failure(StepSourceError.unavailable) }
        let result = StepReading(day: day, timeZoneID: timeZoneID, steps: data.numberOfSteps.intValue,
                                 distance: data.distance?.doubleValue, measuredAt: data.endDate)
        guard result.isValid else { return .failure(StepSourceError.invalidReading) }
        return .success(result)
    }
}
