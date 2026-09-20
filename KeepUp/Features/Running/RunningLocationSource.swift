import CoreLocation
import Foundation

enum RunningAuthorization: Sendable, Equatable { case notDetermined, authorized, denied, restricted, unavailable }
enum RunningLocationEvent: Sendable { case authorization(RunningAuthorization), points([RunningPoint]), failed }

@MainActor protocol RunningLocationSource: AnyObject {
    var authorization: RunningAuthorization { get }
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)? { get set }
    func requestPermission()
    func start(background: Bool)
    func stop()
}

@MainActor enum RunningLocationSources {
    static func make() -> any RunningLocationSource {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), let index = args.firstIndex(of: "-ui-testing-running"), args.indices.contains(index + 1) {
            return UITestRunningLocationSource(mode: args[index + 1])
        }
        #endif
        return CoreRunningLocationSource()
    }
}

#if DEBUG
@MainActor private final class UITestRunningLocationSource: RunningLocationSource {
    let authorization: RunningAuthorization
    private let mode: String
    private var emittedRoute = false
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    init(mode: String) { self.mode = mode; authorization = mode == "denied" ? .denied : .authorized }
    func requestPermission() { onEvent?(.authorization(authorization)) }
    func start(background: Bool) {
        guard mode == "route" else { return }
        let now = Date.now
        if background {
            guard !emittedRoute else { return }
            emittedRoute = true
            let points = (0...12).map { index in
                RunningPoint(latitude: 31.23 + Double(index) * 0.0001, longitude: 121.47,
                             horizontalAccuracy: 5, timestamp: now.addingTimeInterval(Double(index) - 12), speed: 11)
            }
            onEvent?(.points(points))
        } else {
            onEvent?(.points([RunningPoint(latitude: 31.23, longitude: 121.47, horizontalAccuracy: 5, timestamp: now)]))
        }
    }
    func stop() { emittedRoute = false }
}
#endif

@MainActor final class CoreRunningLocationSource: NSObject, RunningLocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    var authorization: RunningAuthorization { Self.access(manager.authorizationStatus) }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func start(background: Bool) {
        guard authorization == .authorized else { return }
        // SDK contract: enabling this without the declared background mode is a fatal error.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        manager.allowsBackgroundLocationUpdates = background && modes.contains("location")
        manager.showsBackgroundLocationIndicator = background
        manager.startUpdatingLocation()
    }
    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let access = Self.access(manager.authorizationStatus)
        Task { @MainActor [weak self] in self?.onEvent?(.authorization(access)) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Never transfer CLLocation or CLLocationManager across the actor boundary.
        let points = locations.map { RunningPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                                  horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp, speed: $0.speed) }
        Task { @MainActor [weak self] in self?.onEvent?(.points(points)) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in self?.onEvent?(denied ? .authorization(.denied) : .failed) }
    }
    nonisolated private static func access(_ status: CLAuthorizationStatus) -> RunningAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }
}
