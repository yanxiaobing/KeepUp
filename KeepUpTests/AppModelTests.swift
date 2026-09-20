import Foundation
import Testing
@testable import KeepUp

private actor SuspendedRepository: CheckInRepository {
    private var entries: [CheckInEntry] = []
    private var shouldSuspend = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var gateObserver: CheckedContinuation<Void, Never>?
    private var activeRun: RunningSession?
    private var finishedRuns: [String: RunningSession] = [:]
    private var failRunningFinish = false

    func open() { }
    func snapshot() async -> LocalSnapshot {
        let result = LocalSnapshot(cards: HabitCard.starters, entries: entries, activeRun: activeRun)
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation in
                suspended = continuation
                gateObserver?.resume()
                gateObserver = nil
            }
        }
        return result
    }
    func add(_ draft: CheckInDraft, now: Date) {
        entries.append(CheckInEntry(id: draft.id, cardID: draft.cardID, day: draft.day,
                                    timeZoneID: draft.timeZoneID, createdAt: now, quantity: nil, unit: .none, note: draft.note))
    }
    func saveContent(entryID: String, content: EntryContent?, asDraft: Bool) async throws {}
    func discardContentDraft(entryID: String) async throws {}
    func createCustomCard(_ draft: CustomCardDraft) async throws -> String { draft.id }
    func archiveCustomCard(id: String) async throws {}
    func saveWeightTarget(_ target: WeightTarget, now: Date) async throws {}
    func saveSchedule(_ value: ScheduledCard, now: Date) async throws {}
    func deleteSchedule(id: String) async throws {}
    func runningSession(id: String) async throws -> RunningSession? { finishedRuns[id] }
    func saveRunningSession(_ session: RunningSession) async throws { activeRun = session }
    func finishRunning(_ session: RunningSession) async throws {
        if failRunningFinish { throw StoreError.invalidContent }
        if finishedRuns[session.id] == nil {
            finishedRuns[session.id] = session
            entries.append(CheckInEntry(id: session.id, cardID: session.kind.cardID, day: session.day,
                                        timeZoneID: session.timeZoneID, createdAt: session.startedAt,
                                        quantity: session.distanceMeters / 1_000, unit: .kilometers, note: ""))
        }
        activeRun = nil
    }
    func discardRunning(id: String) async throws { activeRun = nil }
    func setActiveRun(_ session: RunningSession?) { activeRun = session }
    func setRunningFinishFailure(_ value: Bool) { failRunningFinish = value }
    func saveSteps(_ reading: StepReading, goal: Int?, now: Date) async throws {}
    func saveTarget(_ target: CardTarget) async throws {}
    func saveProfile(_ profile: UserProfile) async throws {}
    func updateProfile(_ change: ProfileChange, now: Date) async throws {}

    func delete(id: String) { entries.removeAll { $0.id == id } }
    func suspendNextSnapshot() { shouldSuspend = true }
    func waitForSuspension() async {
        if suspended != nil { return }
        await withCheckedContinuation { gateObserver = $0 }
    }
    func resumeSnapshot() { suspended?.resume(); suspended = nil }
}

@Test @MainActor
func savingDuringRefreshDoesNotLeaveAnOutdatedScreen() async {
    let repository = SuspendedRepository()
    let model = AppModel(repository: repository)
    await model.load()
    await repository.suspendNextSnapshot()
    let refresh = Task { await model.load() }
    await repository.waitForSuspension()
    let draft = CheckInDraft(cardID: "preset.fruit", day: LocalDay(date: .now), timeZoneID: "UTC", quantity: nil, note: "New")
    #expect(await model.add(draft))
    await repository.resumeSnapshot()
    await refresh.value
    #expect(model.snapshot.entries.map(\.id) == [draft.id])
}

@Test @MainActor
func runningRecoveryDoesNotReviveDiscardedSessionOnLaterRefresh() async {
    let repository = SuspendedRepository()
    var draft = RunningSession(startedAt: .now.addingTimeInterval(-30))
    draft.updatedAt = draft.startedAt.addingTimeInterval(10)
    await repository.setActiveRun(draft)
    let model = AppModel(repository: repository)
    await model.load()
    #expect(model.running.session?.id == draft.id)
    #expect(model.running.session?.phase == .paused)
    #expect(model.running.session?.elapsedSeconds == 10)
    await model.running.discard()
    #expect(model.running.session == nil)
    // A stale snapshot arriving after the user discarded must not act as a new launch recovery.
    await repository.setActiveRun(draft)
    await model.load()
    #expect(model.running.session == nil)
}

@Test @MainActor
func runningRepositoryFailureRetainsFinalSessionUntilSuccessfulRetry() async throws {
    let repository = SuspendedRepository()
    var draft = RunningSession(startedAt: .now.addingTimeInterval(-30))
    draft.updatedAt = draft.startedAt.addingTimeInterval(10)
    draft.distanceMeters = 120
    await repository.setActiveRun(draft)
    await repository.setRunningFinishFailure(true)
    let model = AppModel(repository: repository)
    await model.load()
    await model.running.finish()
    let frozen = try #require(model.running.session)
    #expect(frozen.phase == .finished)
    #expect(frozen.elapsedSeconds == 10)
    #expect(model.running.errorKey == "running.saveFailed")
    #expect(model.running.lastFinishedSession == nil)
    #expect(model.snapshot.entries.isEmpty)

    await repository.setRunningFinishFailure(false)
    await model.running.finish()
    #expect(model.running.session == nil)
    #expect(model.running.lastFinishedSession == frozen)
    #expect(model.running.errorKey == nil)
    #expect(model.snapshot.entries.map(\.id) == [draft.id])
    #expect(try await model.runningSession(id: draft.id) == frozen)
}
