import Foundation
import WCDBSwift

extension LocalStore {
    func createCustomCard(_ draft: CustomCardDraft) throws -> String {
        guard let database else { throw StoreError.notOpen }
        let valid = try draft.validated()
        let rows: [CardRow] = try database.table(StoreTables.cards).getObjects()
        // The same name/artwork/unit is the same custom card; repeated save must not duplicate it.
        if let existing = rows.first(where: { $0.id.hasPrefix("custom.") && $0.titleKey == valid.name && $0.symbol == valid.artwork && $0.unit == valid.unit.rawValue }) {
            try database.delete(fromTable: StoreTables.archivedCards.name, where: ArchivedCardRow.Properties.id == existing.id)
            return existing.id
        }
        guard !rows.contains(where: { $0.id == valid.id }) else { throw StoreError.invalidCustomCard }
        let card = HabitCard(id: valid.id, titleKey: valid.name, symbol: valid.artwork, unit: valid.unit, sortOrder: (rows.map(\.sortOrder).max() ?? 0) + 1)
        try database.insert(CardRow(card), intoTable: StoreTables.cards.name)
        return card.id
    }

    func archiveCustomCard(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        let cards: [CardRow] = try database.table(StoreTables.cards).getObjects(where: CardRow.Properties.id == id, limit: 1)
        guard id.hasPrefix("custom."), !cards.isEmpty else { throw StoreError.invalidCard }
        try database.run(transaction: { handle in
            try handle.insertOrIgnore(ArchivedCardRow(id: id), intoTable: StoreTables.archivedCards.name)
            try handle.delete(fromTable: StoreTables.targets.name, where: TargetRow.Properties.id == id)
        })
    }

    func saveTarget(_ target: CardTarget) throws {
        guard let database else { throw StoreError.notOpen }
        let valid = try target.validated()
        let cards: [CardRow] = try database.table(StoreTables.cards).getObjects(where: CardRow.Properties.id == valid.cardID, limit: 1)
        let hidden: [ArchivedCardRow] = try database.table(StoreTables.archivedCards).getObjects(where: ArchivedCardRow.Properties.id == valid.cardID, limit: 1)
        guard !cards.isEmpty, hidden.isEmpty else { throw StoreError.invalidCard }
        if valid.isEmpty { try database.delete(fromTable: StoreTables.targets.name, where: TargetRow.Properties.id == valid.cardID) }
        else { try database.insertOrReplace(TargetRow(id: valid.cardID, payload: StoredJSON.encode(valid)), intoTable: StoreTables.targets.name) }
    }

    func saveContent(entryID: String, content: EntryContent?, asDraft: Bool) throws {
        guard let database else { throw StoreError.notOpen }
        let entries: [EntryRow] = try database.table(StoreTables.entries).getObjects(where: EntryRow.Properties.id == entryID, limit: 1)
        guard entries.first != nil else { throw StoreError.corruptRecord }
        let rows: [EntryContentRow] = try database.table(StoreTables.content).getObjects(where: EntryContentRow.Properties.id == entryID, limit: 1)
        var record = try rows.first.map { try StoredJSON.decode(EntryContentRecord.self, from: $0.payload) } ?? EntryContentRecord()
        let validated = try content?.validated()
        if asDraft { record.draft = validated }
        else { record.published = validated; record.draft = nil }
        try database.run(transaction: { handle in
            try handle.insertOrReplace(EntryContentRow(id: entryID, payload: StoredJSON.encode(record)), intoTable: StoreTables.content.name)
            if !asDraft {
                try handle.update(table: StoreTables.entries.name, on: EntryRow.Properties.note, with: validated?.text ?? "", where: EntryRow.Properties.id == entryID)
            }
        })
    }

    func discardContentDraft(entryID: String) throws {
        guard let database else { throw StoreError.notOpen }
        let rows: [EntryContentRow] = try database.table(StoreTables.content).getObjects(where: EntryContentRow.Properties.id == entryID, limit: 1)
        guard let row = rows.first else { return }
        var record = try StoredJSON.decode(EntryContentRecord.self, from: row.payload)
        record.draft = nil
        try database.insertOrReplace(EntryContentRow(id: entryID, payload: StoredJSON.encode(record)), intoTable: StoreTables.content.name)
    }
}
