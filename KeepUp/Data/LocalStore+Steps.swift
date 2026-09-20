import Foundation
import WCDBSwift

extension LocalStore {
    func saveSteps(_ reading: StepReading, goal: Int?, now: Date) throws {
        guard let database else { throw StoreError.notOpen }
        guard let zone = TimeZone(identifier: reading.timeZoneID),
              reading.measuredAt.timeIntervalSince1970.isFinite,
              reading.measuredAt <= now,
              reading.day <= LocalDay(date: reading.measuredAt, timeZone: zone) else { throw StoreError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: reading.day.date(in: zone))
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              reading.measuredAt >= start, reading.measuredAt <= end else { throw StoreError.invalidDate }
        guard (0...1_000_000).contains(reading.steps),
              reading.distance.map({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }) ?? true,
              goal.map({ (5_000...30_000).contains($0) && $0 % 1_000 == 0 }) ?? true else { throw StoreError.invalidQuantity }

        let rows = try database.table(StoreTables.stepRecords).getObjects(where: StepRow.Properties.id == reading.day.rawValue, limit: 1)
        let previous = try rows.first.map { try StoredJSON.decode(StepRecord.self, from: $0.payload) }
        // Sensor timestamps, not callback arrival times, determine freshness.
        if let previous, previous.measuredAt > reading.measuredAt { return }
        var record = StepRecord(day: reading.day, timeZoneID: zone.identifier, steps: reading.steps,
                                distance: reading.distance, measuredAt: reading.measuredAt, goal: previous?.goal ?? goal)
        record.checkInDeleted = previous?.checkInDeleted
        if previous == record { return }
        let entryID = "steps." + reading.day.rawValue
        let entries = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.id == entryID, limit: 1)
        if let existing = entries.first {
            guard existing.cardID == "punchcard.1", existing.day == reading.day.rawValue else { throw StoreError.invalidCard }
        }
        let scheduleID = "punchcard.1:" + reading.day.rawValue
        let plans = try database.table(StoreTables.schedules).getObjects(where: ScheduleRow.Properties.id == scheduleID, limit: 1)
        let completed = record.goal.map { reading.steps >= $0 } ?? false
        try database.run(transaction: { handle in
            try handle.insertOrReplace(StepRow(id: reading.day.rawValue, payload: StoredJSON.encode(record)), intoTable: StoreTables.stepRecords.name)
            // Once earned, a check-in survives later sensor corrections. Refresh its displayed total.
            if record.checkInDeleted != true && (completed || !entries.isEmpty) {
                let entry = CheckInEntry(id: entryID, cardID: "punchcard.1", day: reading.day,
                                         timeZoneID: zone.identifier,
                                         createdAt: entries.first.map { Date(timeIntervalSince1970: $0.createdAt) } ?? now,
                                         quantity: Double(reading.steps), unit: .steps,
                                         note: entries.first?.note ?? plans.first?.note ?? "")
                try handle.insertOrReplace(EntryRow(entry), intoTable: StoreTables.entries.name)
                if reading.day == LocalDay(date: now, timeZone: zone) {
                    try handle.delete(fromTable: StoreTables.schedules.name, where: ScheduleRow.Properties.id == scheduleID)
                }
            }
        })
    }
}
