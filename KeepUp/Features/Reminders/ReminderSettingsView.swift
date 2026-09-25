import SwiftUI
import UserNotifications

struct ReminderSettingsView: View {
    let card: HabitCard
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var value: CardTarget
    @State private var original: CardTarget
    @State private var saving = false
    @State private var confirmingDiscard = false
    @State private var timePicker = false
    @State private var error: String?
    private let ink = Color(red: 105/255, green: 104/255, blue: 111/255)
    private var deletesTarget: Bool { value.isEmpty && !original.isEmpty }
    init(card: HabitCard, target: CardTarget?) {
        self.card = card
        let initial = target ?? CardTarget(cardID: card.id)
        _value = State(initialValue: initial); _original = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width/375
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 23*s) {
                            Toggle(isOn: $value.isPinned) { Text("reminder.pin \(localized(card.titleKey, locale))") }
                                .frame(height: 18*s).accessibilityIdentifier("reminder.pin")
                            illustration("alarm_clock_set_tips_a_ic", text: "reminder.pinHelp", height: 150, scale: s)
                        }.padding(23*s).padding(.horizontal, -8*s)
                        separator
                        VStack(spacing: 0) {
                            Toggle("reminder.alarm", isOn: $value.reminderEnabled).frame(height: 18*s).accessibilityIdentifier("reminder.enabled")
                            if value.reminderEnabled && authorizationStatus == .denied {
                                ReminderPermissionNotice().padding(.top, 16*s)
                            }
                            Button { timePicker = true } label: {
                                HStack(spacing: 15) {
                                    Text(value.timeText).font(.system(size: 45*s))
                                    Image(systemName: "chevron.down").font(.system(size: 10))
                                }.foregroundStyle(value.reminderEnabled ? ink : Color(white: 0.78))
                            }.disabled(!value.reminderEnabled).padding(.top, 30*s).accessibilityIdentifier("reminder.time")
                            HStack(spacing: 12) {
                                ForEach(1...7, id: \.self) { day in
                                    Button {
                                        if value.weekdays.contains(day) { value.weekdays.removeAll { $0 == day } }
                                        else { value.weekdays.append(day); value.weekdays.sort() }
                                    } label: {
                                        Text(weekday(day)).font(.system(size: locale.identifier.hasPrefix("zh") ? 12 : 10))
                                            .frame(width: max(0, (geometry.size.width-30*s-72)/7), height: max(0, (geometry.size.width-30*s-72)/7))
                                            .foregroundStyle(value.weekdays.contains(day) ? .white : ink)
                                            .background(value.weekdays.contains(day) ? (value.reminderEnabled ? Color(red: 251/255, green: 192/255, blue: 45/255) : Color(white: 0.78)) : Color(white: 0.96), in: Circle())
                                    }.buttonStyle(.plain).disabled(!value.reminderEnabled).accessibilityIdentifier("reminder.day.\(day)")
                                        .accessibilityAddTraits(value.weekdays.contains(day) ? .isSelected : [])
                                }
                            }.padding(.top, 30*s)
                            Text("reminder.afterCheckIn").font(.system(size: 12)).foregroundStyle(Color(white: 0.7)).padding(.vertical, 23*s)
                            illustration("alarm_clock_set_tips_b_ic", text: "reminder.alarmHelp", height: 175, scale: s)
                        }.padding(23*s).padding(.horizontal, -8*s)
                        separator
                        VStack(spacing: 23*s) {
                            Toggle("reminder.progress", isOn: $value.showsProgress).frame(height: 18*s).accessibilityIdentifier("reminder.progress")
                            illustration("alarm_clock_set_tips_c_ic", text: "reminder.progressHelp", height: 150, scale: s)
                        }.padding(23*s).padding(.horizontal, -8*s)
                    }.font(.system(size: 16*s)).foregroundStyle(ink).tint(Color(red: 251/255, green: 192/255, blue: 45/255)).background(.white)
                }.background(Color(white: 246/255))
            }
            .task(id: scenePhase) {
                if scenePhase == .active { authorizationStatus = await ReminderScheduler.shared.authorizationStatus() }
            }
            .navigationTitle("reminder.title").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if value != original { confirmingDiscard = true } else { dismiss() } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(Text("action.back")).accessibilityIdentifier("reminder.close")
                        .tint(KeepUpStyle.navigationTint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { Image(systemName: deletesTarget ? "trash" : "checkmark") }
                        .disabled(saving || value == original)
                        .accessibilityLabel(Text(LocalizedStringKey(deletesTarget ? "action.delete" : "action.save")))
                        .accessibilityIdentifier("reminder.save")
                        .tint(deletesTarget ? .red : KeepUpStyle.navigationTint)
                }
            }
            .confirmationDialog("reminder.discardQuestion", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("content.discard", role: .destructive) { dismiss() }.accessibilityIdentifier("reminder.discard")
                Button("action.cancel", role: .cancel) {}
            }
            .sheet(isPresented: $timePicker) {
                VStack {
                    HStack {
                        Spacer()
                        Button { timePicker = false } label: { Image(systemName: "checkmark") }
                            .padding().accessibilityLabel(Text("action.done"))
                            .accessibilityIdentifier("reminder.timeDone").tint(KeepUpStyle.navigationTint)
                    }
                    DatePicker("reminder.time", selection: Binding(get: {
                        Calendar.current.date(from: DateComponents(hour: value.hour, minute: value.minute)) ?? .now
                    }, set: { date in value.hour = Calendar.current.component(.hour, from: date); value.minute = Calendar.current.component(.minute, from: date) }), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().accessibilityIdentifier("reminder.timePicker")
                }.presentationDetents([.height(300)])
            }
            .alert("error.title", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                if error == "reminder.permissionDenied", authorizationStatus == .denied {
                    Button("reminder.openSettings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Button("action.ok", role: .cancel) {}
            } message: { Text(LocalizedStringKey(error ?? "error.storage")) }
        }
    }
    private var separator: some View { Color.black.opacity(0.1).frame(height: 0.5).padding(.horizontal, 15) }
    private func weekday(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.locale = locale
        if locale.identifier.hasPrefix("zh") { return ["周一","周二","周三","周四","周五","周六","周日"][day-1] }
        return calendar.shortStandaloneWeekdaySymbols[day % 7]
    }
    private func illustration(_ asset: String, text: String, height: CGFloat, scale s: CGFloat) -> some View {
        Image(asset).resizable().frame(height: height*s)
            .overlay(alignment: .topLeading) {
                if !locale.identifier.hasPrefix("zh") {
                    if asset == "alarm_clock_set_tips_a_ic" {
                        Text(verbatim: "To do").font(.system(size: 14*s)).foregroundStyle(.white)
                            .frame(width: 46*s, height: 23*s).background(Color(white: 0.72), in: UnevenRoundedRectangle(topLeadingRadius: 6*s, bottomTrailingRadius: 9*s))
                            .offset(x: 31*s, y: 11*s)
                    } else if asset == "alarm_clock_set_tips_b_ic" {
                        VStack(spacing: 4*s) {
                            Text(verbatim: "6:32").font(.system(size: 24*s, weight: .ultraLight)).padding(.top, 20*s)
                            Text(verbatim: "Wednesday, September 13").font(.system(size: 6*s))
                            VStack(alignment: .leading, spacing: 3*s) {
                                Text("KeepUp").font(.system(size: 6*s, weight: .bold))
                                Text(verbatim: "Time for your check-in!").font(.system(size: 7*s))
                            }.foregroundStyle(Color(white: 0.25)).padding(5*s).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 5*s)).padding(.horizontal, 3*s).padding(.top, 6*s)
                            Spacer(minLength: 0)
                        }.foregroundStyle(.white).frame(width: 119*s, height: 146*s)
                            .background(LinearGradient(colors: [Color(red: 0.3, green: 0.64, blue: 0.68), Color(red: 0.1, green: 0.45, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .offset(x: 29*s, y: 30*s).accessibilityHidden(true)
                    }
                }
            }
            .overlay(alignment: .trailing) {
                Text(LocalizedStringKey(text)).font(.system(size: 13*s)).lineSpacing(11*s).frame(width: 150*s, alignment: .leading).padding(.trailing, 15*s)
            }.background(Color(white: 246/255)).clipShape(RoundedRectangle(cornerRadius: 8*s))
    }
    private func save() async {
        guard !saving else { return }
        do { value = try value.validated() } catch { self.error = "reminder.invalid"; return }
        saving = true; defer { saving = false }
        if value.reminderEnabled {
            do {
                let granted = try await ReminderScheduler.shared.requestPermission()
                authorizationStatus = await ReminderScheduler.shared.authorizationStatus()
                guard granted else { error = "reminder.permissionDenied"; return }
            } catch {
                authorizationStatus = await ReminderScheduler.shared.authorizationStatus()
                self.error = "reminder.permissionDenied"; return
            }
        }
        if await model.saveTarget(value) { dismiss() }
        else { error = model.actionError; model.actionError = nil }
    }
}

struct ReminderListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var selected: HabitCard?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if authorizationStatus == .denied && model.snapshot.targets.contains(where: \.reminderEnabled) {
                        ReminderPermissionNotice().padding(15)
                    }
                    ForEach(model.snapshot.targets) { target in
                        if let card = model.snapshot.cards.first(where: { $0.id == target.cardID }) {
                            Button { selected = card } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(target.timeText).font(.system(size: 30))
                                        Text(target.reminderEnabled ? days(target) : localized("reminder.notSet", locale)).font(.system(size: 14))
                                    }
                                    Spacer()
                                    Text(LocalizedStringKey(card.titleKey)).font(.system(size: 17)).foregroundStyle(Color(white: 0.58))
                                    Image("me_arrow_ic").resizable().frame(width: 14, height: 14)
                                }.padding(.horizontal, 15).frame(height: 90).background(.white)
                            }.buttonStyle(.plain).accessibilityIdentifier("reminder.target.\(card.id)")
                            Divider().padding(.leading, 15)
                        }
                    }
                    if model.snapshot.targets.isEmpty { Text("reminder.empty").font(.system(size: 14)).foregroundStyle(.secondary).padding(40) }
                }
            }.task(id: scenePhase) {
                if scenePhase == .active { authorizationStatus = await ReminderScheduler.shared.authorizationStatus() }
            }.background(Color(white: 246/255)).navigationTitle("profile.alarms").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(Text("action.close")).accessibilityIdentifier("reminder.listClose").tint(KeepUpStyle.navigationTint) } }
                .fullScreenCover(item: $selected) { card in ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) }
        }
    }
    private func days(_ target: CardTarget) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.locale = locale
        return target.weekdays.map { calendar.shortStandaloneWeekdaySymbols[$0 % 7] }.joined(separator: " · ")
    }
}

private struct ReminderPermissionNotice: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("reminder.permissionDisabled", systemImage: "bell.slash")
                .font(.footnote).foregroundStyle(.secondary)
            Button("reminder.openSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.font(.footnote.weight(.semibold)).accessibilityIdentifier("reminder.openSettings")
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("reminder.permissionNotice")
    }
}
