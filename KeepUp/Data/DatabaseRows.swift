import Foundation
import WCDBSwift

struct CardRow: TableCodable {
    var id: String
    var titleKey: String
    var symbol: String
    var unit: String
    var sortOrder: Int

    init(_ card: HabitCard) {
        id = card.id; titleKey = card.titleKey; symbol = card.symbol
        unit = card.unit.rawValue; sortOrder = card.sortOrder
    }

    func model() throws -> HabitCard {
        guard let unit = CardUnit(rawValue: unit) else { throw StoreError.corruptRecord }
        return HabitCard(id: id, titleKey: titleKey, symbol: symbol, unit: unit, sortOrder: sortOrder)
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = CardRow
        case id, titleKey, symbol, unit, sortOrder
        // WCDB binding types aren't Sendable. First use is serialized by DatabaseSchema.
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

struct EntryRow: TableCodable {
    var id: String
    var cardID: String
    var day: String
    var timeZoneID: String
    var createdAt: Double
    var quantity: Double?
    var unit: String
    var note: String
    var runningKind: String?
    var runningKilocalories: Double?

    init(_ entry: CheckInEntry) {
        id = entry.id; cardID = entry.cardID; day = entry.day.rawValue
        timeZoneID = entry.timeZoneID; createdAt = entry.createdAt.timeIntervalSince1970
        quantity = entry.quantity; unit = entry.unit.rawValue; note = entry.note
        runningKind = entry.runningKind?.rawValue
        runningKilocalories = entry.runningKilocalories
    }

    func model() throws -> CheckInEntry {
        guard let day = LocalDay(rawValue: day), let unit = CardUnit(rawValue: unit),
              TimeZone(identifier: timeZoneID) != nil,
              runningKind.map({ RunningKind(rawValue: $0) != nil }) ?? true,
              runningKilocalories.map({ $0.isFinite && $0 >= 0 && $0 < Double(Int.max) }) ?? true else { throw StoreError.corruptRecord }
        return CheckInEntry(id: id, cardID: cardID, day: day, timeZoneID: timeZoneID,
                            createdAt: Date(timeIntervalSince1970: createdAt), quantity: quantity, unit: unit, note: note,
                            runningKind: runningKind.flatMap(RunningKind.init(rawValue:)), runningKilocalories: runningKilocalories)
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = EntryRow
        case id, cardID, day, timeZoneID, createdAt, quantity, unit, note, runningKind, runningKilocalories
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindIndex(day, createdAt, namedWith: "_day_created")
            BindIndex(cardID, day, namedWith: "_card_day")
        }
    }
}

enum DatabaseSchema {
    static let version = 10
    private static let initializationLock = NSLock()

