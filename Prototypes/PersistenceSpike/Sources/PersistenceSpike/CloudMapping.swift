import CloudKit

enum CloudMapping {
    static let proposedContainerID = "iCloud.com.bestlife.keepup"
    static let zoneID = CKRecordZone.ID(zoneName: "KeepUpPrivate")
    static func record(for entry: CheckIn) -> CKRecord {
        let record = CKRecord(recordType: "CheckIn", recordID: .init(recordName: entry.id, zoneID: zoneID))
        record["day"] = entry.day
        record["timeZoneID"] = entry.timeZoneID
        record["value"] = entry.value
        record["note"] = entry.note
        return record
    }
    static func entry(from record: CKRecord) -> CheckIn? {
        guard record.recordType == "CheckIn", let day = record["day"] as? String,
              let timeZoneID = record["timeZoneID"] as? String,
              let value = record["value"] as? Double else { return nil }
        return CheckIn(id: record.recordID.recordName, day: day, timeZoneID: timeZoneID,
                       value: value, note: record["note"] as? String)
    }
    // API compilation probe only: no container is instantiated and no iCloud request is made.
    // Production needs state persistence, CKRecord system fields, account isolation and conflict handling.
    static func configuration(database: CKDatabase, state: CKSyncEngine.State.Serialization?,
                              delegate: any CKSyncEngineDelegate) -> CKSyncEngine.Configuration {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: delegate)
        configuration.automaticallySync = false
        return configuration
    }
}
