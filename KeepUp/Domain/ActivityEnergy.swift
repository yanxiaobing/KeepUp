import Foundation

/// Fixed activity estimates from Resources/activity-energy.json; not personalized measurements.
/// Keep version-one coefficients stable because historical entries derive energy from quantity.
enum ActivityEnergy {
    struct Coefficient: Decodable {
        let cardNumber: Int
        let calories: Double
        let units: Double
    }
    struct Food: Decodable {
        let id: String
        let calories: Double
        let localizationKey: String
    }
    struct Configuration: Decodable {
        let version: Int
        let coefficients: [Coefficient]
        let foods: [Food]
        let maxFoodServings: Int
        let smallCalorieFoodID: String
        let overflowFoodID: String

        func validate(cards: [OriginalCatalog.Item]) throws {
            guard version == 1, !coefficients.isEmpty, !foods.isEmpty, maxFoodServings > 0,
                  Set(coefficients.map(\.cardNumber)).count == coefficients.count,
                  coefficients.allSatisfy({ coefficient in
                      coefficient.calories.isFinite && coefficient.calories > 0 &&
                      coefficient.units.isFinite && coefficient.units > 0 &&
                      cards.contains { $0.number == coefficient.cardNumber && $0.card.unit != .none && $0.card.unit != .kilograms }
                  }),
                  Set(foods.map(\.id)).count == foods.count,
                  Set(foods.map(\.localizationKey)).count == foods.count,
                  foods.allSatisfy({ !$0.id.isEmpty && !$0.localizationKey.isEmpty && $0.calories.isFinite && $0.calories >= 1 }),
                  foods.contains(where: { $0.id == smallCalorieFoodID }),
                  foods.contains(where: { $0.id == overflowFoodID }) else {
                throw BundledJSON.ConfigurationError.invalid("activity-energy: version, coefficients, foods or references")
            }
        }
    }
    static let configuration = BundledJSON.required(Configuration.self, named: "activity-energy") {
        try $0.validate(cards: OriginalCatalog.items)
    }
    private static let coefficients = Dictionary(uniqueKeysWithValues: configuration.coefficients.map { ($0.cardNumber, $0) })

    static func calories(card: HabitCard, quantity: Double?) -> Int? {
        guard let quantity, quantity.isFinite, quantity > 0,
              let item = OriginalCatalog.item(card), card.unit == item.card.unit,
              let coefficient = coefficients[item.number] else { return nil }
        let result = quantity * coefficient.calories / coefficient.units
        guard result.isFinite, result >= 0, result < Double(Int.max) else { return nil }
        return Int(result)
    }

    static func calories(entry: CheckInEntry, card: HabitCard) -> Int? {
        guard entry.cardID == card.id, entry.unit == card.unit else { return nil }
        return calories(card: card, quantity: entry.quantity)
    }

    struct FoodMatch: Equatable {
        let index: Int
        let count: Int
    }
    static func food(for calories: Int) -> FoodMatch? {
        guard calories > 0 else { return nil }
        let value = Double(calories)
        let foods = configuration.foods
        var selected = foods.firstIndex { $0.id == configuration.overflowFoodID }!
        var minimum = Double.infinity
        for (index, food) in foods.enumerated() where food.calories * Double(configuration.maxFoodServings) >= value {
            let energy = food.calories
            let offset = abs(value - energy * (value / energy).rounded())
            if offset < minimum { selected = index; minimum = offset }
        }
        let roundedCount = (value / foods[selected].calories).rounded()
        guard roundedCount < Double(Int.max) else { return nil }
        let count = Int(roundedCount)
        let smallIndex = foods.firstIndex { $0.id == configuration.smallCalorieFoodID }!
        return count > 0 ? FoodMatch(index: selected, count: count) : FoodMatch(index: smallIndex, count: 1)
    }

    static func description(calories: Int, locale: Locale) -> String {
        let amount = calories.formatted(.number.locale(locale))
        let energy = String(format: localized("energy.burned", locale), amount)
        guard let food = food(for: calories) else { return energy }
        let key = "\(configuration.foods[food.index].localizationKey).\(food.count == 1 ? "one" : "many")"
        let serving = String(format: localized(key, locale), food.count.formatted(.number.locale(locale)))
        return energy + " · " + String(format: localized("energy.equivalent", locale), serving)
    }
}
