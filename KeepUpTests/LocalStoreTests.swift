import Foundation
import Testing
import WCDBSwift
@testable import KeepUp

private func withStore(_ body: (LocalStore, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepUpTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("keepup.sqlite")
    let store = LocalStore(fileURL: url)
    do {
        try await store.open()
        try await body(store, url)
    } catch { await store.close(); throw error }
    await store.close()
}

private let fixtureNow = Date(timeIntervalSince1970: 1_789_516_800)
private func draft(id: String = UUID().uuidString, quantity: Double? = 30, cardID: String = "preset.exercise") -> CheckInDraft {
    CheckInDraft(id: id, cardID: cardID, day: LocalDay(rawValue: "2026-09-15")!, timeZoneID: "Asia/Shanghai",
                 quantity: quantity, note: "散步 · A good day 🌿")
}

@Test func initializationIsIdempotentAndRecordsSurviveReopen() async throws {
    try await withStore { store, url in
        let value = draft()
        try await store.add(value, now: fixtureNow)
        try await store.add(value, now: fixtureNow)
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        do {
            let snapshot = try await reopened.snapshot()
            #expect(snapshot.cards.count == OriginalCatalog.items.count)
            #expect(snapshot.entries.count == 1)
            #expect(snapshot.entries.first?.note == value.note)
            #expect(snapshot.entries.first?.day == value.day)
            #expect(snapshot.entries.first?.timeZoneID == "Asia/Shanghai")
            #expect(snapshot.entries.first?.createdAt == fixtureNow)
        } catch { await reopened.close(); throw error }
        await reopened.close()
    }
}

@Test func separateCheckInsOnSameDayAndDeletionRemainIndependent() async throws {
    try await withStore { store, _ in
        let first = draft(), second = draft()
        try await store.add(first, now: fixtureNow)
        try await store.add(second, now: fixtureNow)
        try await store.delete(id: first.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.map(\.id) == [second.id])
        #expect(snapshot.cards.count == OriginalCatalog.items.count)
    }
}

@Test(arguments: [0.0, -1, Double.infinity, Double.nan, 1_000_001])
func invalidNumericAmountsAreRejected(value: Double) async throws {
    try await withStore { store, _ in
        await #expect(throws: StoreError.invalidQuantity) { try await store.add(draft(quantity: value), now: fixtureNow) }
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.isEmpty)
    }
}

@Test func countRequiresWholeNumberAndCheckboxStoresNoQuantity() async throws {
    try await withStore { store, _ in
        await #expect(throws: StoreError.invalidQuantity) {
            try await store.add(draft(quantity: 1.5, cardID: "preset.pushUps"), now: fixtureNow)
        }
        try await store.add(draft(quantity: 999, cardID: "preset.fruit"), now: fixtureNow)
        #expect(try await store.snapshot().entries.first?.quantity == nil)
    }
}

@Test func futureDatesUnknownCardsAndOversizedNotesAreRejected() async throws {
    try await withStore { store, _ in
        let future = CheckInDraft(cardID: "preset.exercise", day: LocalDay(rawValue: "2099-01-01")!, timeZoneID: "UTC", quantity: 1, note: "")
        await #expect(throws: StoreError.invalidDate) { try await store.add(future, now: fixtureNow) }
        await #expect(throws: StoreError.invalidCard) { try await store.add(draft(cardID: "missing"), now: fixtureNow) }
        let long = CheckInDraft(cardID: "preset.exercise", day: LocalDay(rawValue: "2026-01-01")!, timeZoneID: "UTC", quantity: 1, note: String(repeating: "字", count: 1001))
        await #expect(throws: StoreError.noteTooLong) { try await store.add(long, now: fixtureNow) }
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.isEmpty)
    }
}

@Test func parallelCallersPreserveAllRecords() async throws {
    try await withStore { store, _ in
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<24 { group.addTask { try await store.add(draft(), now: fixtureNow) } }
            try await group.waitForAll()
        }
        #expect(try await store.snapshot().entries.count == 24)
    }
}

