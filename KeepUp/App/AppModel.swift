import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var snapshot = LocalSnapshot.empty
    private(set) var isReady = false
    private(set) var revision = 0
    private(set) var isLoading = false
    private(set) var loadError: String?
    var actionError: String?
    private let repository: any CheckInRepository
    private var reloadRequested = false
    private var hasRestoredRunning = false
    let running = RunningController()

    init(repository: any CheckInRepository) {
        self.repository = repository
        running.configure(checkpoint: { [weak self] session in
            guard let self else { return false }
            do { try await self.repository.saveRunningSession(session); return true }
            catch { return false }
        }, finish: { [weak self] session in
            guard let self else { return false }
            do { try await self.repository.finishRunning(session); await self.load(); return true }
            catch { return false }
        }, discard: { [weak self] id in
            guard let self else { return false }
            do { try await self.repository.discardRunning(id: id); await self.load(); return true }
            catch { return false }
        })
    }

    func runningSession(id: String) async throws -> RunningSession? {
        try await repository.runningSession(id: id)
    }

    func load() async {
        guard !isLoading else {
            reloadRequested = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadRequested = false
            do {
                try await repository.open()
                snapshot = try await repository.snapshot()
                revision += 1
                isReady = true
                loadError = nil
                if !hasRestoredRunning {
                    hasRestoredRunning = true
                    if let active = snapshot.activeRun { running.restore(active) }
                }
            } catch { loadError = (error as? StoreError)?.messageKey ?? "error.storage" }
        } while reloadRequested
    }

    func saveSteps(_ reading: StepReading) async -> Bool {
        do {
            try await repository.saveSteps(reading, goal: StepsGoal.value(on: reading.day), now: .now)
            await load()
            return true
        } catch {
            actionError = (error as? StoreError)?.messageKey ?? "error.storage"
            return false
        }
    }

    func add(_ draft: CheckInDraft) async -> Bool {
        do { try await repository.add(draft, now: .now) }
        catch {
            actionError = (error as? StoreError)?.messageKey ?? "error.storage"
            return false
        }
        await load()
        return true
    }

    func delete(_ entry: CheckInEntry) async {
        do {
            try await repository.delete(id: entry.id)
            await load()
        } catch { actionError = "error.storage" }
    }

    func saveProfile(_ profile: UserProfile) async -> Bool {
        do {
            try await repository.saveProfile(profile)
            await load()
            return true
        } catch {
            actionError = (error as? StoreError)?.messageKey ?? "error.storage"
            return false
        }
    }

    func saveContent(entryID: String, content: EntryContent?, asDraft: Bool = false) async -> Bool {
        do { try await repository.saveContent(entryID: entryID, content: content, asDraft: asDraft); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    func discardContentDraft(entryID: String) async -> Bool {
        do { try await repository.discardContentDraft(entryID: entryID); await load(); return true }
        catch { actionError = "error.storage"; return false }
    }
    func card(for entry: CheckInEntry) -> HabitCard? { snapshot.cards.first { $0.id == entry.cardID } }
    func createCustomCard(_ draft: CustomCardDraft) async -> String? {
        do { let id = try await repository.createCustomCard(draft); await load(); return id }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return nil }
    }
    func archiveCustomCard(id: String) async -> Bool {
        do { try await repository.archiveCustomCard(id: id); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    func saveTarget(_ target: CardTarget) async -> Bool {
        do { try await repository.saveTarget(target); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    func updateProfile(_ change: ProfileChange) async -> Bool {
        do { try await repository.updateProfile(change, now: .now); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    func saveWeightTarget(_ target: WeightTarget) async -> Bool {
        do { try await repository.saveWeightTarget(target, now: .now); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    var latestWeight: Double { snapshot.entries.filter { $0.cardID == "punchcard.50" }.first?.quantity ?? snapshot.profile?.weight ?? 60 }
    func saveSchedule(_ value: ScheduledCard) async -> Bool {
        do { try await repository.saveSchedule(value, now: .now); await load(); return true }
        catch { actionError = (error as? StoreError)?.messageKey ?? "error.storage"; return false }
    }
    func deleteSchedule(id: String) async -> Bool {
        do { try await repository.deleteSchedule(id: id); await load(); return true }
        catch { actionError = "error.storage"; return false }
    }
    func entries(on day: LocalDay) -> [CheckInEntry] { snapshot.entries.filter { $0.day == day } }
}
