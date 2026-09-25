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
    var steps: StepRecord? = nil
    var stepGoal: Int? = nil
    @Environment(\.locale) private var locale
    private var tint: String { entry == nil && card.id != "punchcard.1" ? CalendarCardPalette.pending : CalendarCardPalette.completed(card) }
    private var ribbon: String? {
        if card.id == "punchcard.1" { return nil }
        if let badge { return badge }
        if let wake { return wake.isEarly ? localized("wake.earlyBadge", locale) : nil }
        if let quantity = entry?.quantity, quantity > 0, let entry {
            let digits = ["punchcard.2", "punchcard.96"].contains(card.id) ? 2...2 : card.id == "punchcard.50" ? 1...1 : 0...1
            let value = quantity.formatted(.number.precision(.fractionLength(digits)).locale(locale))
            return value + localized(entry.unit.titleKey, locale)
        }
        return nil
    }
    private var illustration: String {
        guard entry == nil else { return card.cardImage }
        switch card.id {
        case "punchcard.1": return card.cardImage
        case "punchcard.50": return "home_heavy_pic_todo"
        case "punchcard.63": return "ic_early_card_undone"
        default: return "card_icon_todo"
        }
    }
    var body: some View {
        ZStack {
            Color.white
            if card.id == "punchcard.1" {
                StepsCalendarProgressRing(count: steps?.steps ?? entry?.quantity.map(Int.init),
                                          goal: steps?.goal ?? stepGoal, scale: scale)
                    .offset(y: -9 * scale)
            } else if let wake {
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
                if let progress, card.id != "punchcard.1" {
                    HStack(spacing: 1) {
                        ForEach(0..<min(7, max(0, progress)), id: \.self) { _ in
                            Capsule().fill(CalendarCardPalette.color(CalendarCardPalette.completed(card)))
                                .frame(width: (88*scale-8)/7, height: 2)
                        }
                    }.frame(maxWidth: .infinity).padding(.bottom, 19)
                        .accessibilityLabel(Text(verbatim: String(format: localized("reminder.progressCount %lld", locale), Int64(progress))))
                        .accessibilityIdentifier("target.progress.\(card.id)")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5 * scale, style: .circular))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            .accessibilityElement(children: .combine)
    }
}

private struct StepsCalendarProgressRing: View {
    let count: Int?
    let goal: Int?
    let scale: CGFloat

    private var progress: CGFloat {
        guard let count, let goal, goal > 0 else { return 0 }
        return min(1, max(0, CGFloat(count) / CGFloat(goal)))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .overlay { Circle().stroke(Color(hex: 0x54DAC7), lineWidth: 1 * scale) }
                .shadow(color: Color(hex: 0x00C0FF).opacity(0.4), radius: 3 * scale, y: 1 * scale)
            Circle().stroke(Color(hex: 0xCEF3EE), lineWidth: 6 * scale)
                .padding(5 * scale)
            Circle().trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Color(hex: 0xDBD91E), Color(hex: 0x35E7BF),
                                             Color(hex: 0x23A3D2), Color(hex: 0xDBD91E)], center: .center),
                    style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5 * scale)
                .animation(.easeInOut(duration: 1), value: progress)
            Circle().fill(Color(hex: 0xF3F3F3)).padding(9 * scale)
            Text(count.map { $0.formatted(.number.grouping(.never)) } ?? "—")
                .font(.system(size: 16 * scale))
                .foregroundStyle(Color(hex: 0x69696F))
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(12 * scale)
                .contentTransition(.numericText())
            if progress >= 0.97 {
                Circle().fill(Color(hex: 0xDBD91E))
                    .frame(width: 4.5 * scale, height: 4.5 * scale)
                    .offset(y: -31.5 * scale)
            }
        }
        .frame(width: 73 * scale, height: 73 * scale)
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
            .clipShape(RoundedRectangle(cornerRadius: 5 * scale, style: .circular))
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
