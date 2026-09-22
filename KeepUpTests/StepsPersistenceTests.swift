import Foundation
import Testing
import WCDBSwift
@testable import KeepUp

private let stepNow = Date(timeIntervalSince1970: 1_789_516_800)
private let stepZone = "Asia/Shanghai"
private func measuredSteps(_ count: Int, offset: Double = 0) -> StepReading {
    let time = stepNow.addingTimeInterval(offset)
    return StepReading(day: LocalDay(date: stepNow, timeZone: TimeZone(identifier: stepZone)!),
                       timeZoneID: stepZone, steps: count, distance: Double(count) * 0.6, measuredAt: time)
}
private func withStepsStore(_ action: (LocalStore, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpSteps-\(UUID())")
    let url = directory.appendingPathComponent("store.sqlite")
    let store = LocalStore(fileURL: url)
    defer { try? FileManager.default.removeItem(at: directory) }
    do { try await store.open(); try await action(store, url) }
    catch { await store.close(); throw error }
    await store.close()
}

@Test func stepsOnlyCompleteAtGoalAndKeepOneDailyRecord() async throws {
    try await withStepsStore { store, url in
        let day = measuredSteps(0).day
        try await store.saveSteps(measuredSteps(0), goal: 5_000, now: stepNow)
        #expect(try await store.snapshot().entries.isEmpty)
        try await store.saveSteps(measuredSteps(4_999, offset: 1), goal: 5_000, now: stepNow.addingTimeInterval(10))
        #expect(try await store.snapshot().entries.isEmpty)
        try await store.saveSteps(measuredSteps(5_000, offset: 2), goal: 5_000, now: stepNow.addingTimeInterval(10))
        let entry = try #require(try await store.snapshot().entries.first)
        try await store.saveContent(entryID: entry.id, content: EntryContent(text: "Keep this note"), asDraft: false)
        try await store.saveSteps(measuredSteps(6_000, offset: 3), goal: 10_000, now: stepNow.addingTimeInterval(10))
        try await store.saveSteps(measuredSteps(1_000, offset: 1), goal: 10_000, now: stepNow.addingTimeInterval(10))
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        let snapshot = try await reopened.snapshot()
        await reopened.close()
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.id == entry.id)
        #expect(snapshot.entries.first?.quantity == 6_000)
        #expect(snapshot.entries.first?.note == "Keep this note")
        #expect(snapshot.content[entry.id]?.published?.text == "Keep this note")
        #expect(snapshot.steps[day.rawValue]?.goal == 5_000)
        #expect(snapshot.steps[day.rawValue]?.distance == 3_600)
    }
}

@Test func stepGoalCanBeSetAfterFirstReadingAndDaysRemainIndependent() async throws {
    try await withStepsStore { store, _ in
        let today = measuredSteps(6_000)
        try await store.saveSteps(today, goal: nil, now: stepNow)
        #expect(try await store.snapshot().entries.isEmpty)
        try await store.saveSteps(today, goal: 5_000, now: stepNow)
        let yesterday = StepReading(day: LocalDay(date: stepNow.addingTimeInterval(-86400), timeZone: TimeZone(identifier: stepZone)!), timeZoneID: stepZone,
                                    steps: 7_000, distance: nil, measuredAt: stepNow.addingTimeInterval(-86400))
        try await store.saveSteps(yesterday, goal: 5_000, now: stepNow)
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.steps.count == 2)
        let entry = try #require(snapshot.entries.first { $0.day == today.day })
        try await store.delete(id: entry.id)
        #expect(try await store.snapshot().entries.count == 1)
        try await store.saveSteps(measuredSteps(8_000, offset: 1), goal: 5_000, now: stepNow.addingTimeInterval(2))
        #expect(try await store.snapshot().entries.count == 1)
        #expect(try await store.snapshot().steps[today.day.rawValue]?.checkInDeleted == true)
        #expect(try await store.snapshot().steps[today.day.rawValue]?.steps == 8_000)
        // Deleting a check-in doesn't erase the device's measurement history.
        #expect(try await store.snapshot().steps.count == 2)
    }
}