    static func prepare(_ database: Database) throws {
        try initializationLock.withLock {
            let existingVersion = try database.getValue(from: StatementPragma().pragma(.userVersion))?.intValue ?? 0
            guard existingVersion <= version else { throw StoreError.newerSchema }
            try database.run(transaction: { handle in
                try handle.create(table: StoreTables.running.name, of: RunningRow.self)
                try handle.create(table: StoreTables.stepRecords.name, of: StepRow.self)
                try handle.create(table: StoreTables.weightOperations.name, of: WeightOperationRow.self)
                try handle.create(table: StoreTables.weightTarget.name, of: WeightRow.self)
                try handle.create(table: StoreTables.weightRecords.name, of: WeightRow.self)
                try handle.create(table: StoreTables.schedules.name, of: ScheduleRow.self)
                try handle.create(table: StoreTables.wakeRecords.name, of: WakeRow.self)
                try handle.create(table: StoreTables.cards.name, of: CardRow.self)
                try handle.create(table: StoreTables.entries.name, of: EntryRow.self)
                try handle.create(table: StoreTables.profile.name, of: ProfileRow.self)
                try handle.create(table: StoreTables.content.name, of: EntryContentRow.self)
                try handle.create(table: StoreTables.targets.name, of: TargetRow.self)
                try handle.create(table: StoreTables.archivedCards.name, of: ArchivedCardRow.self)
                try handle.insertOrIgnore(HabitCard.starters.map(CardRow.init), intoTable: StoreTables.cards.name)
                try handle.insertOrIgnore(OriginalCatalog.items.map { CardRow($0.card) }, intoTable: StoreTables.cards.name)
                if existingVersion < 10 {
                    // Copy only small summary fields. Normal snapshots still avoid loading historical tracks.
                    var previousID = ""
                    while true {
                        let rows: [RunningRow] = try handle.getObjects(fromTable: StoreTables.running.name,
                            where: RunningRow.Properties.phase == RunningPhase.finished.rawValue && RunningRow.Properties.id > previousID,
                            orderBy: [RunningRow.Properties.id.asOrder()], limit: 1)
                        guard let row = rows.first else { break }
                        previousID = row.id
                        let session = try StoredJSON.decode(RunningSession.self, from: row.payload)
                        try handle.update(table: StoreTables.entries.name, on: EntryRow.Properties.runningKind,
                                          with: session.kind.rawValue, where: EntryRow.Properties.id == row.id)
                        if let energy = RunningMetrics(session: session).estimatedEnergyKilocalories {
                            try handle.update(table: StoreTables.entries.name, on: EntryRow.Properties.runningKilocalories,
                                              with: energy, where: EntryRow.Properties.id == row.id)
                        }
                    }
                }
                if existingVersion < version {
                    try handle.exec(StatementPragma().pragma(.userVersion).to(version))
                }
            })
        }
    }
}

struct TargetRow: TableCodable {
    var id: String
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = TargetRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

struct ProfileRow: TableCodable {
    var id = "local"
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = ProfileRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

struct EntryContentRow: TableCodable {
    var id: String
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = EntryContentRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

struct ArchivedCardRow: TableCodable {
    var id: String
    enum CodingKeys: String, CodingTableKey {
        typealias Root = ArchivedCardRow
        case id
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) { BindColumnConstraint(id, isPrimary: true) }
    }
}

struct ScheduleRow: TableCodable {
    var id: String
    var cardID: String
    var day: String
    var note: String
    init(_ value: ScheduledCard) { id = value.id; cardID = value.cardID; day = value.day.rawValue; note = value.note }
    func model() throws -> ScheduledCard {
        guard let day = LocalDay(rawValue: day) else { throw StoreError.corruptRecord }
        return ScheduledCard(cardID: cardID, day: day, note: note)
    }
    enum CodingKeys: String, CodingTableKey {
        typealias Root = ScheduleRow
        case id, cardID, day, note
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) { BindColumnConstraint(id, isPrimary: true) }
    }
}
struct WakeRow: TableCodable {
    var id: String
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = WakeRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) { BindColumnConstraint(id, isPrimary: true) }
    }
}

struct WeightRow: TableCodable {
    var id: String
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = WeightRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) { BindColumnConstraint(id, isPrimary: true) }
    }
}

struct WeightOperationRow: TableCodable {
    var id: String
    var entryID: String
    enum CodingKeys: String, CodingTableKey {
        typealias Root = WeightOperationRow
        case id, entryID
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) { BindColumnConstraint(id, isPrimary: true) }
    }
}

struct StepRow: TableCodable {
    var id: String
    var payload: Data
    enum CodingKeys: String, CodingTableKey {
        typealias Root = StepRow
        case id, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

struct RunningRow: TableCodable {
    var id: String
    var phase: String
    var revision: Int
    var payload: Data

    init(discardedID: String) {
        id = discardedID
        phase = "deleted"
        revision = 0
        payload = Data()
    }

    init(_ session: RunningSession) throws {
        id = session.id
        phase = session.phase.rawValue
        revision = session.revision
        payload = try StoredJSON.encode(session)
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = RunningRow
        case id, phase, revision, payload
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindIndex(phase, namedWith: "_phase")
        }
    }
}
