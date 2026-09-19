import Foundation
import WCDBSwift

extension LocalStore {
    func saveWeightTarget(_ target: WeightTarget, now: Date) throws {
        let target = try target.validated(now: now)
        let draft = CheckInDraft(id: "weight.target." + target.id, cardID: "punchcard.50", day: target.start,
                                 timeZoneID: TimeZone.current.identifier, quantity: target.initial, note: "")
        try saveWeight(draft, now: now, targetOverride: target)
    }

    func saveWeight(_ draft: CheckInDraft, now: Date, targetOverride: WeightTarget? = nil, profileOverride: UserProfile? = nil) throws {
        guard let database else { throw StoreError.notOpen }
        guard let zone = TimeZone(identifier: draft.timeZoneID), draft.day <= LocalDay(date: now, timeZone: zone) else { throw StoreError.invalidDate }
        guard let raw = draft.quantity, raw.isFinite, (5...200).contains(raw) else { throw StoreError.invalidQuantity }
        let value = (raw*10).rounded()/10
        let identity: [EntryRow] = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.id == draft.id, limit: 1)
        if let occupied = identity.first {
            guard occupied.cardID == draft.cardID, occupied.day == draft.day.rawValue else { throw StoreError.invalidCard }
        }
        let all: [EntryRow] = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.cardID == "punchcard.50", orderBy: [EntryRow.Properties.createdAt.order(.descending)])
        // Persist the operation ID separately from the stable daily entry ID for idempotent retries.
        let receipts: [WeightOperationRow] = try database.table(StoreTables.weightOperations).getObjects(where: WeightOperationRow.Properties.id == draft.id, limit: 1)
        if !receipts.isEmpty { return }
        let existing = all.first { $0.day == draft.day.rawValue }
        let targets: [WeightRow] = try database.table(StoreTables.weightTarget).getObjects(limit: 1)
        let active = try targetOverride ?? targets.first.map { try StoredJSON.decode(WeightTarget.self, from: $0.payload) }
        let target = active.flatMap { draft.day >= $0.start ? $0 : nil }
        let profiles: [ProfileRow] = try database.table(StoreTables.profile).getObjects(limit: 1)
        var profile = try profileOverride ?? profiles.first.map { try StoredJSON.decode(UserProfile.self, from: $0.payload) }
        let plans: [ScheduleRow] = try database.table(StoreTables.schedules).getObjects(where: ScheduleRow.Properties.id == (draft.cardID + ":" + draft.day.rawValue), limit: 1)
        let entry = CheckInEntry(id: existing?.id ?? draft.id, cardID: draft.cardID, day: draft.day, timeZoneID: existing?.timeZoneID ?? zone.identifier,
                                 createdAt: existing.map { Date(timeIntervalSince1970: $0.createdAt) } ?? now, quantity: value, unit: .kilograms,
                                 note: plans.first?.note ?? existing?.note ?? draft.note)
        let record = WeightRecord(height: profile?.height, target: target)
        // Backfilling an older date must not replace the latest weight shown in personal information.
        if !all.contains(where: { $0.day > draft.day.rawValue }) { profile?.weight = value }
        try database.run(transaction: { handle in
            if let targetOverride { try handle.insertOrReplace(WeightRow(id: "current", payload: StoredJSON.encode(targetOverride)), intoTable: StoreTables.weightTarget.name) }
            try handle.insertOrReplace(EntryRow(entry), intoTable: StoreTables.entries.name)
            try handle.insertOrReplace(WeightRow(id: entry.id, payload: StoredJSON.encode(record)), intoTable: StoreTables.weightRecords.name)
            try handle.insertOrReplace(WeightOperationRow(id: draft.id, entryID: entry.id), intoTable: StoreTables.weightOperations.name)
            if let profile { try handle.insertOrReplace(ProfileRow(payload: StoredJSON.encode(profile)), intoTable: StoreTables.profile.name) }
            if target?.achieved(by: value) == true { try handle.delete(fromTable: StoreTables.weightTarget.name, where: WeightRow.Properties.id == "current") }
            if draft.day == LocalDay(date: now, timeZone: zone) { try handle.delete(fromTable: StoreTables.schedules.name, where: ScheduleRow.Properties.id == (draft.cardID + ":" + draft.day.rawValue)) }
        })
    }
}
