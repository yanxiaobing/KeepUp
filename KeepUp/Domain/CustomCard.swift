import Foundation

struct CustomCardDraft: Sendable {
    var id = "custom." + UUID().uuidString
    var name: String
    var artwork: String
    var unit: CardUnit
    static let artworks = (1...7).map { String(format: "card_icon_custom_%02d", $0) }
    static let units: [CardUnit] = [.none, .minutes, .meters, .items, .count, .seconds]

    func validated() throws -> Self {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = copy.name.unicodeScalars.reduce(0) { $0 + ((0x4E00...0x9FA5).contains($1.value) ? 2 : 1) }
        guard id.hasPrefix("custom."), !copy.name.isEmpty, length <= 10,
              copy.name.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits).contains($0) }),
              Self.artworks.contains(artwork), Self.units.contains(unit) else { throw StoreError.invalidCustomCard }
        return copy
    }
}
