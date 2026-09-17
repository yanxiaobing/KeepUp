import SwiftUI

/// PunchCard's default Departure theme and its original action / card colors.
enum KeepUpStyle {
    static let accent = Color(red: 1, green: 100/255, blue: 64/255)
    static var theme: Color { CalendarTheme.selected.color }
    static var day: Color { CalendarTheme.selected.dayColor }
    static let card = Color(red: 93/255, green: 197/255, blue: 220/255)
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let header = Color(red: 44/255, green: 44/255, blue: 44/255)
}

extension HabitCard {
    // UI resource mapping is independent of the persisted schema and existing UUIDs.
    private var artwork: (card: String, sport: String) {
        if isCustom { return (symbol, "customize") }
        if let original = OriginalCatalog.item(self) {
            return (original.artwork, String(original.sport.dropFirst("sport_ic_".count)))
        }
        return switch id {
        case "preset.exercise": ("card_icon_gym", "take_exercise")
        case "preset.walk": ("card_icon_stroll", "take_awalk")
        case "preset.fruit": ("card_detail_ic_fruits", "fruits")
        case "preset.noSoda": ("card_detail_drinks", "drinks")
        case "preset.noLateSnacks": ("card_detail_supper", "supper")
        case "preset.pushUps": ("card_icon_pushup", "push_up")
        default: ("card_icon_gym", "take_exercise")
        }
    }
    var cardImage: String { artwork.card }
    var sportImage: String { "sport_ic_" + artwork.sport }
    var whiteImage: String { "sport_ic_white_" + artwork.sport }
    var feedImage: String { "feed_sport_ic_" + artwork.sport }
}

struct CardSymbol: View {
    let card: HabitCard
    var size: CGFloat = 46
    var body: some View {
        Image(card.sportImage).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct OriginalIconButton: View {
    let image: String
    let label: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(image).renderingMode(["base_icon_close", "card_detail_ic_delete"].contains(image) ? .template : .original)
                .resizable().scaledToFit().foregroundStyle(.primary).frame(width: 24, height: 24)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(Text(label))
    }
}

struct EntryRowView: View {
    @Environment(\.locale) private var locale
    let entry: CheckInEntry
    let card: HabitCard
    var content = EntryContent()
    var hasDraft = false
    var scale: CGFloat = 1
    var body: some View {
        HStack(alignment: .top, spacing: 10 * scale) {
            Image(card.whiteImage).resizable().frame(width: 40 * scale, height: 40 * scale)
                .background(KeepUpStyle.theme.opacity(0.7), in: RoundedRectangle(cornerRadius: 4 * scale))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(LocalizedStringKey(card.titleKey))
                    if let quantity = entry.quantity {
                        Text(quantity, format: .number.precision(.fractionLength(0...2)))
                            .foregroundStyle(Color(red: 245/255, green: 127/255, blue: 23/255))
                        Text(LocalizedStringKey(entry.unit.titleKey))
                    }
                }.font(.system(size: 13 * scale, weight: .bold)).frame(height: 40 * scale, alignment: .top)
                if let calories = ActivityEnergy.calories(entry: entry, card: card) {
                    Text(ActivityEnergy.description(calories: calories, locale: locale))
                        .font(.system(size: 12*scale)).foregroundStyle(Color(white: 0.43))
                        .accessibilityIdentifier("energy.row")
                }
                if hasDraft { Text("content.draft").font(.system(size: 12*scale)).foregroundStyle(KeepUpStyle.accent).padding(.top, 8*scale) }
                if !content.text.isEmpty {
                    Text(content.text).font(.system(size: 15 * scale)).foregroundStyle(Color(white: 34/255).opacity(0.8)).padding(.top, 15 * scale)
                }
                if let data = content.photo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 100*scale, height: 100*scale).clipped().padding(.top, 15*scale)
                        .accessibilityLabel(Text("content.photo")).accessibilityIdentifier("content.savedPhoto")
                }
                Text(entry.createdAt, format: .dateTime.hour().minute()).font(.system(size: 10 * scale))
                    .foregroundStyle(Color(white: 34/255).opacity(0.3)).padding(.top, 20 * scale)
            }
            Spacer(minLength: 0)
        }.padding(15 * scale).frame(maxWidth: .infinity, alignment: .leading).background(.white)
            .accessibilityElement(children: .combine)
    }
}