@Test func stepsRejectInvalidMeasurementsAndGenericManualInput() async throws {
    try await withStepsStore { store, _ in
        await #expect(throws: StoreError.invalidQuantity) { try await store.saveSteps(measuredSteps(-1), goal: 5_000, now: stepNow) }
        await #expect(throws: StoreError.invalidQuantity) { try await store.saveSteps(measuredSteps(100), goal: 5_500, now: stepNow) }
        await #expect(throws: StoreError.invalidDate) { try await store.saveSteps(measuredSteps(100, offset: 1), goal: 5_000, now: stepNow) }
        let draft = CheckInDraft(cardID: "punchcard.1", day: measuredSteps(1).day, timeZoneID: stepZone, quantity: 10_000, note: "")
        await #expect(throws: StoreError.invalidCard) { try await store.add(draft, now: stepNow) }
        let snapshot = try await store.snapshot()
        #expect(snapshot.steps.isEmpty)
    }
}

@Test func schemaSixUpgradeAddsMeasurementsWithoutChangingExistingRecords() async throws {
    try await withStepsStore { store, url in
        let draft = CheckInDraft(cardID: "preset.exercise", day: measuredSteps(1).day, timeZoneID: stepZone, quantity: 20, note: "Legacy")
        try await store.add(draft, now: stepNow)
        await store.close()
        let database = Database(at: url.path)
        try database.exec(StatementDropTable().drop(table: "step_records"))
        try database.exec(StatementPragma().pragma(.userVersion).to(6))
        database.close()
        try await store.open()
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.first?.note == "Legacy")
        #expect(snapshot.steps.isEmpty)
        try await store.saveSteps(measuredSteps(5000), goal: 5000, now: stepNow)
        #expect(try await store.snapshot().entries.count == 2)
    }
}

@Test func intradaySurvivesLiveTotalsReopenAndRejectsInvalidBins() async throws {
    try await withStepsStore { store, url in
        var reading = measuredSteps(6000)
        let zone = TimeZone(identifier: stepZone)!
        let ranges = StepIntraday.ranges(day: reading.day, through: reading.measuredAt, timeZone: zone)
        reading.intraday = StepIntraday(intervals: ranges.map { StepInterval(start: $0.start, end: $0.end, steps: 10) }, measuredThrough: reading.measuredAt)
        try await store.saveSteps(reading, goal: 5000, now: stepNow)
        try await store.saveSteps(measuredSteps(6500, offset: 2), goal: 5000, now: stepNow.addingTimeInterval(3))
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        // A late detail query must enrich the latest total, never roll it back.
        var lateDetail = reading
        let nextThrough = reading.measuredAt.addingTimeInterval(1)
        lateDetail.intraday = StepIntraday(intervals: StepIntraday.ranges(day: reading.day, through: nextThrough, timeZone: zone).map {
            StepInterval(start: $0.start, end: $0.end, steps: 20)
        }, measuredThrough: nextThrough)
        lateDetail = StepReading(day: reading.day, timeZoneID: stepZone, steps: 6100, distance: nil, measuredAt: nextThrough, intraday: lateDetail.intraday)
        try await reopened.saveSteps(lateDetail, goal: 5000, now: stepNow.addingTimeInterval(3))
        let snapshot = try await reopened.snapshot()
        #expect(snapshot.steps[reading.day.rawValue]?.intraday == lateDetail.intraday)
        #expect(snapshot.steps[reading.day.rawValue]?.steps == 6500)
        var invalid = measuredSteps(7000, offset: 3)
        invalid.intraday = StepIntraday(intervals: [], measuredThrough: invalid.measuredAt)
        await #expect(throws: StoreError.invalidQuantity) { try await reopened.saveSteps(invalid, goal: 5000, now: stepNow.addingTimeInterval(4)) }
        await reopened.close()
    }
}
