import Foundation

/// Stable IDs, order, units and artwork are maintained in Resources/cards.json.
enum OriginalCatalog {
    struct Item: Decodable, Sendable {
        let number: Int
        let card: HabitCard
        let artwork: String
        let sport: String
    }
    struct Configuration: Decodable {
        let version: Int
        let items: [Item]
        /// Schema-one seed data is kept unchanged for database upgrade compatibility.
        let legacyStarters: [HabitCard]

        func validate() throws {
            guard version == 1, !items.isEmpty,
                  Set(items.map(\.number)).count == items.count,
                  Set(items.map { $0.card.id }).count == items.count,
                  Set(items.map { $0.card.sortOrder }).count == items.count,
                  items.allSatisfy({ $0.number > 0 && !$0.artwork.isEmpty && !$0.sport.isEmpty &&
                      !$0.card.id.isEmpty && !$0.card.isCustom && !$0.card.titleKey.isEmpty && $0.card.sortOrder >= 0 }),
                  !legacyStarters.isEmpty,
                  Set(legacyStarters.map(\.id)).count == legacyStarters.count,
                  legacyStarters.allSatisfy({ starter in items.contains { $0.card.id == starter.id && $0.card.unit == starter.unit } }) else {
                throw BundledJSON.ConfigurationError.invalid("cards: version, IDs, order or legacy references")
            }
        }
    }
    static let configuration = BundledJSON.required(Configuration.self, named: "cards") { try $0.validate() }
    static let items = configuration.items.sorted { $0.card.sortOrder < $1.card.sortOrder }
    static func item(_ card: HabitCard) -> Item? { items.first { $0.card.id == card.id } }
    static func card(_ number: Int) -> HabitCard? { items.first { $0.number == number }?.card }
}
