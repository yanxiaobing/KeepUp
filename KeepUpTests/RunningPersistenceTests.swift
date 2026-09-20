import Foundation
import Testing
@testable import KeepUp

private let persistedRunStart = Date(timeIntervalSince1970: 1_800_000_000)
private let persistedRunZone = TimeZone(identifier: "Asia/Shanghai")!

private func runningDraftForStorage(id: String = "running." + UUID().uuidString) -> RunningSession {
    var session = RunningSession(id: id, startedAt: persistedRunStart, timeZone: persistedRunZone)
    for index in 0...12 {
        let date = persistedRunStart.addingTimeInterval(Double(index))
        let point = RunningPoint(latitude: 31 + Double(index) * 0.0001, longitude: 121,
                                 horizontalAccuracy: 5, timestamp: date, speed: 11)
        session.append(point, now: date)
    }
    return session
}

private func withRunningStore(_ action: (LocalStore, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpRunning-\(UUID())")
    let url = directory.appendingPathComponent("store.sqlite")
    let store = LocalStore(fileURL: url)
    defer { try? FileManager.default.removeItem(at: directory) }
    do { try await store.open(); try await action(store, url) }
    catch { await store.close(); throw error }
    await store.close()
}

@Test func runningDraftSurvivesReopenAndRejectsOlderRevisionEvenWithNewerWallClock() async throws {
    try await withRunningStore { store, url in
        let first = runningDraftForStorage()
        try await store.saveRunningSession(first)
        await store.close()
        try await store.open()
        #expect(try await store.snapshot().activeRun == first)
        #expect(try await store.runningSession(id: first.id) == first)
        var recovered = try #require(try await store.snapshot().activeRun)
        recovered.recover()
        try await store.saveRunningSession(recovered)
        var stale = first
        stale.updatedAt = persistedRunStart.addingTimeInterval(100)
        try await store.saveRunningSession(stale)
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        let snapshot = try await reopened.snapshot()
        await reopened.close()
        #expect(snapshot.activeRun == recovered)
        #expect(snapshot.activeRun?.phase == .paused)
        #expect(snapshot.activeRun?.elapsedSeconds == 12)
        #expect(snapshot.entries.isEmpty)
    }
}

@Test func runningFinishAtomicallyCreatesOneEntryAndConsumesItsPlan() async throws {
    try await withRunningStore { store, _ in
        let draft = runningDraftForStorage()
        let plan = ScheduledCard(cardID: "punchcard.2", day: draft.day, note: "沿河慢跑")
        try await store.saveSchedule(plan, now: persistedRunStart.addingTimeInterval(-172_800))
        try await store.saveRunningSession(draft)
        var finished = draft
        finished.finish(at: persistedRunStart.addingTimeInterval(20))
        try await store.finishRunning(finished)
        try await store.finishRunning(finished)
        // Even a checkpoint with a numerically newer revision cannot revive a completed run.
        var delayed = draft
        delayed.revision = finished.revision + 1
        try await store.saveRunningSession(delayed)
        let snapshot = try await store.snapshot()
        let entry = try #require(snapshot.entries.first)
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.activeRun == nil)
        #expect(snapshot.schedules.isEmpty)
        #expect(entry.id == draft.id)
        #expect(entry.cardID == "punchcard.2")
        #expect(entry.day == draft.day)
        #expect(entry.timeZoneID == persistedRunZone.identifier)
        #expect(entry.quantity == finished.distanceMeters / 1_000)
        #expect(entry.unit == .kilometers)
        #expect(entry.note == "沿河慢跑")
        #expect(try await store.runningSession(id: draft.id) == finished)
    }
}

