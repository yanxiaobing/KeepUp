import Foundation
import WCDBSwift

extension LocalStore {
    func saveSchedule(_ value: ScheduledCard, now: Date) throws {
        guard let database else { throw StoreError.notOpen }
        let note = value.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.day > LocalDay(date: now), !note.isEmpty, note.utf16.count <= 140 else { throw StoreError.invalidSchedule }
        let cards: [CardRow] = try database.table(StoreTables.cards).getObjects(where: CardRow.Properties.id == value.cardID, limit: 1)
        let hidden: [ArchivedCardRow] = try database.table(StoreTables.archivedCards).getObjects(where: ArchivedCardRow.Properties.id == value.cardID, limit: 1)
        guard !cards.isEmpty, hidden.isEmpty else { throw StoreError.invalidCard }
        try database.insertOrReplace(ScheduleRow(ScheduledCard(cardID: value.cardID, day: value.day, note: note)), intoTable: StoreTables.schedules.name)
    }
    func deleteSchedule(id: String) throws {
        guard let database else { throw StoreError.notOpen }
        try database.delete(fromTable: StoreTables.schedules.name, where: ScheduleRow.Properties.id == id)
    }
}
