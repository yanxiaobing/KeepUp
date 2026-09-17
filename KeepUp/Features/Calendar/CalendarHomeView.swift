import SwiftUI

struct CalendarHomeView: View {
    @Binding var selectedDate: Date
    let openCatalog: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("preference.monthMode") private var isMonthMode = false
    @State private var showingTheme = false
    @State private var scheduleDetail: ScheduledCard?
    @State private var detail: CheckInEntry?
    @State private var editing: CheckInEntry?
    @State private var pendingCard: HabitCard?
    @State private var reminderCard: HabitCard?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2 // PunchCard starts the displayed week on Monday.
        return calendar
    }
    private var selectedDay: LocalDay { LocalDay(date: selectedDate) }
    private var monthTitle: String {
        let year = calendar.component(.year, from: selectedDate)
        let month = selectedDate.formatted(.dateTime.month(.wide).locale(locale))
        return "\(year) | \(month)"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Image(CalendarTheme.selected.city_image).resizable()
                        .frame(width: geometry.size.width, height: 136 * geometry.size.width / 375)
                        .frame(height: max(0, 34 + 136 * geometry.size.width / 375 - geometry.safeAreaInsets.top), alignment: .bottom)
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        calendarHeader
                        calendarBody
                        recordGrid(width: geometry.size.width)
                    }.padding(.horizontal, 15)
                }
                .background(KeepUpStyle.theme.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingTheme) { ThemeListView() }
            .fullScreenCover(item: $pendingCard) { card in
                ComposeEntryView(card: card, day: selectedDay, onSaved: { pendingCard = nil }, onCancel: { pendingCard = nil })
            }
            .fullScreenCover(item: $reminderCard) { card in ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) }
            .fullScreenCover(item: $scheduleDetail) { schedule in
                if let card = model.snapshot.cards.first(where: { $0.id == schedule.cardID }) { ScheduledCardView(card: card, day: schedule.day, existing: schedule) }
            }
            .fullScreenCover(item: $detail) { entry in
                if let card = model.card(for: entry) { EntryDetailView(entry: entry, card: card) }
            }
            .fullScreenCover(item: $editing) { entry in
                if let card = model.card(for: entry) { EntryContentEditor(entry: entry, card: card) }
            }
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: 0) {
            Text(monthTitle).font(.system(size: 18)).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityIdentifier("calendar.month")
            Spacer(minLength: 4)
            if !calendar.isDateInToday(selectedDate) {
            Button { selectedDate = .now } label: {
                Group {
                    if locale.language.languageCode?.identifier == "zh" {
                        Image("homepage_btn_ic_today").resizable().scaledToFit().frame(width: 24, height: 24)
                    } else {
                        Text("calendar.today").font(.system(size: 11, weight: .medium))
                    }
                }.frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("calendar.today")).accessibilityIdentifier("calendar.today")
            }
            OriginalIconButton(image: "skin_logo_\(CalendarTheme.selected.id)", label: "theme.preview") { showingTheme = true }.accessibilityIdentifier("theme.open")
        }
        .foregroundStyle(.white).padding(.leading, 18).padding(.trailing, 8)
        .background(KeepUpStyle.header, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
    }

    private var calendarBody: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                DatePicker("calendar.chooseDate", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact).padding(14)
            } else {
                let monthStart = calendar.dateInterval(of: .month, for: selectedDate)!.start
                let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
                let start = isMonthMode
                    ? calendar.date(byAdding: .day, value: -offset, to: monthStart)!
                    : calendar.dateInterval(of: .weekOfYear, for: selectedDate)!.start
                let count = isMonthMode ? ((offset + calendar.range(of: .day, in: .month, for: selectedDate)!.count + 6) / 7) * 7 : 7
                let daysWithRecords = Set(model.snapshot.entries.map(\.day))
                let plannedDays = Set(model.snapshot.schedules.filter { $0.day >= LocalDay(date: .now) }.map(\.day))
                let weekdays = calendar.veryShortStandaloneWeekdaySymbols
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdays[(index + 1) % 7]).font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 22)
                    }
                    ForEach((0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }, id: \.self) { date in
                        let day = LocalDay(date: date)
                        let selected = day == selectedDay
                        let today = calendar.isDateInToday(date)
                        let recorded = daysWithRecords.contains(day)
                        Button { selectedDate = date } label: {
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.custom("HelveticaNeue-Light", size: 12))
                                .foregroundStyle(recorded && !today ? Color.white : Color.primary.opacity(0.7))
                                .frame(width: 26, height: 26)
                                .background(today ? KeepUpStyle.day : (recorded ? KeepUpStyle.card : .clear), in: Circle())
                                .overlay(Circle().stroke(plannedDays.contains(day) ? Color(hex: 0xBABDC2) : .clear, lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().stroke(selected ? KeepUpStyle.day : .clear, lineWidth: 1))
                                .frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .opacity(calendar.isDate(date, equalTo: selectedDate, toGranularity: .month) ? 1 : 0.35)
                            
                            .accessibilityLabel(Text(date, format: .dateTime.year().month().day()))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("day.\(day.rawValue)")
                    }
                }.padding(.horizontal, 8).padding(.top, 9)
                Button { isMonthMode.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(isMonthMode ? "homepage_tips_ic_up" : "homepage_tips_ic_down")
                            .resizable().scaledToFit().frame(width: 10, height: 10)
                        Text(isMonthMode ? "calendar.showWeek" : "calendar.showMonth").font(.system(size: 11))
                    }.foregroundStyle(.secondary).offset(y: -5).frame(maxWidth: .infinity).frame(height: 19)
                }.buttonStyle(.plain).accessibilityIdentifier("calendar.scope")
            }
        }
        .background(KeepUpStyle.surface, in: UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.grid")
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) { movePage(value.translation.width < 0 ? 1 : -1) }
            else { isMonthMode = value.translation.height > 0 }
        })
    }

    private func recordGrid(width: CGFloat) -> some View {
        let scale = width / 375
        let itemWidth = 88 * scale
        let spacing = (width - itemWidth * 3 - 34) / 4
        return ZStack(alignment: .bottom) {
            if !isMonthMode && model.entries(on: selectedDay).count <= 3 {
                Image("pic_week_pass").resizable().scaledToFit().frame(height: 100).accessibilityHidden(true)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3), spacing: 20) {
                    ForEach(model.entries(on: selectedDay).reversed()) { entry in
                        if let card = model.card(for: entry) {
                            Button { detail = entry } label: {
                                CalendarRecordCard(entry: entry, card: card, scale: scale, wake: model.snapshot.wakeUps[entry.id])
                                    .overlay(alignment: .bottom) { weeklyProgress(card: card, day: selectedDay).padding(.bottom, 19) }
                            }.buttonStyle(.plain).accessibilityIdentifier("entry.\(entry.id)")
                                .contextMenu {
                                    if !model.snapshot.archivedCardIDs.contains(card.id) { Button("reminder.title") { reminderCard = card }.accessibilityIdentifier("entry.reminder") }
                                    Button("entry.viewCard") { detail = entry }.accessibilityIdentifier("entry.viewCard")
                                    Button("content.edit") { editing = entry }.accessibilityIdentifier("entry.editContent")
                                }
                        }
                    }
                    ForEach(model.snapshot.schedules.filter { $0.day == selectedDay }) { schedule in
                        if let card = model.snapshot.cards.first(where: { $0.id == schedule.cardID }) {
                            Button { if schedule.day == LocalDay(date: .now), !model.snapshot.archivedCardIDs.contains(card.id), ![1,2,96].contains(OriginalCatalog.item(card)?.number ?? 0) { pendingCard = card } else { scheduleDetail = schedule } } label: {
                                ScheduledCalendarCard(schedule: schedule, card: card, scale: scale)
                            }.buttonStyle(.plain).accessibilityIdentifier("schedule.card.\(card.id)")
                                .contextMenu { Button("schedule.title") { scheduleDetail = schedule } }
                        }
                    }
                    if selectedDay == LocalDay(date: .now) {
                        ForEach(model.snapshot.targets.filter { $0.isPinned }) { target in
                            if let card = model.snapshot.cards.first(where: { $0.id == target.cardID }), !model.entries(on: selectedDay).contains(where: { $0.cardID == card.id }), !model.snapshot.schedules.contains(where: { $0.cardID == card.id && $0.day == selectedDay }) {
                                Button { pendingCard = card } label: {
                                    VStack(spacing: 0) {
                                        Image(card.id == "punchcard.63" ? "ic_early_card_undone" : card.id == "punchcard.50" ? "home_heavy_pic_todo" : "card_icon_todo").resizable().scaledToFit().frame(width: 74*scale, height: 87*scale)
                                            .frame(maxHeight: .infinity)
                                        Text(LocalizedStringKey(card.titleKey)).font(.system(size: 11)).foregroundStyle(.white)
                                            .frame(maxWidth: .infinity).frame(height: 18).background(Color(white: 0.72))
                                    }.frame(width: itemWidth, height: 116*scale).background(.white)
                                        .overlay(alignment: .topLeading) {
                                            Text("reminder.todo").font(.custom("HelveticaNeue-Light", size: 12)).foregroundStyle(.white).padding(.horizontal, 6).frame(height: 18)
                                                .background { HStack(spacing: 0) { Color(hex: 0xBABDC2); Image("babdc2").resizable().frame(width: 10) } }
                                                .overlay(alignment: .leading) { Image("homepage_tag_light").resizable().frame(width: 6, height: 18) }
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if target.reminderEnabled { Image("card_detail_ic_clock").resizable().frame(width: 16, height: 16).padding(3) }
                                        }
                                        .overlay { Image("xbcalendarItemCover").resizable().allowsHitTesting(false) }
                                        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                                        .overlay(alignment: .bottom) { weeklyProgress(card: card, day: selectedDay).padding(.bottom, 19) }
                                }.buttonStyle(.plain).accessibilityIdentifier("target.pending.\(card.id)")
                                    .contextMenu { Button("reminder.title") { reminderCard = card } }
                            }
                        }
                    }
                    if selectedDay > LocalDay(date: .now) || selectedDay < LocalDay(date: calendar.date(byAdding: .day, value: -1, to: .now)!) {
                        Button(action: openCatalog) {
                            VStack(spacing: 0) {
                                Image(selectedDay > LocalDay(date: .now) ? "home_note_ic_plus" : "homepage_ic_budacard").resizable().scaledToFit()
                                    .frame(width: 45, height: 45).frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(selectedDay > LocalDay(date: .now) ? "schedule.add" : "calendar.backfill").font(.system(size: 11)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 18).background(Color.gray.opacity(0.45))
                            }.frame(width: itemWidth, height: 116 * scale)
                                .overlay(Rectangle().strokeBorder(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }.buttonStyle(.plain).accessibilityIdentifier("calendar.add")
                    }
                }.padding(.horizontal, spacing).padding(.vertical, 15)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(KeepUpStyle.background)
    }

    @ViewBuilder private func weeklyProgress(card: HabitCard, day: LocalDay) -> some View {
        if day == LocalDay(date: .now), let target = model.snapshot.targets.first(where: { $0.cardID == card.id && $0.showsProgress }) {
            let count = target.completedDays(entries: model.snapshot.entries, day: day).count
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(0..<count, id: \.self) { _ in Capsule().fill(KeepUpStyle.card).frame(width: max(0, (geometry.size.width-8)/7), height: 2) }
                }.frame(maxWidth: .infinity)
            }.frame(height: 2).accessibilityElement(children: .ignore).accessibilityLabel(Text("reminder.progressCount \(count)"))
                .accessibilityIdentifier("target.progress.\(card.id)")
        }
    }

    private func movePage(_ offset: Int) {
        let component: Calendar.Component = isMonthMode ? .month : .weekOfYear
        let candidate = calendar.date(byAdding: component, value: offset, to: selectedDate)!
        selectedDate = candidate
    }
}

