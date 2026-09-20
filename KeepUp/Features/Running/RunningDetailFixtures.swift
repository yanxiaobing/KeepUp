#if DEBUG
import Foundation

/// Explicit UI-test input; never replaces live sensors or the normal application database.
enum RunningDetailFixtures {
    static func make(kind: RunningKind) -> RunningSession {
        let beginning = Date.now.addingTimeInterval(-3_600)
        var session = RunningSession(id: "running.ui-details-" + kind.rawValue, startedAt: beginning, kind: kind)
        session.weightKilograms = 60
        session.energyAlgorithmVersion = RunningMetrics.energyAlgorithmVersion
        var date = beginning
        var latitude = 31.23
        func point(_ index: Int) -> RunningPoint {
            RunningPoint(latitude: latitude, longitude: 121.47, horizontalAccuracy: 3, timestamp: date,
                         speed: 2.5, altitude: 20 + Double(index) * 0.3, verticalAccuracy: 2)
        }
        if kind.usesGPS { session.append(point(0), now: date) }
        for index in 1...170 {
            if index == 81 {
                session.pause(at: date)
                date = date.addingTimeInterval(60)
                session.resume(at: date)
                if kind.usesGPS { session.append(point(index - 1), now: date) }
            }
            let start = date
            date = date.addingTimeInterval(index <= 40 ? 11 : index <= 80 ? 8 : 10)
            if kind == .indoor {
                session.appendIndoor(distance: 25, steps: 30, from: start, to: date, now: date)
            } else {
                latitude += 25 / 6_371_000 * 180 / .pi
                session.append(point(index), now: date)
            }
        }
        session.finish(at: date)
        return session
    }
}
#endif
