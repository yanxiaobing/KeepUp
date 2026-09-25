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
    static var editContentSymbol: String {
        if #available(iOS 27, *) { return "text.bubble.badge.sparkles" }
        return "pencil.and.list.clipboard"
    }
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
    var steps: StepRecord? = nil
    var stepGoal: Int? = nil
    var content = EntryContent()
    var hasDraft = false
    var scale: CGFloat = 1
    let action: () -> Void
    @State private var isExpanded = false
    @State private var textHeight: CGFloat = 0

    // Match PunchCard's 108-point timeline preview using the rendered text height,
    // so explicit newlines and different scripts fold at the same visual boundary.
    private var foldedHeight: CGFloat { 108 * scale }
    private var canExpand: Bool { !content.text.isEmpty && textHeight > foldedHeight + 0.5 }
    private var avatarScale: CGFloat { 0.35 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12 * scale) {
                    CalendarTicketCard(card: card, scale: 1, entry: entry, steps: steps, stepGoal: stepGoal)
                        .transformEffect(CGAffineTransform(scaleX: avatarScale, y: avatarScale))
                        .frame(width: 88 * avatarScale, height: 116 * avatarScale, alignment: .topLeading)
                        .offset(y: 2 * scale)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7 * scale) {
                        HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                            HStack(spacing: 3) {
                                Text(LocalizedStringKey(card.titleKey))
                                if let quantity = entry.quantity {
                                    Text(quantity, format: .number.precision(.fractionLength(0...2)))
                                        .foregroundStyle(KeepUpStyle.accent)
                                    Text(LocalizedStringKey(entry.unit.titleKey))
                                }
                            }
                            .font(.system(size: 15 * scale, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.createdAt, format: .dateTime.hour().minute())
                                .font(.system(size: 11 * scale))
                                .foregroundStyle(.secondary)
                        }
                        if let calories = ActivityEnergy.calories(entry: entry, card: card) {
                            Text(ActivityEnergy.description(calories: calories, locale: locale, energyKey: "energy.burnedShort"))
                                .font(.system(size: 12 * scale)).foregroundStyle(.secondary)
                                .accessibilityIdentifier("energy.row")
                        }
                        if hasDraft { Text("content.draft").font(.system(size: 12 * scale)).foregroundStyle(KeepUpStyle.accent) }
                        if !content.text.isEmpty {
                            Text(content.text)
                                .font(.system(size: 14 * scale))
                                .foregroundStyle(Color(white: 0.22))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                                .frame(maxHeight: isExpanded ? nil : foldedHeight, alignment: .top)
                                .clipped()
                                .padding(.top, 4 * scale)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("entry.\(entry.id)")

            VStack(alignment: .leading, spacing: 0) {
                if canExpand {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Text(isExpanded ? "history.collapse" : "history.expand")
                            .font(.system(size: 13 * scale, weight: .medium))
                            .foregroundStyle(KeepUpStyle.theme)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("history.toggle.\(entry.id)")
                        .accessibilityValue(Text(isExpanded ? "history.expanded" : "history.collapsed"))
                }
                Button(action: action) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let data = content.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 112 * scale, height: 112 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                                .padding(.top, 10 * scale)
                                .accessibilityLabel(Text("content.photo")).accessibilityIdentifier("content.savedPhoto")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("history.footer.\(entry.id)")
            }.padding(.leading, 42.8 * scale)
        }.padding(15 * scale).frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: content) { isExpanded = false }
            .onChange(of: entry.id) { isExpanded = false }
    }
}
