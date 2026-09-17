import Foundation
import WCDBSwift

protocol CheckInRepository: Sendable {
    func open() async throws
    func snapshot() async throws -> LocalSnapshot
    func add(_ draft: CheckInDraft, now: Date) async throws
    func delete(id: String) async throws
    func saveProfile(_ profile: UserProfile) async throws
    func updateProfile(_ change: ProfileChange, now: Date) async throws
    func saveContent(entryID: String, content: EntryContent?, asDraft: Bool) async throws
    func discardContentDraft(entryID: String) async throws
    func createCustomCard(_ draft: CustomCardDraft) async throws -> String
    func archiveCustomCard(id: String) async throws
    func saveWeightTarget(_ target: WeightTarget, now: Date) async throws
    func saveSchedule(_ value: ScheduledCard, now: Date) async throws
    func deleteSchedule(id: String) async throws
    func saveTarget(_ target: CardTarget) async throws
}

actor LocalStore: CheckInRepository {
    private let fileURL: URL
    private var database: Database?

    init(fileURL: URL) { self.fileURL = fileURL }

    func open() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opened = Database(at: fileURL.path)
        do {
            try DatabaseSchema.prepare(opened)
            database = opened
        } catch {
            opened.close()
            throw error
        }
    }

    func snapshot() throws -> LocalSnapshot {
        guard let database else { throw StoreError.notOpen }
        let cards: [CardRow] = try database.getObjects(fromTable: "cards", orderBy: [CardRow.Properties.sortOrder.asOrder()])
        let entries: [EntryRow] = try database.getObjects(fromTable: "entries", orderBy: [
            EntryRow.Properties.day.order(.descending),
            EntryRow.Properties.createdAt.order(.descending),
            EntryRow.Properties.id.asOrder()
        ])
        let profiles: [ProfileRow] = try database.getObjects(fromTable: "profile", limit: 1)
        let profile = try profiles.first.map { try JSONDecoder().decode(UserProfile.self, from: $0.payload) }
        let contentRows: [EntryContentRow] = try database.getObjects(fromTable: "entry_content")
        let content = try Dictionary(uniqueKeysWithValues: contentRows.map { ($0.id, try JSONDecoder().decode(EntryContentRecord.self, from: $0.payload)) })
        let archived: [ArchivedCardRow] = try database.getObjects(fromTable: "archived_cards")
        let targets: [TargetRow] = try database.getObjects(fromTable: "card_targets", orderBy: [TargetRow.Properties.id.asOrder()])
        let schedules: [ScheduleRow] = try database.getObjects(fromTable: "scheduled_cards", orderBy: [ScheduleRow.Properties.id.asOrder()])
        let wakes: [WakeRow] = try database.getObjects(fromTable: "wake_records")
        let weightTargets: [WeightRow] = try database.getObjects(fromTable: "weight_target", limit: 1)
        let weights: [WeightRow] = try database.getObjects(fromTable: "weight_records")
        return try LocalSnapshot(cards: cards.map { try $0.model() }, entries: entries.map { try $0.model() }, profile: profile, content: content,
                                 targets: targets.map { try JSONDecoder().decode(CardTarget.self, from: $0.payload) }, schedules: schedules.map { try $0.model() }, weightTarget: weightTargets.first.map { try JSONDecoder().decode(WeightTarget.self, from: $0.payload) }, weights: Dictionary(uniqueKeysWithValues: weights.map { ($0.id, try JSONDecoder().decode(WeightRecord.self, from: $0.payload)) }), wakeUps: Dictionary(uniqueKeysWithValues: wakes.map { ($0.id, try JSONDecoder().decode(WakeUpRecord.self, from: $0.payload)) }), archivedCardIDs: Set(archived.map(\.id)))
    }

    func add(_ draft: CheckInDraft, now: Date = .now) throws {
        guard let database else { throw StoreError.notOpen }
        guard let timeZone = TimeZone(identifier: draft.timeZoneID), draft.day <= LocalDay(date: now, timeZone: timeZone) else {
            throw StoreError.invalidDate
        }
        guard draft.note.count <= 1000 else { throw StoreError.noteTooLong }
        if draft.cardID == "punchcard.50" { try saveWeight(draft, now: now); return }
        let rows: [CardRow] = try database.getObjects(fromTable: "cards", where: CardRow.Properties.id == draft.cardID, limit: 1)
        guard let row = rows.first else { throw StoreError.invalidCard }
        let card = try row.model()
        let hidden: [ArchivedCardRow] = try database.getObjects(fromTable: "archived_cards", where: ArchivedCardRow.Properties.id == card.id, limit: 1)
        guard hidden.isEmpty else { throw StoreError.invalidCard }
        if card.unit != .none {
            guard let value = draft.quantity, value.isFinite, value > 0, value <= 1_000_000,
                  !card.unit.requiresWholeNumber || value.rounded() == value else { throw StoreError.invalidQuantity }
        }
        let schedules: [ScheduleRow] = try database.getObjects(fromTable: "scheduled_cards", where: ScheduleRow.Properties.id == (card.id + ":" + draft.day.rawValue), limit: 1)
        var wake: WakeUpRecord?
        if card.id == "punchcard.63" {
            guard draft.day == LocalDay(date: now, timeZone: timeZone), let time = draft.wakeTime,
                  time <= now, LocalDay(date: time, timeZone: timeZone) == draft.day else { throw StoreError.invalidDate }
            let existing: [EntryRow] = try database.getObjects(fromTable: "entries", where: EntryRow.Properties.cardID == card.id && EntryRow.Properties.day == draft.day.rawValue)
            if existing.contains(where: { $0.id == draft.id }) { return }
            guard existing.isEmpty else { throw StoreError.duplicateWakeUp }
            wake = WakeUpRecord(time: time, recordedAt: now, timeZoneID: timeZone.identifier)
        }
        let entry = CheckInEntry(id: draft.id, cardID: card.id, day: draft.day, timeZoneID: timeZone.identifier,
                                 createdAt: now, quantity: card.unit == .none ? nil : draft.quantity,
                                 unit: card.unit, note: schedules.first?.note ?? draft.note.trimmingCharacters(in: .whitespacesAndNewlines))
        // UUID is a primary key: a retry of the same successful draft cannot duplicate it.
        // A fresh draft is a separate check-in, even for the same card and civil day.
        try database.run(transaction: { handle in
            try handle.insertOrIgnore(EntryRow(entry), intoTable: "entries")
            if let wake { try handle.insertOrReplace(WakeRow(id: entry.id, payload: JSONEncoder().encode(wake)), intoTable: "wake_records") }
            if draft.day == LocalDay(date: now, timeZone: timeZone) {
                try handle.delete(fromTable: "scheduled_cards", where: ScheduleRow.Properties.id == (card.id + ":" + draft.day.rawValue))
            }
        })
    }

    func delete(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        try database.run(transaction: { handle in
            try handle.delete(fromTable: "weight_operations", where: WeightOperationRow.Properties.entryID == id)
            try handle.delete(fromTable: "weight_records", where: WeightRow.Properties.id == id)
            try handle.delete(fromTable: "wake_records", where: WakeRow.Properties.id == id)
            try handle.delete(fromTable: "entry_content", where: EntryContentRow.Properties.id == id)
            try handle.delete(fromTable: "entries", where: EntryRow.Properties.id == id)
        })
    }

    func saveProfile(_ profile: UserProfile) throws {
        guard let database else { throw StoreError.notOpen }
        let valid = try profile.validated()
        try database.insertOrReplace(ProfileRow(payload: JSONEncoder().encode(valid)), intoTable: "profile")
    }

    func close() { database?.close(); database = nil }

    func updateProfile(_ change: ProfileChange, now: Date) throws {
        guard let database else { throw StoreError.notOpen }
        let rows: [ProfileRow] = try database.getObjects(fromTable: "profile", limit: 1)
        let profile = try rows.first.map { try JSONDecoder().decode(UserProfile.self, from: $0.payload) } ?? UserProfile()
        let updated = try change.applying(to: profile).validated()
        if case .weight(let value) = change {
            let draft = CheckInDraft(cardID: "punchcard.50", day: LocalDay(date: now), timeZoneID: TimeZone.current.identifier, quantity: value, note: "")
            try saveWeight(draft, now: now, profileOverride: updated)
        } else {
            try database.insertOrReplace(ProfileRow(payload: JSONEncoder().encode(updated)), intoTable: "profile")
        }
    }
}


