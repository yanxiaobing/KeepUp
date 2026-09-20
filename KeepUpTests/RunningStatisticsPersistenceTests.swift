import Foundation
import Testing
import WCDBSwift
@testable import KeepUp

/// Schema 10 deliberately has no duration column; migration must add it from the saved session.
private struct StatisticsLegacyEntryRow: TableCodable {
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
    enum CodingKeys: String, CodingTableKey {
        typealias Root = StatisticsLegacyEntryRow
        case id, cardID, day, timeZoneID, createdAt, quantity, unit, note, runningKind, runningKilocalories
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

@Test func schemaTenMigrationAddsDurationWithoutRecomputingFrozenEnergy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpStatsMigration-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var session = RunningSession(id: "recorded", startedAt: start, timeZone: TimeZone(secondsFromGMT: 0)!, kind: .indoor)
    session.weightKilograms = 60
    session.energyAlgorithmVersion = RunningMetrics.energyAlgorithmVersion
    session.appendIndoor(distance: 150, steps: 200, from: start, to: start.addingTimeInterval(60), now: start.addingTimeInterval(60))
    session.finish(at: start.addingTimeInterval(60))
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories != nil)
    #expect(RunningMetrics(session: session).estimatedEnergyKilocalories != 42.6)
    let database = Database(at: url.path)
    try database.create(table: StoreTables.entries.name, of: StatisticsLegacyEntryRow.self)
    try database.create(table: StoreTables.running.name, of: RunningRow.self)
    let recorded = StatisticsLegacyEntryRow(id: session.id, cardID: session.kind.cardID, day: session.day.rawValue,
        timeZoneID: session.timeZoneID, createdAt: start.timeIntervalSince1970, quantity: 0.15,
        unit: "kilometers", note: "", runningKind: "indoor", runningKilocalories: 42.6)
    var manual = recorded; manual.id = "manual"; manual.runningKind = nil; manual.runningKilocalories = nil
    // Orphan legacy summary remains unknown; migration must not invent a duration.
    var missing = recorded; missing.id = "missing-session"; missing.runningKilocalories = nil
    try database.insert([recorded, manual, missing], intoTable: StoreTables.entries.name)
    try database.insert(RunningRow(session), intoTable: StoreTables.running.name)
    try database.exec(StatementPragma().pragma(.userVersion).to(10))
    database.close()
    let store = LocalStore(fileURL: url)
    try await store.open()
    do {
        let snapshot = try await store.snapshot()
        let entry = try #require(snapshot.entries.first { $0.id == session.id })
        #expect(entry.runningElapsedSeconds == 60)
        #expect(entry.runningKilocalories == 42.6)
        #expect(snapshot.entries.first { $0.id == manual.id }?.runningElapsedSeconds == nil)
        #expect(snapshot.entries.first { $0.id == missing.id }?.runningElapsedSeconds == nil)
        let summary = RunningStatistics(entries: snapshot.entries)
        #expect(summary.count == 2)
        #expect(summary.distanceMeters == 300)
        #expect(summary.elapsedSeconds == 60)
        #expect(summary.kilocalories == 43)
        #expect(summary.missingDurationCount == 1)
        #expect(summary.missingEnergyCount == 1)
        #expect(summary.averagePaceSecondsPerKilometer == nil)
        await store.close()
        try await store.open()
        #expect(try await store.snapshot().entries == snapshot.entries)
        try await store.delete(id: session.id)
        let afterDeletion = RunningStatistics(entries: try await store.snapshot().entries)
        #expect(afterDeletion.count == 1)
        #expect(afterDeletion.elapsedSeconds == 0)
        #expect(afterDeletion.kilocalories == 0)
        #expect(afterDeletion.missingDurationCount == 1)
    } catch { await store.close(); throw error }
    await store.close()
}

@Test func runningStatisticsTotalsMatchSavedEntriesAfterFinishRetryAndDelete() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpStatsTotals-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    try await store.open()
    do {
        for kind in RunningKind.allCases {
            let session = RunningDetailFixtures.make(kind: kind)
            try await store.finishRunning(session)
            try await store.finishRunning(session)
        }
        let snapshot = try await store.snapshot()
        let stats = RunningStatistics(entries: snapshot.entries)
        #expect(stats.count == 3)
        #expect(abs(stats.distanceMeters - 12_750) < 0.01)
        #expect(stats.missingDurationCount == 0)
        #expect(stats.missingEnergyCount == 0)
        #expect(stats.elapsedSeconds == snapshot.entries.compactMap(\.runningElapsedSeconds).reduce(0, +))
        let timelineEnergy = snapshot.entries.reduce(0) { sum, entry in
            sum + (snapshot.cards.first { $0.id == entry.cardID }.flatMap { ActivityEnergy.calories(entry: entry, card: $0) } ?? 0)
        }
        #expect(stats.kilocalories == timelineEnergy)
        let indoor = try #require(snapshot.entries.first { $0.runningKind == .indoor })
        try await store.delete(id: indoor.id)
        await store.close()
        try await store.open()
        let after = RunningStatistics(entries: try await store.snapshot().entries)
        #expect(after.count == 2)
        #expect(abs(after.distanceMeters - 8_500) < 0.01)
        #expect(after.kilocalories == stats.kilocalories - (RunningMetrics.roundedEnergy(indoor.runningKilocalories) ?? 0))
        #expect(after.elapsedSeconds == stats.elapsedSeconds - (indoor.runningElapsedSeconds ?? 0))
    } catch { await store.close(); throw error }
    await store.close()
}