@Test func newerSchemaIsRejectedWithoutResettingDatabase() async throws {
    try await withStore { store, url in
        try await store.add(draft(id: "preserved"), now: fixtureNow)
        await store.close()
        let database = Database(at: url.path)
        try database.exec(StatementPragma().pragma(.userVersion).to(99))
        database.close()
        await #expect(throws: StoreError.newerSchema) { try await store.open() }
        let probe = Database(at: url.path)
        defer { probe.close() }
        #expect(try probe.getValue(from: StatementPragma().pragma(.userVersion))?.intValue == 99)
        let rows: [EntryRow] = try probe.getObjects(fromTable: "entries")
        #expect(rows.map(\.id) == ["preserved"])
    }
}

@Test func profileSurvivesReopenAndInvalidEditDoesNotReplaceIt() async throws {
    try await withStore { store, url in
        var profile = UserProfile()
        profile.nickname = "  KeepUp  "
        profile.isMale = true
        profile.year = 1991
        profile.height = 181.5
        profile.weight = 75.2
        profile.avatar = Data([1, 2, 3])
        try await store.saveProfile(profile)
        var invalid = profile; invalid.height = .nan
        await #expect(throws: StoreError.invalidProfile) { try await store.saveProfile(invalid) }
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        let saved = try await reopened.snapshot().profile
        let expected = try profile.validated()
        #expect(saved == expected)
        await reopened.close()
    }
}

@Test func schemaOneUpgradePreservesCheckInsAndStartsWithoutProfile() async throws {
    try await withStore { store, url in
        let record = draft()
        try await store.add(record, now: fixtureNow)
        await store.close()
        let database = Database(at: url.path)
        try database.exec(StatementDropTable().drop(table: "profile"))
        try database.exec(StatementPragma().pragma(.userVersion).to(1))
        database.close()
        let upgraded = LocalStore(fileURL: url)
        try await upgraded.open()
        let snapshot = try await upgraded.snapshot()
        #expect(snapshot.profile == nil)
        #expect(snapshot.entries.first?.id == record.id)
        try await upgraded.saveProfile(UserProfile())
        await upgraded.close()
    }
}

@Test func contentDraftPublishDiscardAndDeletionSurviveReopen() async throws {
    try await withStore { store, url in
        let first = draft(id: "first"), second = draft(id: "second")
        try await store.add(first, now: fixtureNow)
        try await store.add(second, now: fixtureNow)
        let published = EntryContent(text: "  A great walk 🌿  ", photo: Data([1,2,3]))
        try await store.saveContent(entryID: first.id, content: published, asDraft: false)
        try await store.saveContent(entryID: first.id, content: EntryContent(text: "Unfinished"), asDraft: true)
        await store.close()
        let reopened = LocalStore(fileURL: url)
        try await reopened.open()
        var snapshot = try await reopened.snapshot()
        #expect(snapshot.content[first.id]?.published?.text == "A great walk 🌿")
        #expect(snapshot.content[first.id]?.published?.photo == Data([1,2,3]))
        #expect(snapshot.content[first.id]?.draft?.text == "Unfinished")
        try await reopened.discardContentDraft(entryID: first.id)
        snapshot = try await reopened.snapshot()
        #expect(snapshot.content[first.id]?.draft == nil)
        #expect(snapshot.content[first.id]?.published?.photo == Data([1,2,3]))
        await #expect(throws: StoreError.invalidContent) {
            try await reopened.saveContent(entryID: first.id, content: EntryContent(text: String(repeating: "字", count: 1001)), asDraft: false)
        }
        #expect(try await reopened.snapshot().content[first.id]?.published?.text == "A great walk 🌿")
        try await reopened.saveContent(entryID: first.id, content: nil, asDraft: false)
        snapshot = try await reopened.snapshot()
        #expect(snapshot.entries.first(where: { $0.id == first.id })?.note == "")
        try await reopened.saveContent(entryID: first.id, content: published, asDraft: true)
        try await reopened.delete(id: first.id)
        snapshot = try await reopened.snapshot()
        #expect(snapshot.content[first.id] == nil)
        #expect(snapshot.entries.map(\.id) == [second.id])
        await #expect(throws: StoreError.corruptRecord) {
            try await reopened.saveContent(entryID: first.id, content: published, asDraft: false)
        }
        await reopened.close()
    }
}