extension LocalStore {
    func createCustomCard(_ draft: CustomCardDraft) throws -> String {
        guard let database else { throw StoreError.notOpen }
        let valid = try draft.validated()
        let rows: [CardRow] = try database.getObjects(fromTable: "cards")
        // The same name/artwork/unit is the same custom card; repeated save must not duplicate it.
        if let existing = rows.first(where: { $0.id.hasPrefix("custom.") && $0.titleKey == valid.name && $0.symbol == valid.artwork && $0.unit == valid.unit.rawValue }) {
            try database.delete(fromTable: "archived_cards", where: ArchivedCardRow.Properties.id == existing.id)
            return existing.id
        }
        guard !rows.contains(where: { $0.id == valid.id }) else { throw StoreError.invalidCustomCard }
        let card = HabitCard(id: valid.id, titleKey: valid.name, symbol: valid.artwork, unit: valid.unit, sortOrder: (rows.map(\.sortOrder).max() ?? 0) + 1)
        try database.insert(CardRow(card), intoTable: "cards")
        return card.id
    }

    func archiveCustomCard(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        let cards: [CardRow] = try database.getObjects(fromTable: "cards", where: CardRow.Properties.id == id, limit: 1)
        guard id.hasPrefix("custom."), !cards.isEmpty else { throw StoreError.invalidCard }
        try database.run(transaction: { handle in
            try handle.insertOrIgnore(ArchivedCardRow(id: id), intoTable: "archived_cards")
            try handle.delete(fromTable: "card_targets", where: TargetRow.Properties.id == id)
        })
    }