struct CalendarRecordCard: View {
    let entry: CheckInEntry
    let card: HabitCard
    var scale: CGFloat = 1
    var wake: WakeUpRecord? = nil
    private var cardColor: Color { card.id == "punchcard.50" ? Color(hex: 0xF5D039) : KeepUpStyle.card }
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
            if let wake { WakeUpClock(time: wake.time, timeZoneID: wake.timeZoneID, compact: true).frame(width: 72*scale, height: 72*scale).frame(maxHeight: .infinity).offset(y: -9*scale) } else {
            Image(card.cardImage).resizable().frame(width: 74 * scale, height: 87 * scale)
                .frame(maxHeight: .infinity).offset(y: scale > 1 ? -11 : -8)
            }
            if let quantity = entry.quantity {
                HStack(spacing: 1) {
                    Text(quantity, format: .number.precision(.fractionLength(card.id == "punchcard.50" ? 1...1 : 0...1)))
                    Text(LocalizedStringKey(entry.unit.titleKey))
                }.font(.system(size: 10)).foregroundStyle(cardColor)
                    .padding(.horizontal, 4).padding(.vertical, 2).background(.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(cardColor, lineWidth: 1))
                    .padding(.bottom, 22)
            }
            Text(LocalizedStringKey(card.titleKey)).font(.system(size: 11)).foregroundStyle(.white)
                .lineLimit(1).frame(maxWidth: .infinity).frame(height: 18).background(wake == nil ? cardColor : Color(hex: 0x3DB9A9))
        }.frame(width: 88 * scale, height: 116 * scale)
            .overlay(alignment: .topLeading) {
                if wake?.isEarly == true { Text("wake.earlyBadge").font(.system(size: 12)).foregroundStyle(.white).padding(.horizontal, 6).frame(height: 18).background(Color(hex: 0x3DB9A9)) }
            }
            .overlay { Image("xbcalendarItemCover").resizable().allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1).accessibilityElement(children: .combine)
    }
}
