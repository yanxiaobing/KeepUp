import Foundation
import SwiftUI
import Testing
@testable import KeepUp

private let encouragementDay = LocalDay(rawValue: "2026-09-20")!
private func encouragementEntry(_ id: String, card: HabitCard = OriginalCatalog.card(3)!, day: String = "2026-09-20",
                                quantity: Double? = 30, unit: CardUnit? = nil, zone: String = "UTC") -> CheckInEntry {
    let localDay = LocalDay(rawValue: day)!
    return CheckInEntry(id: id, cardID: card.id, day: localDay, timeZoneID: zone,
                        createdAt: localDay.date(in: TimeZone(identifier: zone)!), quantity: quantity, unit: unit ?? card.unit, note: "")
}
private func encouragementChoices(_ entries: [CheckInEntry], card: HabitCard = OriginalCatalog.card(3)!,
                                  weight: WeightRecord? = nil, today: LocalDay = encouragementDay) -> [EntryEncouragement] {
    EntryEncouragement.candidates(entry: entries[0], card: card, entries: entries, weight: weight, today: today)
}
private func encouragementTarget(initial: Double = 70, target: Double = 65, start: String = "2026-09-01",
                                 end: String = "2026-10-01") -> WeightTarget {
    WeightTarget(initial: initial, target: target, start: LocalDay(rawValue: start)!, end: LocalDay(rawValue: end)!)
}

@Test func encouragementTotalsOnlyMatchingCardAndUnitWithKnownPositiveMeasurements() {
    let records = [encouragementEntry("a", quantity: 12.5), encouragementEntry("b", quantity: 7.5),
                   encouragementEntry("wrong-card", card: OriginalCatalog.card(4)!, quantity: 999),
                   encouragementEntry("wrong-unit", quantity: 999, unit: .count),
                   encouragementEntry("unknown", quantity: nil), encouragementEntry("zero", quantity: 0),
                   encouragementEntry("negative", quantity: -1), encouragementEntry("nan", quantity: .nan),
                   encouragementEntry("infinite", quantity: .infinity)]
    let choices = encouragementChoices(records)
    #expect(choices.contains(.quantity(20)))
    #expect(choices.contains(.checkIns(8)))
    #expect(!choices.contains(.quantity(1_019)))
}

@Test func encouragementRejectsOverflowAndDoesNotInventZeroTotal() {
    let huge = [encouragementEntry("a", quantity: .greatestFiniteMagnitude), encouragementEntry("b", quantity: .greatestFiniteMagnitude)]
    #expect(encouragementChoices(huge) == [.checkIns(2), .general])
    #expect(encouragementChoices([encouragementEntry("unknown", quantity: nil)]) == [.general])
    #expect(encouragementChoices([encouragementEntry("zero", quantity: 0)]) == [.general])
}

@Test func encouragementCountsUnitlessCheckInsWithoutAddingTheirMeasurements() {
    let card = HabitCard(id: "custom.unitless", titleKey: "Test", symbol: "", unit: .none, sortOrder: 0)
    let records = [encouragementEntry("a", card: card, quantity: 100), encouragementEntry("b", card: card, quantity: 200)]
    #expect(encouragementChoices(records, card: card) == [.checkIns(2), .general])
    #expect(encouragementChoices([records[0]], card: card) == [.general])
    let repetitions = HabitCard(id: "custom.repetitions", titleKey: "Test", symbol: "", unit: .count, sortOrder: 1)
    let counted = [encouragementEntry("a", card: repetitions, quantity: 10), encouragementEntry("b", card: repetitions, quantity: 20)]
    #expect(encouragementChoices(counted, card: repetitions) == [.checkIns(2), .quantity(30), .general])
}

@Test func encouragementWeightUsesSavedTargetAndNeverAddsWeights() {
    let card = OriginalCatalog.card(50)!
    let records = [encouragementEntry("latest", card: card, quantity: 64.5), encouragementEntry("earlier", card: card, quantity: 68)]
    let saved = WeightRecord(height: 170, target: encouragementTarget())
    #expect(encouragementChoices(records, card: card, weight: saved) == [.weightGoal(losing: true, days: 19, change: 5.5)])
    #expect(encouragementChoices(records, card: card, weight: nil) == [.checkIns(2), .general])
    let unmet = WeightRecord(height: nil, target: encouragementTarget(target: 60))
    #expect(encouragementChoices(records, card: card, weight: unmet) == [.checkIns(2), .general])
}