@Test func profileFieldEditsMergeAndWeightCreatesOneRecord() async throws {
    try await withStore { store, _ in
        try await store.saveProfile(UserProfile())
        try await store.updateProfile(.nickname("Jamie"), now: fixtureNow)
        try await store.updateProfile(.height(178.5), now: fixtureNow)
        try await store.updateProfile(.weight(72.3), now: fixtureNow)
        let snapshot = try await store.snapshot()
        #expect(snapshot.profile?.nickname == "Jamie")
        #expect(snapshot.profile?.height == 178.5)
        #expect(snapshot.profile?.weight == 72.3)
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.cardID == "punchcard.50")
        #expect(snapshot.entries.first?.quantity == 72.3)
        await #expect(throws: StoreError.invalidProfile) { try await store.updateProfile(.weight(.nan), now: fixtureNow) }
        #expect(try await store.snapshot().entries.count == 1)
    }
}

@Test func schemaTwoUpgradePreservesProfileAndLegacyNotes() async throws {
    try await withStore { store, url in
        let item = draft()
        try await store.add(item, now: fixtureNow)
        try await store.saveProfile(UserProfile(nickname: "Jamie"))
        await store.close()
        let database = Database(at: url.path)
        try database.exec(StatementDropTable().drop(table: "entry_content"))
        try database.exec(StatementPragma().pragma(.userVersion).to(2))
        database.close()
        try await store.open()
        let snapshot = try await store.snapshot()
        #expect(snapshot.profile?.nickname == "Jamie")
        #expect(snapshot.entries.first?.id == item.id)
        #expect(snapshot.publishedContent(for: snapshot.entries[0]).text == item.note)
    }
}

@Test func customCardIdentityUnitsAndTargetsSurviveReopen() async throws {
    try await withStore { store, url in
        let custom = CustomCardDraft(name: "阅读", artwork: CustomCardDraft.artworks[2], unit: .minutes)
        let id = try await store.createCustomCard(custom)
        let duplicate = try await store.createCustomCard(.init(name: "阅读", artwork: custom.artwork, unit: .minutes))
        #expect(id == duplicate)
        let other = try await store.createCustomCard(.init(name: "阅读", artwork: custom.artwork, unit: .items))
        #expect(id != other)
        try await store.add(draft(quantity: 12, cardID: id), now: fixtureNow)
        var target = CardTarget(cardID: id); target.isPinned = true; target.showsProgress = true
        target.weekdays = [5, 1, 1, 3]
        try await store.saveTarget(target)
        target = try target.validated()
        await store.close(); try await store.open()
        let state = try await store.snapshot()
        #expect(state.cards.filter(\.isCustom).count == 2)
        #expect(state.cards.first(where: { $0.id == id })?.symbol == custom.artwork)
        #expect(state.entries.first?.quantity == 12)
        #expect(state.targets == [target])
        var invalid = target; invalid.reminderEnabled = true; invalid.weekdays = []
        await #expect(throws: StoreError.invalidTarget) { try await store.saveTarget(invalid) }
        #expect(try await store.snapshot().targets == [target])
        try await store.saveTarget(CardTarget(cardID: id))
        #expect(try await store.snapshot().targets.isEmpty)
        #expect(try await store.snapshot().entries.count == 1)
    }
}

@Test func invalidCustomCardsCannotChangeCatalog() async throws {
    try await withStore { store, _ in
        for name in ["", "abcdefghijk", "一二三四五六", "Two words", "Hello!", "Hi😀"] {
            await #expect(throws: StoreError.invalidCustomCard) {
                _ = try await store.createCustomCard(.init(name: name, artwork: CustomCardDraft.artworks[0], unit: .none))
            }
        }
        await #expect(throws: StoreError.invalidCustomCard) {
            _ = try await store.createCustomCard(.init(name: "Valid", artwork: "missing", unit: .none))
        }
        #expect(try await store.snapshot().cards.filter(\.isCustom).isEmpty)
        let id = try await store.createCustomCard(.init(name: "Count", artwork: CustomCardDraft.artworks[0], unit: .items))
        await #expect(throws: StoreError.invalidQuantity) { try await store.add(draft(quantity: 1.5, cardID: id), now: fixtureNow) }
        try await store.add(draft(quantity: 2, cardID: id), now: fixtureNow)
        #expect(try await store.snapshot().entries.first?.unit == .items)
    }
}

