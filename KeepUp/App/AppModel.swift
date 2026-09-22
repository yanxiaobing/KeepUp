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
    #if DEBUG
    private var preparedUIFixtures = false
    #endif
    let running = RunningController()
    let runningVoice = RunningVoiceCoach()

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
        }, weight: { [weak self] in
            guard let self else { return nil }
            return self.snapshot.entries.first { $0.cardID == "punchcard.50" }?.quantity ?? self.snapshot.profile?.weight
        })
        running.onEvent = { [weak self] event in
            guard let self else { return }
            self.runningVoice.handle(event, settings: Defaults[.runningSettings], locale: self.runningLocale)
        }
    }

    private var runningLocale: Locale { (AppLanguage(rawValue: Defaults[.appLanguage]) ?? .system).locale }

    func refreshRunningSettings() {
        running.settingsDidChange()
        runningVoice.update(settings: Defaults[.runningSettings], locale: runningLocale)
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
                #if DEBUG
                if !preparedUIFixtures {
                    preparedUIFixtures = true
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-ui-testing"), args.contains("-reset-test-data"), args.contains("-ui-testing-skip-onboarding") {
                        for target in CardTarget.registrationDefaults { try await repository.saveTarget(target) }
                    }
                    if args.contains("-ui-testing"), args.contains("-reset-test-data"),
                       let index = args.firstIndex(of: "-ui-testing-running-details"), args.indices.contains(index + 1),
                       let kind = RunningKind(rawValue: args[index + 1]) {
                        try await repository.finishRunning(RunningDetailFixtures.make(kind: kind))
                    }
                    if args.contains("-ui-testing"), args.contains("-reset-test-data"), args.contains("-ui-testing-history-collapse") {
                        for (id, text) in [("history.ui-long", (1...12).map { String(format: "Line %02d", $0) }.joined(separator: "\n")),
                                           ("history.ui-short", "Short note")] {
                            try await repository.add(CheckInDraft(id: id, cardID: "preset.exercise", day: LocalDay(date: .now),
                                timeZoneID: TimeZone.current.identifier, quantity: 30, note: ""), now: .now)
                            try await repository.saveContent(entryID: id, content: EntryContent(text: text), asDraft: false)
                        }
                    }
                    if args.contains("-ui-testing"), args.contains("-reset-test-data"), args.contains("-ui-testing-entry-posters") {
                        try await EntryPosterFixtures.prepare(repository: repository)
                    }
                    if args.contains("-ui-testing"), args.contains("-reset-test-data"), args.contains("-ui-testing-calendar-scroll") {
                        for index in 0..<45 {
                            try await repository.add(CheckInDraft(id: "calendar.scroll.\(index)", cardID: "preset.exercise",
                                day: LocalDay(date: .now), timeZoneID: TimeZone.current.identifier,
                                quantity: 30, note: ""), now: Date.now.addingTimeInterval(Double(index)))
                        }
                    }
                }
                #endif
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