@Test func encouragementWeightGainGoalTakesPriorityOverCountAndStreak() {
    let card = OriginalCatalog.card(50)!
    let records = [encouragementEntry("today", card: card, quantity: 66), encouragementEntry("yesterday", day: "2026-09-19"),
                   encouragementEntry("previous-weight", card: card, day: "2026-09-18", quantity: 64)]
    let saved = WeightRecord(height: nil, target: encouragementTarget(initial: 60, target: 65))
    #expect(encouragementChoices(records, card: card, weight: saved) == [.weightGoal(losing: false, days: 19, change: 6)])
    let unmet = WeightRecord(height: nil, target: encouragementTarget(initial: 60, target: 68))
    #expect(encouragementChoices(records, card: card, weight: unmet) == [.checkIns(2), .streak(3), .general])
}

@Test func encouragementWeightElapsedDaysUseCivilDatesAcrossDSTAndAtLeastOneDay() {
    let card = OriginalCatalog.card(50)!
    let entry = encouragementEntry("dst", card: card, day: "2026-03-09", quantity: 65, zone: "America/Los_Angeles")
    let target = encouragementTarget(start: "2026-03-07", end: "2026-04-01")
    #expect(encouragementChoices([entry], card: card, weight: WeightRecord(target: target)) == [.weightGoal(losing: true, days: 2, change: 5)])
    let sameDay = encouragementTarget(start: "2026-03-09", end: "2026-04-01")
    #expect(encouragementChoices([entry], card: card, weight: WeightRecord(target: sameDay)) == [.weightGoal(losing: true, days: 1, change: 5)])
}

@Test func encouragementWeightRejectsFutureOrInvalidTargetAndInvalidMeasurement() {
    let card = OriginalCatalog.card(50)!
    let entry = encouragementEntry("weight", card: card, quantity: 65)
    let targets = [encouragementTarget(start: "2026-09-21"), encouragementTarget(end: "2026-09-01"),
                   encouragementTarget(initial: 65, target: 65), encouragementTarget(initial: .nan),
                   encouragementTarget(target: .infinity), encouragementTarget(initial: 201), encouragementTarget(target: 19)]
    for target in targets {
        #expect(encouragementChoices([entry], card: card, weight: WeightRecord(target: target)) == [.general])
    }
    for value in [Double.nan, .infinity, 0, -1, 201] {
        let invalid = encouragementEntry("invalid", card: card, quantity: value)
        #expect(encouragementChoices([invalid], card: card, weight: WeightRecord(target: encouragementTarget())) == [.general])
    }
    let mismatch = encouragementEntry("wrong-unit", card: card, quantity: 65, unit: .count)
    #expect(encouragementChoices([mismatch], card: card, weight: WeightRecord(target: encouragementTarget())) == [.general])
}

@Test func encouragementStreakIsGlobalAndDeduplicatesDays() {
    let entries = [encouragementEntry("today"), encouragementEntry("today-duplicate"),
                   encouragementEntry("yesterday-other-card", card: OriginalCatalog.card(4)!, day: "2026-09-19"),
                   encouragementEntry("before", day: "2026-09-18"), encouragementEntry("future", day: "2026-09-21")]
    let choices = encouragementChoices(entries)
    #expect(choices.contains(.streak(3)))
    #expect(!choices.contains(.streak(4)))
}

@Test func encouragementStreakAllowsYesterdayButStopsAtGap() {
    let entries = [encouragementEntry("yesterday", day: "2026-09-19"), encouragementEntry("before", day: "2026-09-18"),
                   encouragementEntry("gap", day: "2026-09-16")]
    #expect(encouragementChoices(entries).contains(.streak(2)))
    let expired = LocalDay(rawValue: "2026-09-21")!
    #expect(!encouragementChoices(entries, today: expired).contains(.streak(2)))
    #expect(encouragementChoices([entries[0], entries[2]]) == [.checkIns(2), .quantity(60), .general])
}

