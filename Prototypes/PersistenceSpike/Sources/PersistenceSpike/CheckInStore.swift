import Foundation
import WCDBSwift

// Feasibility probe only; this is not the production schema or sync implementation.
struct CheckIn: TableCodable, Sendable, Equatable {
    var id: String
    var day: String
    var timeZoneID: String
    var value: Double
    var note: String?

    enum CodingKeys: String, CodingTableKey {
        typealias Root = CheckIn
        case id, day, timeZoneID, value, note
        // WCDB's shared ORM metadata is not Sendable and initializes lazily.
        // SchemaBootstrap serializes first use; database instances stay actor-owned.
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindIndex(day, namedWith: "_day")
        }
    }
}

struct PendingChange: TableCodable, Sendable {
    var id: String
    var operation: String
    enum CodingKeys: String, CodingTableKey {
        typealias Root = PendingChange
        case id, operation
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

// Synthetic earlier schema, for testing addition of an optional column only.
struct CheckInV1: TableCodable {
    var id: String
    var day: String
    var timeZoneID: String
    var value: Double
    enum CodingKeys: String, CodingTableKey {
        typealias Root = CheckInV1
        case id, day, timeZoneID, value
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

enum ProbeError: Error { case injectedFailure }

private enum SchemaBootstrap {
    // WCDB 2.1.16 TableBinding.innerBinding is lazy without a synchronization guard.
    // Multiple store constructors must not configure the same binding concurrently.
    static let lock = NSLock()
}

actor CheckInStore {
    private let database: Database
    init(path: String) throws {
        let openedDatabase = Database(at: path)
        try SchemaBootstrap.lock.withLock {
            try openedDatabase.create(table: "check_ins", of: CheckIn.self)
            try openedDatabase.create(table: "pending_changes", of: PendingChange.self)
        }
        database = openedDatabase
    }
    func save(_ entry: CheckIn, failBeforeQueue: Bool = false) throws {
        try database.run(controllableTransaction: { handle in
            try handle.insertOrReplace(entry, intoTable: "check_ins")
            if failBeforeQueue { return false }
            try handle.insertOrReplace(PendingChange(id: entry.id, operation: "save"), intoTable: "pending_changes")
            return true
        })
        // The controllable API expresses deliberate rollback. WCDB's regular
        // transaction callback converts thrown Swift errors into database errors.
        if failBeforeQueue { throw ProbeError.injectedFailure }
    }
    func delete(id: String) throws {
        try database.run(transaction: { handle in
            try handle.delete(fromTable: "check_ins", where: CheckIn.Properties.id == id)
            try handle.insertOrReplace(PendingChange(id: id, operation: "delete"), intoTable: "pending_changes")
        })
    }
    func entries(day: String) throws -> [CheckIn] {
        try database.getObjects(fromTable: "check_ins", where: CheckIn.Properties.day == day,
                                orderBy: [CheckIn.Properties.id.asOrder()])
    }
    func total(day: String) throws -> Double {
        try database.getValue(on: CheckIn.Properties.value.sum(), fromTable: "check_ins",
                              where: CheckIn.Properties.day == day).doubleValue
    }
    func pending() throws -> [PendingChange] {
        try database.getObjects(fromTable: "pending_changes", orderBy: [PendingChange.Properties.id.asOrder()])
    }
    func close() { database.close() }
    static func seedV1(path: String) throws {
        let database = Database(at: path)
        defer { database.close() }
        try SchemaBootstrap.lock.withLock {
            try database.create(table: "check_ins", of: CheckInV1.self)
        }
        try database.insert(CheckInV1(id: "old", day: "2026-09-16", timeZoneID: "Asia/Shanghai", value: 3), intoTable: "check_ins")
    }
}
