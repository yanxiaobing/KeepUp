import Foundation
import Testing
@testable import KeepUp

private actor SuspendedRepository: CheckInRepository {
    private var entries: [CheckInEntry] = []
    private var shouldSuspend = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var gateObserver: CheckedContinuation<Void, Never>?

    func open() { }
    func snapshot() async -> LocalSnapshot {
        let result = LocalSnapshot(cards: HabitCard.starters, entries: entries)
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