@Test func encouragementSelectionAndFloatingPointTotalsIgnoreSnapshotOrder() {
    let card = OriginalCatalog.card(3)!
    let entry = encouragementEntry("stable-poster", quantity: 0.1)
    let entries = [entry, encouragementEntry("b", quantity: 1), encouragementEntry("c", quantity: 0.2),
                   encouragementEntry("d", day: "2026-09-19", quantity: 0.3)]
    let expected = EntryEncouragement.selected(entry: entry, card: card, entries: entries, weight: nil, today: encouragementDay)
    let choices = encouragementChoices(entries)
    for reordered in [Array(entries.reversed()), [entries[2], entries[0], entries[3], entries[1]]] {
        #expect(EntryEncouragement.candidates(entry: entry, card: card, entries: reordered, weight: nil, today: encouragementDay) == choices)
        #expect(EntryEncouragement.selected(entry: entry, card: card, entries: reordered, weight: nil, today: encouragementDay) == expected)
    }
    #expect(choices.contains(expected))
}

@Test func encouragementFormatsEveryBranchInEnglishAndChinese() {
    let card = OriginalCatalog.card(3)!
    let samples: [(EntryEncouragement, String, String)] = [
        (.general, "Whatever happens, keep your spirits up!", "输了什么也不要输心情~"),
        (.checkIns(12), "Exercise check-ins: 12. Keep going—you’re building a better you.", "嘿，你真棒！已经打健身卡12次，努力会让你遇见更好的自己。"),
        (.quantity(123.5), "Exercise total: 123.5 min. Every effort counts!", "累计健身123.5分钟，每一次坚持都有收获！"),
        (.streak(7), "You’ve checked in for 7 days in a row. Keep it going!", "已经连续打卡7天，继续保持！"),
        (.weightGoal(losing: true, days: 19, change: 5.5), "Weight-loss goal reached! 19 days, 5.5 kg lost.", "达成减重目标！用19天减重5.5公斤。"),
        (.weightGoal(losing: false, days: 1, change: 6), "Weight-gain goal reached! 1 day, 6.0 kg gained.", "达成增重目标！用1天增重6.0公斤。"),
        (.weightGoal(losing: true, days: 1, change: 1), "Weight-loss goal reached! 1 day, 1.0 kg lost.", "达成减重目标！用1天减重1.0公斤。")
    ]
    for (choice, english, chinese) in samples {
        #expect(choice.text(card: card, locale: Locale(identifier: "en_US")) == english)
        #expect(choice.text(card: card, locale: Locale(identifier: "zh_Hans_CN")) == chinese)
    }
}

@Test @MainActor func encouragementRendersCompleteOrdinaryAndWeightPostersInBothLanguages() throws {
    let ordinaryCard = OriginalCatalog.card(3)!
    // A fixed ID selects the quantity branch so the attachment covers cumulative wording.
    let cumulative = encouragementEntry("b", quantity: 123.5)
    #expect(EntryEncouragement.selected(entry: cumulative, card: ordinaryCard, entries: [cumulative], weight: nil, today: encouragementDay) == .quantity(123.5))
    let weightCard = OriginalCatalog.card(50)!
    let weightEntry = encouragementEntry("weight-poster", card: weightCard, quantity: 64.5)
    for language in ["en_US", "zh_Hans_CN"] {
        for isWeight in [false, true] {
            let entry = isWeight ? weightEntry : cumulative
            let card = isWeight ? weightCard : ordinaryCard
            let weights = isWeight ? [entry.id: WeightRecord(height: 170, target: encouragementTarget())] : [:]
            let poster = EntryPoster(entry: entry, card: card, entries: [entry], locale: Locale(identifier: language),
                                     weights: weights, referenceDay: encouragementDay).frame(width: 375, height: 700)
                .environment(\.locale, Locale(identifier: language)).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: poster)
            renderer.scale = 3
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == 375 && image.size.height == 700)
            #expect(image.cgImage?.width == 1_125 && image.cgImage?.height == 2_100)
            Attachment.record(Array(try #require(image.pngData())), named: "encouragement-\(isWeight ? "weight" : "total")-\(language).png")
        }
    }
}
