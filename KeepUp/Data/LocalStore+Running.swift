import Foundation
import WCDBSwift

extension LocalStore {
    func runningSession(id: String) throws -> RunningSession? {
        guard let database else { throw StoreError.notOpen }
        guard let row = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.id == id, limit: 1).first,
              row.phase != "deleted" else { return nil }
        return try StoredJSON.decode(RunningSession.self, from: row.payload)
    }

    func saveRunningSession(_ session: RunningSession) throws {
        guard let database else { throw StoreError.notOpen }
        try validateRunning(session)
        guard session.phase != .finished else { throw StoreError.invalidContent }
        let existing = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.id == session.id, limit: 1).first
        if let existing {
            // A delayed checkpoint must never resurrect a discarded or finished workout.
            guard existing.phase != "deleted", existing.phase != RunningPhase.finished.rawValue else { return }
            guard session.revision > existing.revision else { return }
            try validateRecordedParameters(session, against: StoredJSON.decode(RunningSession.self, from: existing.payload))
        }
        let other = try database.table(StoreTables.running).getObjects(where:
            RunningRow.Properties.id != session.id &&
            (RunningRow.Properties.phase == RunningPhase.running.rawValue || RunningRow.Properties.phase == RunningPhase.paused.rawValue), limit: 1)
        guard other.isEmpty else { throw StoreError.invalidContent }
        try database.insertOrReplace(RunningRow(session), intoTable: StoreTables.running.name)
    }

    func finishRunning(_ session: RunningSession) throws {
        guard let database else { throw StoreError.notOpen }
        try validateRunning(session)
        guard session.phase == .finished, session.distanceMeters >= session.kind.minimumDistanceMeters else { throw StoreError.invalidQuantity }
        let previous = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.id == session.id, limit: 1).first
        if let previous {
            guard previous.phase != "deleted" else { throw StoreError.invalidContent }
            if previous.phase == RunningPhase.finished.rawValue { return }
            guard session.revision > previous.revision else { throw StoreError.invalidContent }
            try validateRecordedParameters(session, against: StoredJSON.decode(RunningSession.self, from: previous.payload))
        }
        let occupied = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.id == session.id, limit: 1)
        guard occupied.isEmpty else { throw StoreError.invalidCard }
        let scheduleID = session.kind.cardID + ":" + session.day.rawValue
        let plan = try database.table(StoreTables.schedules).getObjects(where: ScheduleRow.Properties.id == scheduleID, limit: 1).first
        let entry = CheckInEntry(id: session.id, cardID: session.kind.cardID, day: session.day,
                                 timeZoneID: session.timeZoneID, createdAt: session.startedAt,
                                 quantity: session.distanceMeters / 1_000, unit: .kilometers, note: plan?.note ?? "",
                                 runningKind: session.kind, runningKilocalories: RunningMetrics(session: session).estimatedEnergyKilocalories,
                                 runningElapsedSeconds: session.elapsedSeconds)
        try database.run(transaction: { handle in
            try handle.insertOrReplace(RunningRow(session), intoTable: StoreTables.running.name)
            try handle.insert(EntryRow(entry), intoTable: StoreTables.entries.name)
            try handle.delete(fromTable: StoreTables.schedules.name, where: ScheduleRow.Properties.id == scheduleID)
        })
    }

    func discardRunning(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        guard !id.isEmpty else { throw StoreError.invalidContent }
        var row = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.id == id, limit: 1).first ?? RunningRow(discardedID: id)
        guard row.phase != RunningPhase.finished.rawValue else { throw StoreError.invalidContent }
        row.phase = "deleted"
        row.payload = Data()
        try database.insertOrReplace(row, intoTable: StoreTables.running.name)
    }

    private func validateRecordedParameters(_ session: RunningSession, against old: RunningSession) throws {
        guard session.kind == old.kind, session.weightKilograms == old.weightKilograms,
              session.energyAlgorithmVersion == old.energyAlgorithmVersion else { throw StoreError.invalidContent }
    }

    private func validateRunning(_ session: RunningSession) throws {
        guard !session.id.isEmpty, session.revision >= 0,
              let zone = TimeZone(identifier: session.timeZoneID),
              session.startedAt.timeIntervalSince1970.isFinite,
              session.updatedAt.timeIntervalSince1970.isFinite, session.updatedAt >= session.startedAt,
              session.day == LocalDay(date: session.startedAt, timeZone: zone),
              session.activeSince.map({ $0.timeIntervalSince1970.isFinite && $0 >= session.startedAt && $0 <= session.updatedAt }) ?? true,
              session.finishedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= session.startedAt && $0 <= session.updatedAt }) ?? true else { throw StoreError.invalidDate }
        guard session.steps >= 0, session.steps <= 10_000_000,
              session.kind.usesGPS ? (session.steps == 0 && session.indoorSegments.allSatisfy(\.isEmpty)) : session.segments.allSatisfy(\.isEmpty) else { throw StoreError.invalidContent }
        guard session.weightKilograms.map({ $0.isFinite && (5...200).contains($0) }) ?? true,
              (session.weightKilograms == nil && session.energyAlgorithmVersion == nil)
                || (session.weightKilograms != nil && session.energyAlgorithmVersion == RunningMetrics.energyAlgorithmVersion) else { throw StoreError.invalidContent }
        guard session.distanceMeters.isFinite, (0...1_000_000).contains(session.distanceMeters),
              session.elapsedSeconds.isFinite, (0...604_800).contains(session.elapsedSeconds),
              session.phase == .running ? session.activeSince != nil : session.activeSince == nil,
              session.phase == .finished ? session.finishedAt != nil : session.finishedAt == nil else { throw StoreError.invalidContent }
        guard session.splits.count == Int(session.distanceMeters / 1_000),
              session.splits.enumerated().allSatisfy({ index, split in
                  split.kilometer == index + 1 && split.elapsedSeconds.isFinite && split.elapsedSeconds >= 0
              }),
              session.splits.reduce(0, { $0 + $1.elapsedSeconds }) <= session.elapsed(at: session.updatedAt) + 2 else { throw StoreError.invalidContent }
        var lastTime: Date?
        for segment in session.segments {
            for point in segment {
                guard point.latitude.isFinite, (-90...90).contains(point.latitude),
                      point.longitude.isFinite, (-180...180).contains(point.longitude),
                      point.horizontalAccuracy.isFinite, (0...50).contains(point.horizontalAccuracy), point.speed.isFinite,
                      point.altitude.map(\.isFinite) ?? true,
                      point.verticalAccuracy.map({ $0.isFinite && $0 >= 0 }) ?? true,
                      point.timestamp.timeIntervalSince1970.isFinite,
                      point.timestamp >= session.startedAt, point.timestamp <= session.updatedAt.addingTimeInterval(2),
                      lastTime.map({ point.timestamp > $0 }) ?? true else { throw StoreError.invalidContent }
                lastTime = point.timestamp
            }
        }
        var lastSample: RunningIndoorSample?
        for segment in session.indoorSegments {
            var previous: RunningIndoorSample?
            for sample in segment {
                guard sample.timestamp.timeIntervalSince1970.isFinite,
                      sample.timestamp >= session.startedAt, sample.timestamp <= session.updatedAt.addingTimeInterval(2),
                      sample.elapsedSeconds.isFinite, sample.elapsedSeconds >= 0,
                      sample.elapsedSeconds <= session.elapsed(at: session.updatedAt) + 2,
                      sample.distanceMeters.isFinite, (0...session.distanceMeters).contains(sample.distanceMeters),
                      (0...session.steps).contains(sample.steps),
                      lastSample.map({ sample.timestamp >= $0.timestamp && sample.elapsedSeconds >= $0.elapsedSeconds
                          && sample.distanceMeters >= $0.distanceMeters && sample.steps >= $0.steps }) ?? true,
                      previous.map({ sample.timestamp > $0.timestamp && sample.elapsedSeconds > $0.elapsedSeconds }) ?? true else { throw StoreError.invalidContent }
                previous = sample
                lastSample = sample
            }
        }
    }
}