    func saveTarget(_ target: CardTarget) throws {
        guard let database else { throw StoreError.notOpen }
        let valid = try target.validated()
        let cards: [CardRow] = try database.getObjects(fromTable: "cards", where: CardRow.Properties.id == valid.cardID, limit: 1)
        let hidden: [ArchivedCardRow] = try database.getObjects(fromTable: "archived_cards", where: ArchivedCardRow.Properties.id == valid.cardID, limit: 1)
        guard !cards.isEmpty, hidden.isEmpty else { throw StoreError.invalidCard }
        if valid.isEmpty { try database.delete(fromTable: "card_targets", where: TargetRow.Properties.id == valid.cardID) }
        else { try database.insertOrReplace(TargetRow(id: valid.cardID, payload: JSONEncoder().encode(valid)), intoTable: "card_targets") }
    }

    func saveContent(entryID: String, content: EntryContent?, asDraft: Bool) throws {
        guard let database else { throw StoreError.notOpen }
        let entries: [EntryRow] = try database.getObjects(fromTable: "entries", where: EntryRow.Properties.id == entryID, limit: 1)
        guard entries.first != nil else { throw StoreError.corruptRecord }
        let rows: [EntryContentRow] = try database.getObjects(fromTable: "entry_content", where: EntryContentRow.Properties.id == entryID, limit: 1)
        var record = try rows.first.map { try JSONDecoder().decode(EntryContentRecord.self, from: $0.payload) } ?? EntryContentRecord()
        let validated = try content?.validated()
        if asDraft { record.draft = validated }
        else { record.published = validated; record.draft = nil }
        try database.run(transaction: { handle in
            try handle.insertOrReplace(EntryContentRow(id: entryID, payload: JSONEncoder().encode(record)), intoTable: "entry_content")
            if !asDraft {
                try handle.update(table: "entries", on: EntryRow.Properties.note, with: validated?.text ?? "", where: EntryRow.Properties.id == entryID)
            }
        })
    }

    func discardContentDraft(entryID: String) throws {
        guard let database else { throw StoreError.notOpen }
        let rows: [EntryContentRow] = try database.getObjects(fromTable: "entry_content", where: EntryContentRow.Properties.id == entryID, limit: 1)
        guard let row = rows.first else { return }
        var record = try JSONDecoder().decode(EntryContentRecord.self, from: row.payload)
        record.draft = nil
        try database.insertOrReplace(EntryContentRow(id: entryID, payload: JSONEncoder().encode(record)), intoTable: "entry_content")
    }
}

extension LocalStore {
    func saveSchedule(_ value: ScheduledCard, now: Date) throws {
        guard let database else { throw StoreError.notOpen }
        let note = value.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.day > LocalDay(date: now), !note.isEmpty, note.utf16.count <= 140 else { throw StoreError.invalidSchedule }
        let cards: [CardRow] = try database.getObjects(fromTable: "cards", where: CardRow.Properties.id == value.cardID, limit: 1)
        let hidden: [ArchivedCardRow] = try database.getObjects(fromTable: "archived_cards", where: ArchivedCardRow.Properties.id == value.cardID, limit: 1)
        guard !cards.isEmpty, hidden.isEmpty else { throw StoreError.invalidCard }
        try database.insertOrReplace(ScheduleRow(ScheduledCard(cardID: value.cardID, day: value.day, note: note)), intoTable: "scheduled_cards")
    }
    func deleteSchedule(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        try database.delete(fromTable: "scheduled_cards", where: ScheduleRow.Properties.id == id)
    }
}