@Test func removingCustomCardPreservesHistoryAndRecreationRestoresIdentity() async throws {
    try await withStore { store, _ in
        let custom = CustomCardDraft(name: "Read", artwork: CustomCardDraft.artworks[1], unit: .minutes)
        let id = try await store.createCustomCard(custom)
        try await store.add(draft(quantity: 10, cardID: id), now: fixtureNow)
        var target = CardTarget(cardID: id); target.isPinned = true; target.reminderEnabled = true
        try await store.saveTarget(target)
        try await store.archiveCustomCard(id: id)
        await store.close(); try await store.open()
        let removed = try await store.snapshot()
        #expect(removed.archivedCardIDs == [id])
        #expect(removed.entries.count == 1)
        #expect(removed.cards.contains { $0.id == id })
        #expect(removed.targets.isEmpty)
        await #expect(throws: StoreError.invalidCard) { try await store.add(draft(quantity: 5, cardID: id), now: fixtureNow) }
        await #expect(throws: StoreError.invalidCard) { try await store.saveTarget(target) }
        let restoredID = try await store.createCustomCard(.init(name: custom.name, artwork: custom.artwork, unit: custom.unit))
        #expect(restoredID == id)
        #expect(try await store.snapshot().archivedCardIDs.isEmpty)
        #expect(try await store.snapshot().cards.filter(\.isCustom).count == 1)
        try await store.add(draft(quantity: 15, cardID: id), now: fixtureNow)
        #expect(try await store.snapshot().entries.count == 2)
        await #expect(throws: StoreError.invalidCard) { try await store.archiveCustomCard(id: "preset.exercise") }
    }
}

@Test func schedulesStaySeparateSurviveReopenAndCompleteAtomically() async throws {
    try await withStore { store, url in
        let now = Date.now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let day = LocalDay(date: tomorrow)
        let plan = ScheduledCard(cardID: "preset.exercise", day: day, note: "Morning gym")
        try await store.saveSchedule(plan, now: now)
        try await store.saveSchedule(ScheduledCard(cardID: plan.cardID, day: day, note: "Bring water"), now: now)
        var snapshot = try await store.snapshot()
        #expect(snapshot.schedules.count == 1)
        #expect(snapshot.entries.isEmpty)
        await store.close(); try await store.open()
        snapshot = try await store.snapshot()
        #expect(snapshot.schedules.first?.note == "Bring water")
        let value = CheckInDraft(cardID: plan.cardID, day: day, timeZoneID: TimeZone.current.identifier, quantity: 20, note: "")
        await #expect(throws: StoreError.invalidDate) { try await store.add(value, now: now) }
        #expect(try await store.snapshot().schedules.count == 1)
        try await store.add(value, now: tomorrow)
        try await store.add(value, now: tomorrow)
        snapshot = try await store.snapshot()
        #expect(snapshot.schedules.isEmpty)
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.note == "Bring water")
    }
}

@Test func schedulesValidateNotesAndRejectPastEditsWithoutLosingData() async throws {
    try await withStore { store, _ in
        let now = Date.now
        let future = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let plan = ScheduledCard(cardID: "preset.fruit", day: LocalDay(date: future), note: "Eat fruit")
        try await store.saveSchedule(plan, now: now)
        await #expect(throws: StoreError.invalidSchedule) { try await store.saveSchedule(plan, now: future) }
        await #expect(throws: StoreError.invalidSchedule) { try await store.saveSchedule(ScheduledCard(cardID: plan.cardID, day: plan.day, note: String(repeating: "🌱", count: 71)), now: now) }
        #expect(try await store.snapshot().schedules == [plan])
        try await store.deleteSchedule(id: plan.id)
        #expect(try await store.snapshot().schedules.isEmpty)
    }
}

@Test func wakeUpUsesActualTimeAndAllowsOnlyOneRecordPerCivilDay() async throws {
    try await withStore { store, _ in
        let late = ISO8601DateFormatter().date(from: "2026-09-17T10:00:00Z")!
        let selected = ISO8601DateFormatter().date(from: "2026-09-17T06:30:00Z")!
        let day = LocalDay(date: late, timeZone: .gmt)
        let value = CheckInDraft(wakeTime: selected, cardID: "punchcard.63", day: day, timeZoneID: "GMT", quantity: nil, note: "")
        try await store.add(value, now: late)
        try await store.add(value, now: late)
        var duplicate = value; duplicate.id = UUID().uuidString
        await #expect(throws: StoreError.duplicateWakeUp) { try await store.add(duplicate, now: late) }
        await store.close(); try await store.open()
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.wakeUps[value.id]?.time == selected)
        #expect(snapshot.wakeUps[value.id]?.isEarly == false)
        try await store.delete(id: value.id)
        #expect(try await store.snapshot().wakeUps.isEmpty)
        let early = selected
        try await store.add(value, now: early)
        #expect(try await store.snapshot().wakeUps[value.id]?.isEarly == true)
    }
}

