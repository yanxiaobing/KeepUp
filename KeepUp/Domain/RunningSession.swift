import Foundation

enum RunningPhase: String, Codable, Sendable { case running, paused, finished }

/// Raw WGS-84 coordinates from Core Location; display adapters must not rewrite stored points.
struct RunningPoint: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timestamp: Date
    var speed: Double = -1

    func isUsable(at now: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && horizontalAccuracy.isFinite && (0...50).contains(horizontalAccuracy)
            && timestamp.timeIntervalSince1970.isFinite
            && now.timeIntervalSince(timestamp) <= 15 && timestamp.timeIntervalSince(now) <= 2
    }

    func distance(to other: RunningPoint) -> Double {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dlat = lat2 - lat1, dlon = (other.longitude - longitude) * .pi / 180
        let a = pow(sin(dlat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(min(1, max(0, a))), sqrt(max(0, 1 - a)))
    }
}

struct RunningSplit: Codable, Sendable, Equatable, Identifiable {
    var kilometer: Int
    /// Active seconds spent completing this kilometer, including stops before pressing pause.
    var elapsedSeconds: Double
    var id: Int { kilometer }
}

struct RunningSession: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var revision: Int = 0
    var day: LocalDay
    var timeZoneID: String
    var startedAt: Date
    var updatedAt: Date
    var phase: RunningPhase
    var elapsedSeconds: Double
    var activeSince: Date?
    var distanceMeters: Double
    var segments: [[RunningPoint]]
    var splits: [RunningSplit]
    var finishedAt: Date?

    init(id: String = "running." + UUID().uuidString, startedAt: Date = .now, timeZone: TimeZone = .current) {
        self.id = id
        day = LocalDay(date: startedAt, timeZone: timeZone)
        timeZoneID = timeZone.identifier
        self.startedAt = startedAt
        updatedAt = startedAt
        phase = .running
        elapsedSeconds = 0
        activeSince = startedAt
        distanceMeters = 0
        segments = []
        splits = []
        finishedAt = nil
    }

    func elapsed(at date: Date) -> Double {
        elapsedSeconds + (phase == .running ? max(0, date.timeIntervalSince(activeSince ?? date)) : 0)
    }

    mutating func pause(at date: Date) {
        guard phase == .running else { return }
        elapsedSeconds = elapsed(at: date)
        activeSince = nil
        updatedAt = date
        revision += 1
        phase = .paused
    }

    mutating func resume(at date: Date) {
        guard phase == .paused else { return }
        activeSince = date
        updatedAt = date
        revision += 1
        phase = .running
        // An empty segment explicitly breaks the line even when no samples arrived before pause.
        if segments.last?.isEmpty != true { segments.append([]) }
    }

    mutating func finish(at date: Date) {
        guard phase != .finished else { return }
        pause(at: date)
        phase = .finished
        finishedAt = date
        updatedAt = date
        revision += 1
    }

    /// Freeze recovery at the last durable checkpoint; process downtime is never active time.
    mutating func recover() {
        if phase == .running { pause(at: updatedAt) }
    }

    @discardableResult
    mutating func append(_ point: RunningPoint, now: Date) -> Bool {
        guard phase == .running, let activeSince, point.timestamp >= activeSince,
              point.isUsable(at: now) else { return false }
        if let previous = segments.reversed().compactMap(\.last).first,
           point.timestamp <= previous.timestamp { return false }
        if segments.isEmpty { segments.append([]) }
        guard let previous = segments.last?.last else {
            segments[segments.count - 1].append(point)
            updatedAt = now
            revision += 1
            return true
        }
        let interval = point.timestamp.timeIntervalSince(previous.timestamp)
        if interval > 30 {
            segments.append([point])
            updatedAt = now
            revision += 1
            return true
        }
        let distance = previous.distance(to: point)
        guard distance >= 3,
              !(point.speed >= 0 && point.speed < 0.5 && distance < max(5, point.horizontalAccuracy)),
              distance <= 15 * interval + max(10, point.horizontalAccuracy + previous.horizontalAccuracy) else { return false }
        let before = distanceMeters
        distanceMeters += distance
        let previousElapsed = elapsed(at: previous.timestamp)
        let currentElapsed = elapsed(at: point.timestamp)
        while Double(splits.count + 1) * 1_000 <= distanceMeters {
            let kilometer = splits.count + 1
            let fraction = (Double(kilometer) * 1_000 - before) / distance
            let totalAtSplit = previousElapsed + (currentElapsed - previousElapsed) * fraction
            splits.append(RunningSplit(kilometer: kilometer, elapsedSeconds: max(0, totalAtSplit - splits.reduce(0) { $0 + $1.elapsedSeconds })))
        }
        segments[segments.count - 1].append(point)
        updatedAt = now
        revision += 1
        return true
    }
}
