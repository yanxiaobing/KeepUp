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
    func runningSession(id: String) async throws -> RunningSession?
    func saveRunningSession(_ session: RunningSession) async throws
    func finishRunning(_ session: RunningSession) async throws
    func discardRunning(id: String) async throws
    func saveSteps(_ reading: StepReading, goal: Int?, now: Date) async throws
    func saveTarget(_ target: CardTarget) async throws
}

actor LocalStore: CheckInRepository {
    private let fileURL: URL
    private(set) var database: Database?

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
        let cards: [CardRow] = try database.table(StoreTables.cards).getObjects(orderBy: [CardRow.Properties.sortOrder.asOrder()])
        let entries: [EntryRow] = try database.table(StoreTables.entries).getObjects(orderBy: [
            EntryRow.Properties.day.order(.descending),
            EntryRow.Properties.createdAt.order(.descending),
            EntryRow.Properties.id.asOrder()
        ])
        let profiles: [ProfileRow] = try database.table(StoreTables.profile).getObjects(limit: 1)
        let profile = try profiles.first.map { try StoredJSON.decode(UserProfile.self, from: $0.payload) }
        let contentRows: [EntryContentRow] = try database.table(StoreTables.content).getObjects()
        let content = try Dictionary(uniqueKeysWithValues: contentRows.map { ($0.id, try StoredJSON.decode(EntryContentRecord.self, from: $0.payload)) })
        let archived: [ArchivedCardRow] = try database.table(StoreTables.archivedCards).getObjects()
        let targets: [TargetRow] = try database.table(StoreTables.targets).getObjects(orderBy: [TargetRow.Properties.id.asOrder()])
        let schedules: [ScheduleRow] = try database.table(StoreTables.schedules).getObjects(orderBy: [ScheduleRow.Properties.id.asOrder()])
        let wakes: [WakeRow] = try database.table(StoreTables.wakeRecords).getObjects()
        let weightTargets: [WeightRow] = try database.table(StoreTables.weightTarget).getObjects(limit: 1)
        let weights: [WeightRow] = try database.table(StoreTables.weightRecords).getObjects()
        let steps = try database.table(StoreTables.stepRecords).getObjects()
        let active = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.phase == RunningPhase.running.rawValue || RunningRow.Properties.phase == RunningPhase.paused.rawValue, limit: 1)
        let activeRun = try active.first.map { try StoredJSON.decode(RunningSession.self, from: $0.payload) }
        return try LocalSnapshot(cards: cards.map { try $0.model() }, entries: entries.map { try $0.model() }, profile: profile, content: content,
                                 targets: targets.map { try StoredJSON.decode(CardTarget.self, from: $0.payload) }, schedules: schedules.map { try $0.model() }, weightTarget: weightTargets.first.map { try StoredJSON.decode(WeightTarget.self, from: $0.payload) }, weights: Dictionary(uniqueKeysWithValues: weights.map { ($0.id, try StoredJSON.decode(WeightRecord.self, from: $0.payload)) }), wakeUps: Dictionary(uniqueKeysWithValues: wakes.map { ($0.id, try StoredJSON.decode(WakeUpRecord.self, from: $0.payload)) }), steps: Dictionary(uniqueKeysWithValues: steps.map { ($0.id, try StoredJSON.decode(StepRecord.self, from: $0.payload)) }), activeRun: activeRun, archivedCardIDs: Set(archived.map(\.id)))
    }

    func add(_ draft: CheckInDraft, now: Date = .now) throws {
        guard let database else { throw StoreError.notOpen }
        guard let timeZone = TimeZone(identifier: draft.timeZoneID), draft.day <= LocalDay(date: now, timeZone: timeZone) else {
            throw StoreError.invalidDate
        }
        guard draft.cardID != "punchcard.1" else { throw StoreError.invalidCard }
        guard draft.note.count <= 1000 else { throw StoreError.noteTooLong }
        if draft.cardID == "punchcard.50" { try saveWeight(draft, now: now); return }
        let rows: [CardRow] = try database.table(StoreTables.cards).getObjects(where: CardRow.Properties.id == draft.cardID, limit: 1)
        guard let row = rows.first else { throw StoreError.invalidCard }
        let card = try row.model()
        let hidden: [ArchivedCardRow] = try database.table(StoreTables.archivedCards).getObjects(where: ArchivedCardRow.Properties.id == card.id, limit: 1)
        guard hidden.isEmpty else { throw StoreError.invalidCard }
        if card.unit != .none {
            guard let value = draft.quantity, value.isFinite, value > 0, value <= 1_000_000,
                  !card.unit.requiresWholeNumber || value.rounded() == value else { throw StoreError.invalidQuantity }
        }
        let schedules: [ScheduleRow] = try database.table(StoreTables.schedules).getObjects(where: ScheduleRow.Properties.id == (card.id + ":" + draft.day.rawValue), limit: 1)
        var wake: WakeUpRecord?
        if card.id == "punchcard.63" {
            guard draft.day == LocalDay(date: now, timeZone: timeZone), let time = draft.wakeTime,
                  time <= now, LocalDay(date: time, timeZone: timeZone) == draft.day else { throw StoreError.invalidDate }
            let existing: [EntryRow] = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.cardID == card.id && EntryRow.Properties.day == draft.day.rawValue)
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
            try handle.insertOrIgnore(EntryRow(entry), intoTable: StoreTables.entries.name)
            if let wake { try handle.insertOrReplace(WakeRow(id: entry.id, payload: StoredJSON.encode(wake)), intoTable: StoreTables.wakeRecords.name) }
            if draft.day == LocalDay(date: now, timeZone: timeZone) {
                try handle.delete(fromTable: StoreTables.schedules.name, where: ScheduleRow.Properties.id == (card.id + ":" + draft.day.rawValue))
            }
        })
    }

    func delete(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        let entry = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.id == id, limit: 1).first
        var runningDeletion = try database.table(StoreTables.running).getObjects(where: RunningRow.Properties.id == id, limit: 1).first
        runningDeletion?.phase = "deleted"
        runningDeletion?.payload = Data()
        var stepDeletion: StepRow?
        if let entry, entry.cardID == "punchcard.1",
           let row = try database.table(StoreTables.stepRecords).getObjects(where: StepRow.Properties.id == entry.day, limit: 1).first {
            var record = try StoredJSON.decode(StepRecord.self, from: row.payload)
            record.checkInDeleted = true
            stepDeletion = StepRow(id: row.id, payload: try StoredJSON.encode(record))
        }
        try database.run(transaction: { handle in
            if let runningDeletion { try handle.insertOrReplace(runningDeletion, intoTable: StoreTables.running.name) }
            if let stepDeletion { try handle.insertOrReplace(stepDeletion, intoTable: StoreTables.stepRecords.name) }
            try handle.delete(fromTable: StoreTables.weightOperations.name, where: WeightOperationRow.Properties.entryID == id)
            try handle.delete(fromTable: StoreTables.weightRecords.name, where: WeightRow.Properties.id == id)
            try handle.delete(fromTable: StoreTables.wakeRecords.name, where: WakeRow.Properties.id == id)
            try handle.delete(fromTable: StoreTables.content.name, where: EntryContentRow.Properties.id == id)
            try handle.delete(fromTable: StoreTables.entries.name, where: EntryRow.Properties.id == id)
        })
    }

    func saveProfile(_ profile: UserProfile) throws {
        guard let database else { throw StoreError.notOpen }
        let valid = try profile.validated()
        try database.insertOrReplace(ProfileRow(payload: StoredJSON.encode(valid)), intoTable: StoreTables.profile.name)
    }

    func close() { database?.close(); database = nil }

    func updateProfile(_ change: ProfileChange, now: Date) throws {
        guard let database else { throw StoreError.notOpen }
        let rows: [ProfileRow] = try database.table(StoreTables.profile).getObjects(limit: 1)
        let profile = try rows.first.map { try StoredJSON.decode(UserProfile.self, from: $0.payload) } ?? UserProfile()
        let updated = try change.applying(to: profile).validated()
        if case .weight(let value) = change {
            let draft = CheckInDraft(cardID: "punchcard.50", day: LocalDay(date: now), timeZoneID: TimeZone.current.identifier, quantity: value, note: "")
            try saveWeight(draft, now: now, profileOverride: updated)
        } else {
            try database.insertOrReplace(ProfileRow(payload: StoredJSON.encode(updated)), intoTable: StoreTables.profile.name)
        }
    }
}