@Test func wakeUpWindowAndCivilDayBoundaries() async throws {
    let formatter = ISO8601DateFormatter()
    for (time, expected) in [("2026-09-17T04:59:59Z", false), ("2026-09-17T05:00:00Z", true), ("2026-09-17T08:59:59Z", true), ("2026-09-17T09:00:00Z", false)] {
        let date = formatter.date(from: time)!
        #expect(WakeUpRecord(time: date, recordedAt: date, timeZoneID: "GMT").isEarly == expected)
    }
    try await withStore { store, _ in
        let now = formatter.date(from: "2026-09-17T07:00:00Z")!
        for time in [now.addingTimeInterval(60), now.addingTimeInterval(-86400)] {
            let value = CheckInDraft(wakeTime: time, cardID: "punchcard.63", day: LocalDay(date: now, timeZone: .gmt), timeZoneID: "GMT", quantity: nil, note: "")
            await #expect(throws: StoreError.invalidDate) { try await store.add(value, now: now) }
        }
    }
}

@Test func weightUpdatesOneDailyRecordAndPreservesContentOnRetry() async throws {
    try await withStore { store, _ in
        try await store.saveProfile(UserProfile(height: 175, weight: 70))
        let day = LocalDay(date: fixtureNow, timeZone: .gmt)
        let first = CheckInDraft(cardID: "punchcard.50", day: day, timeZoneID: "GMT", quantity: 70.1, note: "First weigh-in")
        try await store.add(first, now: fixtureNow)
        try await store.saveContent(entryID: first.id, content: EntryContent(text: "Keep this note"), asDraft: false)
        let second = CheckInDraft(cardID: "punchcard.50", day: day, timeZoneID: "GMT", quantity: 69.8, note: "")
        try await store.add(second, now: fixtureNow.addingTimeInterval(120))
        try await store.add(first, now: fixtureNow.addingTimeInterval(180))
        await store.close(); try await store.open()
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.id == first.id)
        #expect(snapshot.entries.first?.quantity == 69.8)
        #expect(snapshot.content[first.id]?.published?.text == "Keep this note")
        #expect(snapshot.profile?.weight == 69.8)
        #expect(snapshot.weights[first.id]?.height == 175)
        try await store.delete(id: first.id)
        #expect(try await store.snapshot().weights.isEmpty)
    }
}

@Test func weightTargetsSnapshotResetAndCompleteInBothDirections() async throws {
    try await withStore { store, _ in
        let now = Date.now; let today = LocalDay(date: now)
        let end = LocalDay(date: Calendar.current.date(byAdding: .day, value: 30, to: now)!)
        let goal = WeightTarget(initial: 70, target: 65, start: today, end: end)
        try await store.saveWeightTarget(goal, now: now)
        try await store.saveWeightTarget(goal, now: now)
        var snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 1)
        let id = try #require(snapshot.entries.first?.id)
        #expect(snapshot.weightTarget == goal)
        #expect(snapshot.weights[id]?.target == goal)
        let finished = CheckInDraft(cardID: "punchcard.50", day: today, timeZoneID: TimeZone.current.identifier, quantity: 64.9, note: "")
        try await store.add(finished, now: now)
        #expect(try await store.snapshot().weightTarget == nil)
        #expect(try await store.snapshot().weights[id]?.target == goal)
        let gaining = WeightTarget(initial: 64.9, target: 68, start: today, end: end)
        try await store.saveWeightTarget(gaining, now: now)
        try await store.saveWeightTarget(goal, now: now) // A delayed retry cannot reinstate an old goal.
        #expect(try await store.snapshot().weightTarget == gaining)
        try await store.add(CheckInDraft(cardID: "punchcard.50", day: today, timeZoneID: TimeZone.current.identifier, quantity: 68, note: ""), now: now)
        snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.weightTarget == nil)
        #expect(snapshot.weights[id]?.target == gaining)
        await store.close(); try await store.open()
        #expect(try await store.snapshot().weights[id]?.target == gaining)
    }
}

