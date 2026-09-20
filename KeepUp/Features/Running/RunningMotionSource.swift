import CoreMotion
import Foundation

struct RunningMotionReading: Sendable, Equatable {
    /// The exact start passed to this subscription, independent of sensor timestamp rounding.
    var startedAt: Date
    var measuredAt: Date
    var distanceMeters: Double
    var steps: Int
}

enum RunningMotionEvent: Sendable {
    case authorization(RunningAuthorization)
    case reading(RunningMotionReading)
    case failed
}

@MainActor protocol RunningMotionSource: AnyObject {
    var authorization: RunningAuthorization { get }
    var onEvent: (@MainActor (RunningMotionEvent) -> Void)? { get set }
    func requestPermission()
    func start(from date: Date)
    func stop()
}

@MainActor enum RunningMotionSources {
    static func make() -> any RunningMotionSource {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), let index = args.firstIndex(of: "-ui-testing-running"),
           args.indices.contains(index + 1), args[index + 1].hasPrefix("motion") {
            return UITestRunningMotionSource(mode: args[index + 1])
        }
        #endif
        return CoreRunningMotionSource()
    }
}

#if DEBUG
@MainActor private final class UITestRunningMotionSource: RunningMotionSource {
    let authorization: RunningAuthorization
    var onEvent: (@MainActor (RunningMotionEvent) -> Void)?
    init(mode: String) {
        authorization = mode == "motion-denied" ? .denied : (mode == "motion-unavailable" ? .unavailable : .authorized)
    }
    func requestPermission() { onEvent?(.authorization(authorization)) }
    func start(from date: Date) {
        guard authorization == .authorized else { return }
        let now = Date.now
        // The explicitly opted-in fixture models 2 m/s, so immediate resume does not fabricate another 120 m.
        let distance = min(120, max(0, now.timeIntervalSince(date)) * 2)
        onEvent?(.reading(RunningMotionReading(startedAt: date, measuredAt: now,
                                              distanceMeters: distance, steps: Int(distance * 1.5))))
    }
    func stop() {}
}
#endif

@MainActor final class CoreRunningMotionSource: RunningMotionSource {
    // Construction and stop() must not touch Core Motion during onboarding.
    private var pedometer: CMPedometer?
    private var permissionPedometer: CMPedometer?
    private let makePedometer: () -> CMPedometer

    init(makePedometer: @escaping () -> CMPedometer = { CMPedometer() }) {
        self.makePedometer = makePedometer
    }
    private var generation = 0
    private var permissionGeneration = 0
    var onEvent: (@MainActor (RunningMotionEvent) -> Void)?

    var authorization: RunningAuthorization {
        guard CMPedometer.isDistanceAvailable() else { return .unavailable }
        switch CMPedometer.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }

    func requestPermission() {
        guard authorization == .notDetermined else { onEvent?(.authorization(authorization)); return }
        permissionGeneration += 1
        let token = permissionGeneration
        let date = Date.now
        let permissionPedometer = self.permissionPedometer ?? makePedometer()
        self.permissionPedometer = permissionPedometer
        permissionPedometer.queryPedometerData(from: date.addingTimeInterval(-1), to: date) { @Sendable [weak self] _, error in
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.permissionGeneration == token else { return }
                self.onEvent?(.authorization(self.authorization))
                if failed, self.authorization == .notDetermined { self.onEvent?(.failed) }
            }
        }
    }

    func start(from date: Date) {
        stop()
        guard authorization == .authorized else { onEvent?(.authorization(authorization)); return }
        let token = generation
        let pedometer = self.pedometer ?? makePedometer()
        self.pedometer = pedometer
        pedometer.startUpdates(from: date) { @Sendable [weak self] data, error in
            let reading: RunningMotionReading?
            if error == nil, let data, let distance = data.distance?.doubleValue {
                reading = RunningMotionReading(startedAt: date, measuredAt: data.endDate,
                                               distanceMeters: distance, steps: data.numberOfSteps.intValue)
            } else { reading = nil }
            // Only scalar, sendable values cross to MainActor. Missing distance is a failed sample, never zero.
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                guard self.authorization == .authorized else { self.onEvent?(.authorization(self.authorization)); return }
                if let reading { self.onEvent?(.reading(reading)) }
                else { self.onEvent?(.failed) }
            }
        }
    }

    func stop() {
        generation += 1
        permissionGeneration += 1
        pedometer?.stopUpdates()
    }
}
