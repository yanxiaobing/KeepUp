import Foundation
import Testing
@testable import KeepUp

@Test func energyUsesOriginalCoefficientsAndStableAliases() {
    #expect(ActivityEnergy.calories(card: OriginalCatalog.card(3)!, quantity: 30) == 175)
    #expect(ActivityEnergy.calories(card: OriginalCatalog.card(16)!, quantity: 10) == 15)
    #expect(ActivityEnergy.calories(card: OriginalCatalog.card(18)!, quantity: 3) == 39)
    #expect(ActivityEnergy.calories(card: OriginalCatalog.card(57)!, quantity: 1) == 2)
    #expect(OriginalCatalog.items.filter { ActivityEnergy.calories(card: $0.card, quantity: 60) != nil }.count == 31)
}

@Test func energyRejectsUnsupportedCardsAndInvalidQuantities() {
    for number in [1, 2, 50, 63, 65, 96] {
        #expect(ActivityEnergy.calories(card: OriginalCatalog.card(number)!, quantity: 60) == nil)
    }
    let card = OriginalCatalog.card(3)!
    for value in [0, -1, Double.nan, .infinity, Double.greatestFiniteMagnitude] {
        #expect(ActivityEnergy.calories(card: card, quantity: value) == nil)
    }
    #expect(ActivityEnergy.calories(card: card, quantity: nil) == nil)
    let custom = HabitCard(id: "custom.test", titleKey: "Test", symbol: "", unit: .minutes, sortOrder: 0)
    #expect(ActivityEnergy.calories(card: custom, quantity: 30) == nil)
    let entry = CheckInEntry(id: "test", cardID: card.id, day: LocalDay(rawValue: "2026-09-18")!, timeZoneID: "UTC", createdAt: .now, quantity: 30, unit: .count, note: "")
    #expect(ActivityEnergy.calories(entry: entry, card: card) == nil)
}

@Test func foodMatchKeepsOriginalOrderRoundingAndFallback() {
    #expect(ActivityEnergy.food(for: 0) == nil)
    #expect(ActivityEnergy.food(for: 1) == .init(index: 1, count: 1))
    #expect(ActivityEnergy.food(for: 30) == .init(index: 0, count: 4))
    #expect(ActivityEnergy.food(for: 175) == .init(index: 5, count: 4))
    #expect(ActivityEnergy.food(for: 20000) == .init(index: 38, count: 7))
    #expect(ActivityEnergy.description(calories: 175, locale: Locale(identifier: "zh-Hans")) == "预计消耗175大卡 · 约等于4个上校鸡块")
    #expect(ActivityEnergy.description(calories: 175, locale: Locale(identifier: "en")) == "Est. 175 kcal burned · ≈ 4 chicken nuggets")
    #expect(ActivityEnergy.description(calories: 0, locale: Locale(identifier: "en")) == "Est. 0 kcal burned")
}

@Test func bundledConfigurationPreservesCatalogAndFoodReferences() throws {
    #expect(OriginalCatalog.items.count == 45)
    #expect(HabitCard.starters.map(\.id) == ["preset.exercise", "preset.walk", "preset.fruit", "preset.noSoda", "preset.noLateSnacks", "preset.pushUps"])
    #expect(ActivityEnergy.configuration.coefficients.count == 31)
    #expect(ActivityEnergy.configuration.foods.count == 39)
    for food in ActivityEnergy.configuration.foods {
        for language in ["en", "zh-Hans"] {
            for form in ["one", "many"] {
                let key = "\(food.localizationKey).\(form)"
                #expect(localized(key, Locale(identifier: language)) != key)
            }
        }
    }
    #expect(throws: BundledJSON.ConfigurationError.self) {
        _ = try BundledJSON.decode(OriginalCatalog.Configuration.self, named: "nonexistent-config")
    }
}

@Test func bundledConfigurationRejectsBrokenVersionsAndReferences() throws {
    let url = Bundle.main.url(forResource: "activity-energy", withExtension: "json")!
    let original = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let changes: [(String, Any)] = [("version", 99), ("foods", [] as [String]), ("maxFoodServings", 0), ("smallCalorieFoodID", "missing"), ("overflowFoodID", "missing")]
    for change in changes {
        var json = original; json[change.0] = change.1
        let config = try JSONDecoder().decode(ActivityEnergy.Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: BundledJSON.ConfigurationError.self) { try config.validate(cards: OriginalCatalog.items) }
    }
    for coefficient in [
        ["cardNumber": 3, "calories": 350, "units": 0],
        ["cardNumber": 999, "calories": 350, "units": 60]
    ] {
        var json = original; json["coefficients"] = [coefficient]
        let config = try JSONDecoder().decode(ActivityEnergy.Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: BundledJSON.ConfigurationError.self) { try config.validate(cards: OriginalCatalog.items) }
    }
    let cardsURL = Bundle.main.url(forResource: "cards", withExtension: "json")!
    var cards = try JSONSerialization.jsonObject(with: Data(contentsOf: cardsURL)) as! [String: Any]
    let items = cards["items"] as! [[String: Any]]
    cards["items"] = items + [items[0]]
    let duplicate = try JSONDecoder().decode(OriginalCatalog.Configuration.self, from: JSONSerialization.data(withJSONObject: cards))
    #expect(throws: BundledJSON.ConfigurationError.self) { try duplicate.validate() }
}

@Test func stepEnergyUsesFixedEstimateAndRejectsUnknownOrInvalidCounts() {
    #expect(ActivityEnergy.stepCalories(steps: nil) == nil)
    #expect(ActivityEnergy.stepCalories(steps: -1) == nil)
    #expect(ActivityEnergy.stepCalories(steps: Int.max) == nil)
    for (steps, expected) in [(0, 0), (1, 0), (33, 0), (34, 1), (100, 3), (6500, 195), (9999, 299), (1_000_000, 30_000)] {
        #expect(ActivityEnergy.stepCalories(steps: steps) == expected)
    }
    let card = OriginalCatalog.card(1)!
    let day = LocalDay(rawValue: "2020-09-08")!
    func measuredEntry(_ quantity: Double?) -> CheckInEntry {
        CheckInEntry(id: "steps.2020-09-08", cardID: card.id, day: day, timeZoneID: "UTC", createdAt: .now,
                     quantity: quantity, unit: .steps, note: "")
    }
    let entry = measuredEntry(6500)
    #expect(ActivityEnergy.calories(entry: entry, card: card) == 195)
    let record = StepRecord(day: day, timeZoneID: "UTC", steps: 6500, distance: nil, measuredAt: day.date(), goal: nil)
    let presentation = StepsPresentation(day: day, reading: nil, saved: record, goal: nil)
    #expect(presentation.estimatedKilocalories == ActivityEnergy.calories(entry: entry, card: card))
    for value in [Double.nan, .infinity, -1, 12.5, 1_000_001] {
        #expect(ActivityEnergy.calories(entry: measuredEntry(value), card: card) == nil)
    }
    #expect(ActivityEnergy.calories(entry: measuredEntry(nil), card: card) == nil)
    #expect(StepsPresentation(day: day, reading: nil, saved: nil, goal: nil).estimatedKilocalories == nil)
}
