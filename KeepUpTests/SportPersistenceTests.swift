import Foundation
import Testing
import WCDBSwift
@testable import KeepUp

private let sportStart = Date(timeIntervalSince1970: 1_800_000_000)
private let sportZone = TimeZone(identifier: "UTC")!

private func withSportStore(_ action: (LocalStore) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpSport-\(UUID())")
    let store = LocalStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    defer { try? FileManager.default.removeItem(at: directory) }
    do { try await store.open(); try await action(store) }
    catch { await store.close(); throw error }
    await store.close()
}

@Test(arguments: [RunningKind.outdoor, .indoor, .cycling])
func sportModePersistsAndConsumesOnlyItsOwnCardPlan(kind: RunningKind) async throws {
    try await withSportStore { store in
        var session = RunningSession(startedAt: sportStart, timeZone: sportZone, kind: kind)
        session.distanceMeters = kind.minimumDistanceMeters
        session.updatedAt = sportStart.addingTimeInterval(180)
        if kind == .indoor { session.steps = 300 }
        for id in ["punchcard.2", "punchcard.96"] {
            try await store.saveSchedule(ScheduledCard(cardID: id, day: session.day, note: id), now: sportStart.addingTimeInterval(-86_400))
        }
        try await store.saveRunningSession(session)
        await store.close()
        try await store.open()
        #expect(try await store.snapshot().activeRun?.kind == kind)
        session.finish(at: sportStart.addingTimeInterval(180))
        try await store.finishRunning(session)
        try await store.finishRunning(session)
        let snapshot = try await store.snapshot()
        let entry = try #require(snapshot.entries.first)
        #expect(snapshot.entries.count == 1)
        #expect(entry.cardID == kind.cardID)
        #expect(entry.note == kind.cardID)
        #expect(entry.quantity == kind.minimumDistanceMeters / 1_000)
        #expect(snapshot.schedules.count == 1)
        #expect(snapshot.schedules.first?.cardID != kind.cardID)
        #expect(try await store.runningSession(id: session.id) == session)
    }
}

@Test func olderRunningJSONDefaultsToOutdoorAndRetainsHistory() throws {
    var original = RunningSession(startedAt: sportStart, timeZone: sportZone)
    original.distanceMeters = 100
    original.finish(at: sportStart.addingTimeInterval(60))
    var object = try #require(JSONSerialization.jsonObject(with: StoredJSON.encode(original)) as? [String: Any])
    object.removeValue(forKey: "kind")
    object.removeValue(forKey: "steps")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try StoredJSON.decode(RunningSession.self, from: legacy)
    #expect(decoded.kind == .outdoor)
    #expect(decoded.steps == 0)
    #expect(decoded.id == original.id)
    #expect(decoded.distanceMeters == 100)
    #expect(decoded.phase == .finished)
}

@Test func activeSportCannotChangeIdentityAndCyclingCannotSaveAtRunningThreshold() async throws {
    try await withSportStore { store in
        let run = RunningSession(startedAt: sportStart, timeZone: sportZone)
        try await store.saveRunningSession(run)
        var changed = RunningSession(id: run.id, startedAt: sportStart, timeZone: sportZone, kind: .cycling)
        changed.revision = run.revision + 1
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(changed) }
        #expect(try await store.snapshot().activeRun == run)
        try await store.discardRunning(id: run.id)

        var cycling = RunningSession(startedAt: sportStart, timeZone: sportZone, kind: .cycling)
        cycling.distanceMeters = 100
        cycling.updatedAt = sportStart.addingTimeInterval(60)
        try await store.saveRunningSession(cycling)
        var tooShort = cycling
        tooShort.finish(at: sportStart.addingTimeInterval(60))
        await #expect(throws: StoreError.invalidQuantity) { try await store.finishRunning(tooShort) }
        #expect(try await store.snapshot().activeRun == cycling)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}

@Test func schemaEightRunningDraftRemainsOutdoorAfterSportUpgrade() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpSportUpgrade-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    var saved = RunningSession(startedAt: sportStart, timeZone: sportZone)
    saved.distanceMeters = 100
    saved.pause(at: sportStart.addingTimeInterval(60))
    var object = try #require(JSONSerialization.jsonObject(with: StoredJSON.encode(saved)) as? [String: Any])
    object.removeValue(forKey: "kind")
    object.removeValue(forKey: "steps")
    var row = try RunningRow(saved)
    row.payload = try JSONSerialization.data(withJSONObject: object)
    let database = Database(at: url.path)
    try DatabaseSchema.prepare(database)
    try database.insertOrReplace(row, intoTable: StoreTables.running.name)
    try database.exec(StatementPragma().pragma(.userVersion).to(8))
    database.close()
    let store = LocalStore(fileURL: url)
    do {
        try await store.open()
        let active = try #require(try await store.snapshot().activeRun)
        #expect(active == saved)
        #expect(active.kind == .outdoor)
        #expect(active.steps == 0)
        await store.close()
    } catch { await store.close(); throw error }
    let migrated = Database(at: url.path)
    #expect(try migrated.getValue(from: StatementPragma().pragma(.userVersion))?.intValue == 9)
    migrated.close()
}
