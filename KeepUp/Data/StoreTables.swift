import Foundation
import WCDBSwift

struct StoreTable<Row: TableCodable>: Sendable {
    let name: String
}

enum StoreTables {
    static let cards = StoreTable<CardRow>(name: "cards")
    static let entries = StoreTable<EntryRow>(name: "entries")
    static let profile = StoreTable<ProfileRow>(name: "profile")
    static let content = StoreTable<EntryContentRow>(name: "entry_content")
    static let archivedCards = StoreTable<ArchivedCardRow>(name: "archived_cards")
    static let targets = StoreTable<TargetRow>(name: "card_targets")
    static let schedules = StoreTable<ScheduleRow>(name: "scheduled_cards")
    static let wakeRecords = StoreTable<WakeRow>(name: "wake_records")
    static let weightTarget = StoreTable<WeightRow>(name: "weight_target")
    static let weightRecords = StoreTable<WeightRow>(name: "weight_records")
    static let weightOperations = StoreTable<WeightOperationRow>(name: "weight_operations")
}

extension Database {
    func table<Row>(_ definition: StoreTable<Row>) -> Table<Row> {
        getTable(named: definition.name, of: Row.self)
    }
}

enum StoredJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}