extension LocalStore {
    func saveWeightTarget(_ target: WeightTarget, now: Date) throws {
        let target = try target.validated(now: now)
        let draft = CheckInDraft(id: "weight.target." + target.id, cardID: "punchcard.50", day: target.start,
                                 timeZoneID: TimeZone.current.identifier, quantity: target.initial, note: "")
        try saveWeight(draft, now: now, targetOverride: target)
    }

    private func saveWeight(_ draft: CheckInDraft, now: Date, targetOverride: WeightTarget? = nil, profileOverride: UserProfile? = nil) throws {
        guard let database else { throw StoreError.notOpen }
        guard let zone = TimeZone(identifier: draft.timeZoneID), draft.day <= LocalDay(date: now, timeZone: zone) else { throw StoreError.invalidDate }
        guard let raw = draft.quantity, raw.isFinite, (5...200).contains(raw) else { throw StoreError.invalidQuantity }
        let value = (raw*10).rounded()/10
        let identity: [EntryRow] = try database.getObjects(fromTable: "entries", where: EntryRow.Properties.id == draft.id, limit: 1)
        if let occupied = identity.first {
            guard occupied.cardID == draft.cardID, occupied.day == draft.day.rawValue else { throw StoreError.invalidCard }
        }
        let all: [EntryRow] = try database.getObjects(fromTable: "entries", where: EntryRow.Properties.cardID == "punchcard.50", orderBy: [EntryRow.Properties.createdAt.order(.descending)])
        // Persist the operation ID separately from the stable daily entry ID for idempotent retries.
        let receipts: [WeightOperationRow] = try database.getObjects(fromTable: "weight_operations", where: WeightOperationRow.Properties.id == draft.id, limit: 1)
        if !receipts.isEmpty { return }
        let existing = all.first { $0.day == draft.day.rawValue }
        let targets: [WeightRow] = try database.getObjects(fromTable: "weight_target", limit: 1)
        let active = try targetOverride ?? targets.first.map { try JSONDecoder().decode(WeightTarget.self, from: $0.payload) }
        let target = active.flatMap { draft.day >= $0.start ? $0 : nil }
        let profiles: [ProfileRow] = try database.getObjects(fromTable: "profile", limit: 1)
        var profile = try profileOverride ?? profiles.first.map { try JSONDecoder().decode(UserProfile.self, from: $0.payload) }
        let plans: [ScheduleRow] = try database.getObjects(fromTable: "scheduled_cards", where: ScheduleRow.Properties.id == (draft.cardID + ":" + draft.day.rawValue), limit: 1)
        let entry = CheckInEntry(id: existing?.id ?? draft.id, cardID: draft.cardID, day: draft.day, timeZoneID: existing?.timeZoneID ?? zone.identifier,
                                 createdAt: existing.map { Date(timeIntervalSince1970: $0.createdAt) } ?? now, quantity: value, unit: .kilograms,
                                 note: plans.first?.note ?? existing?.note ?? draft.note)
        let record = WeightRecord(height: profile?.height, target: target)
        // Backfilling an older date must not replace the latest weight shown in personal information.
        if !all.contains(where: { $0.day > draft.day.rawValue }) { profile?.weight = value }
        try database.run(transaction: { handle in
            if let targetOverride { try handle.insertOrReplace(WeightRow(id: "current", payload: JSONEncoder().encode(targetOverride)), intoTable: "weight_target") }
            try handle.insertOrReplace(EntryRow(entry), intoTable: "entries")
            try handle.insertOrReplace(WeightRow(id: entry.id, payload: JSONEncoder().encode(record)), intoTable: "weight_records")
            try handle.insertOrReplace(WeightOperationRow(id: draft.id, entryID: entry.id), intoTable: "weight_operations")
            if let profile { try handle.insertOrReplace(ProfileRow(payload: JSONEncoder().encode(profile)), intoTable: "profile") }
            if target?.achieved(by: value) == true { try handle.delete(fromTable: "weight_target", where: WeightRow.Properties.id == "current") }
            if draft.day == LocalDay(date: now, timeZone: zone) { try handle.delete(fromTable: "scheduled_cards", where: ScheduleRow.Properties.id == (draft.cardID + ":" + draft.day.rawValue)) }
        })
    }
}
