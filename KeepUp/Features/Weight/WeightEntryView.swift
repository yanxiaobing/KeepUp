import SwiftUI

struct WeightEntryView: View {
    let day: LocalDay
    let onSaved: () -> Void
    let onCancel: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var value = 60.0
    @State private var draftID = UUID().uuidString
    @State private var reminder = false
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width/375
            let bottom = max(geometry.safeAreaInsets.bottom, 34)
            let height = 388*s+bottom
            ZStack(alignment: .bottom) {
                Color(white: 34/255).opacity(0.8)
                VStack { Button(action: onCancel) { Color.clear.contentShape(Rectangle()) }.frame(height: max(0, geometry.size.height-height)).accessibilityIdentifier("weight.cancel"); Spacer(minLength: 0) }.disabled(busy)
                ZStack(alignment: .top) {
                    Color.white
                    Group {
                        if let target = model.snapshot.weightTarget {
                            Text("weight.targetProgress \(target.target.formatted(.number.precision(.fractionLength(1)).locale(locale))) \((target.progress(at: value)*100).formatted(.number.precision(.fractionLength(1)).locale(locale)))")
                        } else { Text("weight.targetHint") }
                    }.font(.system(size: 10*s)).foregroundStyle(Color(white: 0.3)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15*s).padding(.top, 15*s)
                    Text(value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "kg").font(.system(size: 32*s, weight: .bold)).foregroundStyle(KeepUpStyle.accent).padding(.top, 60*s).accessibilityIdentifier("weight.value")
                    WeightBMILabel(weight: value, height: model.snapshot.profile?.height, locale: locale).font(.system(size: 13*s)).padding(.top, 110*s)
                    if ready { WeightRuler(value: $value, range: 5...200, large: true).frame(height: 80*s).padding(.horizontal, 25*s).padding(.top, 182*s) }
                    Image("target_weight__arrow_2").resizable().frame(width: 14*s, height: 74*s).padding(.top, 158*s).allowsHitTesting(false)
                    VStack {
                        Spacer()
                        if let error { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red) }
                        Button { Task { await save() } } label: { Text("action.checkIn").font(.system(size: 18*s)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 55*s).background(KeepUpStyle.accent, in: RoundedRectangle(cornerRadius: 10*s)) }
                            .disabled(busy).accessibilityIdentifier("weight.save").padding(.horizontal, 15*s).padding(.bottom, bottom)
                    }
                }.frame(height: height).clipShape(UnevenRoundedRectangle(topLeadingRadius: 10*s, topTrailingRadius: 10*s))
                    .overlay(alignment: .topTrailing) {
                        Button { reminder = true } label: { Image("card_popup_ic_clock").resizable().frame(width: 70*s, height: 35*s) }.padding(.trailing, 10*s).offset(y: -47*s).accessibilityIdentifier("weight.reminder")
                    }
            }.ignoresSafeArea().onAppear { if !ready { value = model.latestWeight; ready = true } }
                .fullScreenCover(isPresented: $reminder) { if let card = OriginalCatalog.card(50) { ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) } }
        }.ignoresSafeArea()
    }
    private func save() async {
        busy = true; defer { busy = false }
        if await model.add(CheckInDraft(id: draftID, cardID: "punchcard.50", day: day, timeZoneID: TimeZone.current.identifier, quantity: value, note: "")) { onSaved() }
        else { error = model.actionError; model.actionError = nil }
    }
}

struct WeightBMILabel: View {
    let weight: Double
    let height: Double?
    let locale: Locale
    var highlight = true
    var body: some View {
        if let bmi = WeightMetrics.bmi(weight: weight, height: height) {
            let value = Text(bmi.formatted(.number.precision(.fractionLength(1)).locale(locale))).foregroundStyle(highlight ? Color(hex: 0xF9414D).opacity(0.8) : .white)
            Text("BMI=\(value), \(localized(WeightMetrics.descriptionKey(bmi: bmi), locale))").lineLimit(1).minimumScaleFactor(0.8)
        } else { Text("weight.heightNeeded").foregroundStyle(.secondary) }
    }
}
