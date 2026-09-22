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
    func queryIntraday(day: LocalDay, through: Date, timeZone: TimeZone) async throws -> StepIntraday? {
        let ranges = StepIntraday.ranges(day: day, through: through, timeZone: timeZone)
        return StepIntraday(intervals: ranges.enumerated().map { index, range in
            StepInterval(start: range.start, end: range.end,
                         steps: mode == "partial" && index == 0 ? nil : (mode == "zero" || day != LocalDay(date: through, timeZone: timeZone) ? 0 : (6500 / max(1, ranges.count) + (index < 6500 % max(1, ranges.count) ? 1 : 0))))
        }, measuredThrough: through)
    }
    func stop() {}
}
#endif

@MainActor
protocol StepSource: AnyObject {
    var access: StepAccess { get }
    func query(day: LocalDay, now: Date, timeZone: TimeZone) async throws -> StepReading
    func updates(day: LocalDay, timeZone: TimeZone) -> AsyncThrowingStream<StepReading, Error>
    func stop()
    func queryIntraday(day: LocalDay, through: Date, timeZone: TimeZone) async throws -> StepIntraday?
}

extension StepSource {
    func queryIntraday(day: LocalDay, through: Date, timeZone: TimeZone) async throws -> StepIntraday? { nil }
}

@MainActor
final class CoreMotionStepSource: StepSource {
    // Construction and stop() must not touch Core Motion during onboarding.
    private var pedometer: CMPedometer?
    private var queryPedometer: CMPedometer?
    private var intervalCache: [DateInterval: Int] = [:]
    private let makePedometer: () -> CMPedometer

    init(makePedometer: @escaping () -> CMPedometer = { CMPedometer() }) {
        self.makePedometer = makePedometer
    }
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
        let queryPedometer = self.queryPedometer ?? makePedometer()
        self.queryPedometer = queryPedometer
        // Objective-C does not annotate this handler Sendable; prevent inherited MainActor isolation.
        return try await withCheckedThrowingContinuation { continuation in
            queryPedometer.queryPedometerData(from: interval.start, to: interval.end) { @Sendable data, error in
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
        let pedometer = self.pedometer ?? makePedometer()
        self.pedometer = pedometer
        pedometer.startUpdates(from: start) { @Sendable data, error in
            switch Self.reading(data, error: error, day: day, timeZoneID: timeZone.identifier) {
            case .success(let reading): continuation.yield(reading)
            case .failure(let error): continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func stop() {
        pedometer?.stopUpdates()
        continuation?.finish()
        continuation = nil
    }

    func queryIntraday(day: LocalDay, through: Date, timeZone: TimeZone) async throws -> StepIntraday? {
        let device = makePedometer()
        var samples: [StepInterval] = []
        for range in StepIntraday.ranges(day: day, through: through, timeZone: timeZone) {
            try Task.checkCancellation()
            let count: Int?
            if let cached = intervalCache[range] { count = cached }
            else {
                count = await withCheckedContinuation { continuation in
                    device.queryPedometerData(from: range.start, to: range.end) { @Sendable data, error in
                        let value = data?.numberOfSteps.intValue
                        continuation.resume(returning: error == nil ? value.flatMap { (0...1_000_000).contains($0) ? $0 : nil } : nil)
                    }
                }
                // Recent samples can still be revised by the sensor. Cache only settled bins.
                if let count, range.end < through.addingTimeInterval(-3600) { intervalCache[range] = count }
            }
            samples.append(StepInterval(start: range.start, end: range.end, steps: count))
        }
        try Task.checkCancellation()
        intervalCache = intervalCache.filter { $0.key.end > through.addingTimeInterval(-7 * 86400) }
        return StepIntraday(intervals: samples, measuredThrough: through)
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
