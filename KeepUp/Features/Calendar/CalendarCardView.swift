import SwiftUI

/// Shared geometry from XBCalendarCell, including the top-left result ribbon.
enum CalendarCardPalette {
    static let pending = "babdc2"
    static func completed(_ card: HabitCard) -> String {
        switch card.id {
        case "punchcard.50": "f5d039"
        case "punchcard.63": "5fdcc9"
        default: "5fc6dc"
        }
    }
    static func color(_ hex: String) -> Color { Color(hex: UInt32(hex, radix: 16)!) }
}

struct CalendarCardRibbon: View {
    let text: String
    let color: String
    var body: some View {
        Text(verbatim: text).font(.custom("HelveticaNeue-Light", size: 12))
            .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 6).frame(height: 18)
            .background {
                HStack(spacing: 0) {
                    CalendarCardPalette.color(color)
                    Image(color).resizable().frame(width: 10)
                }
            }
            .overlay(alignment: .leading) {
                Image("homepage_tag_light").resizable().frame(width: 6, height: 18)
            }
    }
}

struct CalendarTicketCard: View {
    let card: HabitCard
    let scale: CGFloat
    var entry: CheckInEntry? = nil
    var wake: WakeUpRecord? = nil
    var badge: String? = nil
    var reminder = false
    var progress: Int? = nil
    @Environment(\.locale) private var locale
    private var tint: String { entry == nil ? CalendarCardPalette.pending : CalendarCardPalette.completed(card) }
    private var ribbon: String? {
        if let badge { return badge }
        if let wake { return wake.isEarly ? localized("wake.earlyBadge", locale) : nil }
        if let quantity = entry?.quantity, quantity > 0, let entry {
            let value = quantity.formatted(.number.precision(.fractionLength(card.id == "punchcard.50" ? 1...1 : 0...1)).locale(locale))
            return value + localized(entry.unit.titleKey, locale)
        }
        return nil
    }
    private var illustration: String {
        guard entry == nil else { return card.cardImage }
        switch card.id {
        case "punchcard.50": return "home_heavy_pic_todo"
        case "punchcard.63": return "ic_early_card_undone"
        default: return "card_icon_todo"
        }
    }
    var body: some View {
        ZStack {
            Color.white
            if let wake {
                WakeUpClock(time: wake.time, timeZoneID: wake.timeZoneID, compact: true)
                    .frame(width: 72*scale, height: 72*scale).offset(y: -9*scale)
            } else {
                Image(illustration).resizable().frame(width: 74*scale, height: 87*scale)
                    .offset(y: scale > 1 ? -11 : -8)
            }
        }.frame(width: 88*scale, height: 116*scale)
            .overlay(alignment: .bottom) {
                Text(LocalizedStringKey(card.titleKey)).font(.system(size: 11)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity).frame(height: 18).background(CalendarCardPalette.color(tint))
            }
            .overlay(alignment: .topLeading) {
                if let ribbon { CalendarCardRibbon(text: ribbon, color: tint).frame(maxWidth: 88*scale, alignment: .leading) }
            }
            .overlay(alignment: .topTrailing) {
                if reminder && entry == nil { Image("card_detail_ic_clock").resizable().frame(width: 16, height: 16).padding(3) }
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    HStack(spacing: 1) {
                        ForEach(0..<min(7, max(0, progress)), id: \.self) { _ in
                            Capsule().fill(CalendarCardPalette.color(CalendarCardPalette.completed(card)))
                                .frame(width: (88*scale-8)/7, height: 2)
                        }
                    }.frame(maxWidth: .infinity).padding(.bottom, 19)
                        .accessibilityLabel(Text("reminder.progressCount \(progress)"))
                        .accessibilityIdentifier("target.progress.\(card.id)")
                }
            }
            .overlay { Image("xbcalendarItemCover").resizable().allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            .accessibilityElement(children: .combine)
    }
}

struct CalendarAddCard: View {
    let future: Bool
    let scale: CGFloat
    var body: some View {
        ZStack {
            Image(future ? "home_note_ic_plus" : "homepage_ic_budacard").resizable().scaledToFit()
                .frame(width: (future ? 25 : 45)*scale, height: (future ? 25 : 45)*scale).offset(y: -9*scale)
            CalendarEntryBorder().strokeBorder(Color(hex: 0xBABDC2), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }.frame(width: 88*scale, height: 116*scale)
            .overlay(alignment: .bottom) {
                Text(future ? "schedule.add" : "calendar.backfill").font(.system(size: 11)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity).frame(height: 18)
                    .background(Color(hex: 0xBABDC2))
            }
            .overlay { Image("xbcalendarItemCover").resizable().allowsHitTesting(false) }
    }
}

private struct CalendarEntryBorder: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return Path { path in
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
    }
    func inset(by amount: CGFloat) -> some InsettableShape { var copy = self; copy.inset += amount; return copy }
}
