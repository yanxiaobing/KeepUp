import SwiftUI

/// Frame values follow BCPunchCardKeyboardView / BCPunchCardUnUnitView.
/// The overlay belongs to the catalog, avoiding the insets of an iOS sheet.
struct ComposeEntryView: View {
    let card: HabitCard
    let day: LocalDay
    var onSaved: () -> Void = {}
    var onCancel: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var wakeTime = Date.now
    @State private var confirmingEarly = false
    private var isWake: Bool { card.id == "punchcard.63" }
    @State private var quantity = ""
    @State private var isSaving = false
    @State private var errorKey: String?
    @State private var draftID = UUID().uuidString
    @State private var showingReminder = false
    private var valid: Bool { card.unit == .none || (Double(quantity) ?? 0) > 0 }
    private var occurrence: Int { model.snapshot.entries.filter { $0.cardID == card.id }.count + 1 }

    var body: some View {
        if card.id == "punchcard.50" { WeightEntryView(day: day, onSaved: onSaved, onCancel: onCancel) } else {
        GeometryReader { geometry in
            let scale = geometry.size.width / 375
            let bottom = max(geometry.safeAreaInsets.bottom, 34)
            let numeric = card.unit != .none
            let height = (numeric ? 460 : 315) * scale + bottom
            ZStack(alignment: .bottom) {
                Color(red: 34/255, green: 34/255, blue: 34/255).opacity(0.8)
                VStack(spacing: 0) {
                    Button { if !isSaving { onCancel() } } label: {
                        Color.clear.contentShape(Rectangle())
                    }.buttonStyle(.plain).frame(height: max(0, geometry.size.height-height))
                        .accessibilityLabel(Text("action.cancel")).accessibilityIdentifier("entry.cancel")
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 10 * scale) {
                        if isWake { Image("ic_wake_up").resizable().frame(width: 35*scale, height: 35*scale) } else { CardSymbol(card: card, size: 60*scale) }
                        VStack(alignment: .leading, spacing: 10 * scale) {
                            if isWake { Text("wake.time").font(.system(size: 16*scale)) } else if numeric {
                                HStack(spacing: 7 * scale) {
                                    Text(LocalizedStringKey(card.titleKey)).font(.system(size: 16 * scale, weight: .bold))
                                    Text(quantity.isEmpty ? "0" : quantity).foregroundStyle(KeepUpStyle.accent)
                                        .accessibilityIdentifier("entry.quantity")
                                    Text(LocalizedStringKey(card.unit.titleKey))
                                }.font(.system(size: 16 * scale))
                                Group {
                                    if let calories = ActivityEnergy.calories(card: card, quantity: Double(quantity)) {
                                        Text(ActivityEnergy.description(calories: calories, locale: locale))
                                            .accessibilityIdentifier("energy.preview")
                                    } else { Text("entry.enterValue") }
                                }.font(.system(size: 12 * scale)).foregroundStyle(Color(white: 0.43)).fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(verbatim: String(format: localized("entry.occurrence %lld", locale), Int64(occurrence))).font(.system(size: 18 * scale, weight: .bold)).foregroundStyle(KeepUpStyle.accent)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, (isWake ? 25 : 15) * scale).frame(height: (isWake ? 69 : 94) * scale)
                    Rectangle().fill(Color(white: 0.28).opacity(0.2)).frame(height: 1 / 3).padding(.horizontal, 15 * scale)
                    if numeric {
                        numberPad(scale: scale).frame(height: 276 * scale).padding(.top, 20 * scale)
                        Spacer(minLength: 0)
                    } else if isWake {
                        WakeUpTimePicker(selection: $wakeTime, scale: scale, upperBound: Date.now)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(LocalizedStringKey(card.titleKey)).font(.system(size: 38)).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let errorKey { Text(LocalizedStringKey(errorKey)).font(.footnote).foregroundStyle(.red) }
                    Button { if isWake && Calendar.current.component(.hour, from: .now) < 5 { confirmingEarly = true } else { Task { await save() } } } label: {
                        Group {
                            if isSaving { ProgressView().tint(.white) }
                            else { Text("action.checkIn").font(.system(size: 18 * scale)) }
                        }.frame(maxWidth: .infinity).frame(height: 55 * scale).foregroundStyle(.white)
                            .background(valid ? KeepUpStyle.accent : Color(red: 196/255, green: 198/255, blue: 203/255), in: RoundedRectangle(cornerRadius: 10 * scale))
                    }.buttonStyle(.plain).disabled(!valid || isSaving).accessibilityIdentifier("entry.save")
                        .padding(.horizontal, 15 * scale).padding(.bottom, bottom)
                }.frame(height: height).background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 10 * scale, topTrailingRadius: 10 * scale))
                    .foregroundStyle(Color(red: 72/255, green: 72/255, blue: 77/255))
                    .overlay(alignment: .topTrailing) {
                        Button { showingReminder = true } label: {
                            Image("card_popup_ic_clock").resizable().scaledToFit().frame(width: 70 * scale, height: 35 * scale)
                        }.padding(.trailing, 10 * scale).offset(y: -47 * scale).accessibilityLabel(Text("profile.alarms")).accessibilityIdentifier("entry.reminder")
                    }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .alert("wake.tooEarly", isPresented: $confirmingEarly) {
                    Button("action.checkIn") { Task { await save() } }.accessibilityIdentifier("wake.confirm")
                    Button("action.cancel", role: .cancel) {}
                }
                .fullScreenCover(isPresented: $showingReminder) { ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) }
        }.ignoresSafeArea()
        }
    }

    private func numberPad(scale: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(["7", "8", "9", "4", "5", "6", "1", "2", "3", "blank", "0", "delete"], id: \.self) { key in
                Button { press(key) } label: {
                    Group {
                        if key == "delete" { Image("punch_card_delete").resizable().scaledToFit().frame(width: 28 * scale, height: 28 * scale) }
                        else { Text(key == "blank" ? "" : key).font(.system(size: 24 * scale)) }
                    }.frame(maxWidth: .infinity).frame(height: 69 * scale).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(isSaving || key == "blank").accessibilityIdentifier("keypad." + key)
                    .accessibilityLabel(key == "delete" ? Text("action.backspace") : Text(key))
            }
        }
    }
    private func press(_ key: String) {
        if key == "delete" { if !quantity.isEmpty { quantity.removeLast() }; return }
        guard quantity.count < (card.unit == .minutes ? 4 : 5) else { return }
        quantity = quantity == "0" ? key : quantity + key
    }
    private func save() async {
        guard valid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let draft = CheckInDraft(wakeTime: isWake ? wakeTime : nil, id: draftID, cardID: card.id, day: day, timeZoneID: TimeZone.current.identifier, quantity: Double(quantity), note: "")
        if await model.add(draft) { onSaved() }
        else { errorKey = model.actionError; model.actionError = nil }
    }
}
