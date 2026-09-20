import Foundation
import Testing
import WCDBSwift
@testable import KeepUp

private let metricsStorageStart = Date(timeIntervalSince1970: 1_800_000_000)

private func measuredIndoorSession() -> RunningSession {
    var session = RunningSession(startedAt: metricsStorageStart, kind: .indoor)
    session.weightKilograms = 60
    session.energyAlgorithmVersion = RunningMetrics.energyAlgorithmVersion
    for index in 1...12 {
        let start = metricsStorageStart.addingTimeInterval(Double(index - 1) * 5)
        let end = start.addingTimeInterval(5)
        session.appendIndoor(distance: 10, steps: 15, from: start, to: end, now: end)
    }
    session.finish(at: metricsStorageStart.addingTimeInterval(60))
    return session
}

@Test func recordedEnergyAndMeasurementsSurviveContentChangesProfileChangesAndReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpMetrics-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    try await store.open()
    do {
        let session = measuredIndoorSession()
        try await store.finishRunning(session)
        var profile = UserProfile(); profile.weight = 90
        try await store.saveProfile(profile)
        try await store.saveContent(entryID: session.id, content: EntryContent(text: "雨天室内跑", photo: Data([1, 2, 3])), asDraft: false)
        await store.close()
        try await store.open()
        let snapshot = try await store.snapshot()
        let entry = try #require(snapshot.entries.first)
        let card = try #require(snapshot.cards.first { $0.id == session.kind.cardID })
        #expect(entry.runningKind == .indoor)
        #expect(entry.runningElapsedSeconds == session.elapsedSeconds)
        #expect(entry.runningKilocalories == RunningMetrics(session: session).estimatedEnergyKilocalories)
        #expect(ActivityEnergy.calories(entry: entry, card: card) == RunningMetrics(session: session).roundedEnergyKilocalories)
        #expect(snapshot.profile?.weight == 90)
        #expect(snapshot.publishedContent(for: entry).text == "雨天室内跑")
        #expect(try await store.runningSession(id: session.id) == session)
        #expect(snapshot.activeRun == nil)
        try await store.delete(id: session.id)
        let deleted = try await store.snapshot()
        #expect(deleted.entries.isEmpty)
        #expect(deleted.content[session.id] == nil)
        #expect(try await store.runningSession(id: session.id) == nil)
    } catch { await store.close(); throw error }
    await store.close()
}

private struct LegacyMetricsEntryRow: TableCodable {
    var id: String
    var cardID: String
    var day: String
    var timeZoneID: String
    var createdAt: Double
    var quantity: Double?
    var unit: String
    var note: String
    enum CodingKeys: String, CodingTableKey {
        typealias Root = LegacyMetricsEntryRow
        case id, cardID, day, timeZoneID, createdAt, quantity, unit, note
        nonisolated(unsafe) static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
        }
    }
}

@Test func schemaNineMigrationKeepsLegacyWorkoutEnergyUnknownAndManualEstimatesUnchanged() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpMetricsMigration-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    var oldSession = measuredIndoorSession()
    oldSession.weightKilograms = nil
    oldSession.energyAlgorithmVersion = nil
    oldSession.indoorSegments = []
    let database = Database(at: url.path)
    try database.create(table: StoreTables.entries.name, of: LegacyMetricsEntryRow.self)
    try database.create(table: StoreTables.running.name, of: RunningRow.self)
    let oldEntry = LegacyMetricsEntryRow(id: oldSession.id, cardID: "punchcard.2", day: oldSession.day.rawValue,
                                        timeZoneID: oldSession.timeZoneID, createdAt: metricsStorageStart.timeIntervalSince1970,
                                        quantity: oldSession.distanceMeters / 1_000, unit: "kilometers", note: "旧记录")
    var manual = oldEntry; manual.id = "manual-running"
    try database.insert([oldEntry, manual], intoTable: StoreTables.entries.name)
    try database.insert(RunningRow(oldSession), intoTable: StoreTables.running.name)
    try database.exec(StatementPragma().pragma(.userVersion).to(9))
    database.close()
    let store = LocalStore(fileURL: url)
    try await store.open()
    do {
        let snapshot = try await store.snapshot()
        let recorded = try #require(snapshot.entries.first { $0.id == oldSession.id })
        let manualEntry = try #require(snapshot.entries.first { $0.id == manual.id })
        let card = try #require(snapshot.cards.first { $0.id == "punchcard.2" })
        #expect(recorded.runningKind == .indoor)
        #expect(recorded.runningElapsedSeconds == oldSession.elapsedSeconds)
        #expect(manualEntry.runningElapsedSeconds == nil)
        #expect(recorded.runningKilocalories == nil)
        #expect(ActivityEnergy.calories(entry: recorded, card: card) == nil)
        #expect(manualEntry.runningKind == nil)
        #expect(ActivityEnergy.calories(entry: manualEntry, card: card) == ActivityEnergy.calories(card: card, quantity: manualEntry.quantity))
        #expect(try await store.runningSession(id: oldSession.id) == oldSession)
        await store.close()
        try await store.open()
        #expect(try await store.snapshot().entries == snapshot.entries)
    } catch { await store.close(); throw error }
    await store.close()
}

@MainActor private final class MetricsCaptureGPS: RunningLocationSource {
    var authorization = RunningAuthorization.authorized
    var onEvent: (@MainActor (RunningLocationEvent) -> Void)?
    func start(background: Bool) {}
    func stop() {}
    func requestPermission() {}
}

@Test @MainActor func recordingCapturesWeightAtStartAndDoesNotReplaceItOnResume() async {
    let controller = RunningController(source: MetricsCaptureGPS())
    var weight = 60.0
    controller.configure(checkpoint: { _ in true }, finish: { _ in true }, discard: { _ in true }, weight: { weight })
    await controller.start()
    #expect(controller.session?.weightKilograms == 60)
    #expect(controller.session?.energyAlgorithmVersion == RunningMetrics.energyAlgorithmVersion)
    await controller.pause()
    weight = 80
    await controller.resume()
    #expect(controller.session?.weightKilograms == 60)
    await controller.discard()
    await controller.start()
    #expect(controller.session?.weightKilograms == 80)
    await controller.discard()
}

@Test func malformedSamplesAndChangesToCapturedWeightCannotReplaceStoredMeasurements() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpMetricsValidation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    try await store.open()
    do {
        var valid = measuredIndoorSession()
        valid.phase = .paused; valid.finishedAt = nil
        try await store.saveRunningSession(valid)
        var invalid = valid
        invalid.revision += 1
        invalid.weightKilograms = 80
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(invalid) }
        invalid = valid
        invalid.revision += 1
        invalid.indoorSegments[0][1].distanceMeters = valid.distanceMeters + 1
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(invalid) }
        invalid = valid
        invalid.revision += 1
        invalid.indoorSegments[0][1].timestamp = valid.startedAt.addingTimeInterval(-1)
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(invalid) }
        #expect(try await store.runningSession(id: valid.id) == valid)
    } catch { await store.close(); throw error }
    await store.close()
}
