import Foundation
import Testing
@testable import PersistenceSpike

private func withStore(_ body: (CheckInStore, String) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpSpike-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("probe.sqlite").path
    let store = try CheckInStore(path: path)
    do { try await body(store, path) }
    catch { await store.close(); throw error }
    await store.close()
}
private func entry(_ id: String = UUID().uuidString, day: String = "2026-09-16", value: Double = 1) -> CheckIn {
    CheckIn(id: id, day: day, timeZoneID: "America/Los_Angeles", value: value, note: "晨跑 · Morning run 🏃")
}

@Test func unicodeDateQueryAndSQLAggregation() async throws {
    try await withStore { store, _ in
        try await store.save(entry("a", value: 2.5))
        try await store.save(entry("b", value: 1.5))
        try await store.save(entry("c", day: "2026-09-17", value: 100))
        let rows = try await store.entries(day: "2026-09-16")
        #expect(rows.count == 2)
        #expect(rows.first?.note == "晨跑 · Morning run 🏃")
        #expect(rows.first?.timeZoneID == "America/Los_Angeles")
        #expect(try await store.total(day: "2026-09-16") == 4)
    }
}
@Test func transactionRollsBackRecordAndQueueTogether() async throws {
    try await withStore { store, _ in
        do {
            try await store.save(entry("failed"), failBeforeQueue: true)
            Issue.record("Expected an injected failure")
        } catch ProbeError.injectedFailure { }
        #expect(try await store.entries(day: "2026-09-16").isEmpty)
        #expect(try await store.pending().isEmpty)
    }
}
@Test func updatesDeletionAndQueueSurviveReopen() async throws {
    try await withStore { store, path in
        try await store.save(entry("a", value: 1))
        try await store.save(entry("a", value: 9))
        try await store.save(entry("b"))
        try await store.delete(id: "b")
        await store.close()
        let reopened = try CheckInStore(path: path)
        do {
            #expect(try await reopened.entries(day: "2026-09-16").map(\.value) == [9])
            #expect(try await reopened.pending().map(\.operation) == ["save", "delete"])
        } catch { await reopened.close(); throw error }
        await reopened.close()
    }
}
@Test func concurrentCallersDoNotLoseWrites() async throws {
    try await withStore { store, _ in
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask { try await store.save(entry("\(index)")) }
            }
            try await group.waitForAll()
        }
        #expect(try await store.entries(day: "2026-09-16").count == 32)
        #expect(try await store.pending().count == 32)
    }
}
@Test func concurrentStoreInitializationDoesNotDuplicateConstraints() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<16 {
            group.addTask {
                try await withStore { store, _ in
                    try await store.save(entry("one"))
                    #expect(try await store.entries(day: "2026-09-16").count == 1)
                }
            }
        }
        try await group.waitForAll()
    }
}
@Test func addingOptionalColumnPreservesOldRows() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpMigration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("probe.sqlite").path
    try CheckInStore.seedV1(path: path)
    let store = try CheckInStore(path: path)
    do {
        let old = try await store.entries(day: "2026-09-16")
        #expect(old.count == 1)
        #expect(old.first?.note == nil)
        #expect(old.first?.value == 3)
        try await store.save(entry("new"))
        #expect(try await store.entries(day: "2026-09-16").count == 2)
    } catch { await store.close(); throw error }
    await store.close()
}
@Test func cloudRecordRoundTripIsLocalAndPreservesIdentity() {
    let source = entry("stable-id")
    let record = CloudMapping.record(for: source)
    #expect(record.recordID.recordName == "stable-id")
    #expect(record.recordID.zoneID == CloudMapping.zoneID)
    #expect(CloudMapping.entry(from: record) == source)
    record["day"] = nil
    #expect(CloudMapping.entry(from: record) == nil)
}