@Test func deletingRunningHistoryPreventsDelayedCheckpointsAndFinishesFromRecreatingIt() async throws {
    try await withRunningStore { store, _ in
        var draft = runningDraftForStorage()
        try await store.saveRunningSession(draft)
        var finished = draft
        finished.finish(at: persistedRunStart.addingTimeInterval(20))
        try await store.finishRunning(finished)
        try await store.delete(id: draft.id)
        draft.revision = finished.revision + 10
        try await store.saveRunningSession(draft)
        finished.revision = draft.revision + 1
        await #expect(throws: StoreError.invalidContent) { try await store.finishRunning(finished) }
        #expect(try await store.runningSession(id: draft.id) == nil)
        #expect(try await store.snapshot().activeRun == nil)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}

@Test func discardedDraftCannotReturnAndDoesNotBlockANewSession() async throws {
    try await withRunningStore { store, _ in
        var discarded = runningDraftForStorage()
        try await store.saveRunningSession(discarded)
        try await store.discardRunning(id: discarded.id)
        try await store.discardRunning(id: discarded.id)
        discarded.revision += 10
        try await store.saveRunningSession(discarded)
        var finished = discarded
        finished.finish(at: persistedRunStart.addingTimeInterval(20))
        await #expect(throws: StoreError.invalidContent) { try await store.finishRunning(finished) }
        #expect(try await store.runningSession(id: discarded.id) == nil)
        let next = runningDraftForStorage()
        try await store.saveRunningSession(next)
        #expect(try await store.snapshot().activeRun?.id == next.id)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}

@Test func discardBeforeFirstCheckpointPersistsATombstoneAcrossReopen() async throws {
    try await withRunningStore { store, _ in
        let neverSaved = runningDraftForStorage()
        try await store.discardRunning(id: neverSaved.id)
        await store.close()
        try await store.open()
        try await store.saveRunningSession(neverSaved)
        var finished = neverSaved
        finished.finish(at: persistedRunStart.addingTimeInterval(20))
        await #expect(throws: StoreError.invalidContent) { try await store.finishRunning(finished) }
        #expect(try await store.runningSession(id: neverSaved.id) == nil)
        #expect(try await store.snapshot().activeRun == nil)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}

@Test func runningStoreRejectsSecondActiveSessionAndShortFinishWithoutLosingDraft() async throws {
    try await withRunningStore { store, _ in
        let active = RunningSession(startedAt: persistedRunStart, timeZone: persistedRunZone)
        try await store.saveRunningSession(active)
        let other = runningDraftForStorage()
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(other) }
        var tooShort = active
        tooShort.finish(at: persistedRunStart.addingTimeInterval(20))
        await #expect(throws: StoreError.invalidQuantity) { try await store.finishRunning(tooShort) }
        #expect(try await store.snapshot().activeRun == active)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}

@Test func runningStoreRejectsMalformedSplitsChronologyAndDatesWithoutReplacingValidDraft() async throws {
    try await withRunningStore { store, _ in
        var valid = RunningSession(startedAt: persistedRunStart, timeZone: persistedRunZone)
        for index in 0...200 {
            let date = persistedRunStart.addingTimeInterval(Double(index))
            let point = RunningPoint(latitude: 31 + Double(index) * 0.0001, longitude: 121,
                                     horizontalAccuracy: 5, timestamp: date, speed: 11)
            valid.append(point, now: date)
        }
        #expect(valid.splits.count == 2)
        try await store.saveRunningSession(valid)

        var discontinuousSplits = valid
        discontinuousSplits.revision += 1
        discontinuousSplits.splits[1].kilometer = 3
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(discontinuousSplits) }
        #expect(try await store.runningSession(id: valid.id) == valid)

        var negativeSplit = valid
        negativeSplit.revision += 1
        negativeSplit.splits[0].elapsedSeconds = -1
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(negativeSplit) }
        #expect(try await store.runningSession(id: valid.id) == valid)

        var reversedAcrossSegments = valid
        reversedAcrossSegments.revision += 1
        let points = try #require(valid.segments.first)
        // Each segment is internally ordered, but the second starts before the first ends.
        reversedAcrossSegments.segments = [Array(points.prefix(101)), Array(points.dropFirst(99))]
        await #expect(throws: StoreError.invalidContent) { try await store.saveRunningSession(reversedAcrossSegments) }
        #expect(try await store.runningSession(id: valid.id) == valid)

        var invalidCheckpointDate = valid
        invalidCheckpointDate.revision += 1
        invalidCheckpointDate.updatedAt = valid.startedAt.addingTimeInterval(-1)
        await #expect(throws: StoreError.invalidDate) { try await store.saveRunningSession(invalidCheckpointDate) }
        #expect(try await store.snapshot().activeRun == valid)
        #expect(try await store.snapshot().entries.isEmpty)
    }
}