@Test func invalidWeightGoalsAndBackfillsCannotCorruptCurrentState() async throws {
    try await withStore { store, _ in
        let now = Date.now; let today = LocalDay(date: now)
        let tomorrow = LocalDay(date: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        for (initial, target, end) in [(60.0, 60.0, tomorrow), (60, .nan, tomorrow), (60, 55, today), (60, 201, tomorrow)] {
            await #expect(throws: StoreError.invalidWeightTarget) { try await store.saveWeightTarget(WeightTarget(initial: initial, target: target, start: today, end: end), now: now) }
        }
        #expect(try await store.snapshot().entries.isEmpty)
        try await store.saveProfile(UserProfile(height: 180, weight: 70))
        let goal = WeightTarget(initial: 70, target: 65, start: today, end: tomorrow)
        try await store.saveWeightTarget(goal, now: now)
        let yesterday = LocalDay(date: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
        let past = CheckInDraft(cardID: "punchcard.50", day: yesterday, timeZoneID: TimeZone.current.identifier, quantity: 64, note: "")
        try await store.add(past, now: now)
        let snapshot = try await store.snapshot()
        #expect(snapshot.weightTarget == goal)
        #expect(snapshot.profile?.weight == 70)
        #expect(snapshot.weights[past.id]?.target == nil)
        await #expect(throws: StoreError.invalidQuantity) { try await store.add(CheckInDraft(cardID: "punchcard.50", day: today, timeZoneID: TimeZone.current.identifier, quantity: 201, note: ""), now: now) }
    }
}

@Test func weightPlanAndProfileEditsShareDailyUpdateRules() async throws {
    try await withStore { store, _ in
        try await store.saveProfile(UserProfile())
        let now = Date.now; let later = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let day = LocalDay(date: later)
        try await store.saveSchedule(ScheduledCard(cardID: "punchcard.50", day: day, note: "Morning weight"), now: now)
        let value = CheckInDraft(cardID: "punchcard.50", day: day, timeZoneID: TimeZone.current.identifier, quantity: 59.9, note: "")
        try await store.add(value, now: later)
        try await store.updateProfile(.weight(59.8), now: later)
        let snapshot = try await store.snapshot()
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.note == "Morning weight")
        #expect(snapshot.entries.first?.quantity == 59.8)
        #expect(snapshot.schedules.isEmpty)
        #expect(snapshot.weights.count == 1)
    }
}

@Test func schemaFiveWeightUpgradeAndIDsPreserveExistingRecords() async throws {
    try await withStore { store, url in
        let now = Date.now
        let value = CheckInDraft(cardID: "preset.fruit", day: LocalDay(date: now), timeZoneID: TimeZone.current.identifier, quantity: nil, note: "Preserve")
        try await store.add(value, now: now)
        try await store.saveProfile(UserProfile(nickname: "KeepUp"))
        let future = LocalDay(date: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        let plan = ScheduledCard(cardID: "punchcard.50", day: future, note: "Weigh in")
        try await store.saveSchedule(plan, now: now)
        await store.close()
        let database = Database(at: url.path)
        for table in ["weight_target", "weight_records", "weight_operations"] { try database.exec(StatementDropTable().drop(table: table)) }
        try database.exec(StatementPragma().pragma(.userVersion).to(5)); database.close()
        try await store.open()
        var snapshot = try await store.snapshot()
        #expect(snapshot.entries.first?.id == value.id)
        #expect(snapshot.schedules == [plan])
        #expect(snapshot.profile?.nickname == "KeepUp")
        await #expect(throws: StoreError.invalidCard) {
            try await store.add(CheckInDraft(id: value.id, cardID: "punchcard.50", day: value.day, timeZoneID: value.timeZoneID, quantity: 60, note: ""), now: now)
        }
        snapshot = try await store.snapshot()
        #expect(snapshot.entries.first?.cardID == "preset.fruit")
        #expect(snapshot.weightTarget == nil)
        #expect(snapshot.weights.isEmpty)
    }
}
