import SwiftUI

struct CalendarHomeView: View {
    @Binding var selectedDate: Date
    let openCatalog: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.monthMode) private var isMonthMode
    @State private var showingTheme = false
    @State private var showingRunning = false
    @State private var scheduleDetail: ScheduledCard?
    @State private var detail: CheckInEntry?
    @State private var pendingDay = LocalDay(date: .now)
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

    private var dayEntries: [CheckInEntry] { model.entries(on: selectedDay) }
    private var daySchedules: [ScheduledCard] { model.snapshot.schedules.filter { $0.day == selectedDay } }
    private var pendingCards: [HabitCard] {
        guard selectedDay == LocalDay(date: .now) else { return [] }
        let recorded = Set(dayEntries.map(\.cardID))
        let scheduled = Set(daySchedules.map(\.cardID))
        return model.snapshot.targets.filter { $0.isPinned }.compactMap { target in
            guard !recorded.contains(target.cardID), !scheduled.contains(target.cardID),
                  !model.snapshot.archivedCardIDs.contains(target.cardID) else { return nil }
            return model.snapshot.cards.first { $0.id == target.cardID }
        }
    }
    private var showsAddCard: Bool {
        selectedDay > LocalDay(date: .now) || selectedDay < LocalDay(date: calendar.date(byAdding: .day, value: -1, to: .now)!)
    }
    private var visibleCardCount: Int {
        dayEntries.count + daySchedules.count + pendingCards.count + (showsAddCard ? 1 : 0)
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
                        if model.running.session != nil {
                            Button { showingRunning = true } label: {
                                Label("running.resumeActivity", systemImage: model.running.session?.kind == .cycling ? "bicycle" : "figure.run")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }.buttonStyle(.plain).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 10).accessibilityIdentifier("running.resumeActivity")
                        }
                        recordGrid(width: geometry.size.width)
                    }.padding(.horizontal, 15)
                }
                .background(KeepUpStyle.theme.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingTheme) { ThemeListView() }
            .fullScreenCover(isPresented: $showingRunning) { RunningView() }
            .fullScreenCover(item: $pendingCard) { card in
                if card.id == "punchcard.1" { StepsView(day: pendingDay) }
                else if ["punchcard.2", "punchcard.96"].contains(card.id) { RunningView(kind: card.id == "punchcard.96" ? .cycling : .outdoor) }
                else { ComposeEntryView(card: card, day: pendingDay, onSaved: { pendingCard = nil }, onCancel: { pendingCard = nil }) }
            }
            .fullScreenCover(item: $reminderCard) { card in ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) }
            .fullScreenCover(item: $scheduleDetail) { schedule in
                if let card = model.snapshot.cards.first(where: { $0.id == schedule.cardID }) { ScheduledCardView(card: card, day: schedule.day, existing: schedule) }
            }
            .fullScreenCover(item: $detail) { entry in
                if entry.cardID == "punchcard.1" { StepsView(day: entry.day, followsToday: false) }
                else if let card = model.card(for: entry) {
                    if ["punchcard.2", "punchcard.96"].contains(entry.cardID) { RunningRecordView(entry: entry, card: card) }
                    else { EntryDetailView(entry: entry, card: card) }
                }
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
                        let planned = plannedDays.contains(day) && !recorded && !today
                        let selectionColor = today ? KeepUpStyle.day : (recorded ? KeepUpStyle.card : (planned ? Color(hex: 0xBABDC2) : KeepUpStyle.day))
                        Button { selectedDate = date } label: {
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.custom("HelveticaNeue-Light", size: 12))
                                .foregroundStyle(recorded && !today ? Color.white : Color.primary.opacity(0.7))
                                .frame(width: 26, height: 26)
                                .background(today ? KeepUpStyle.day : (recorded ? KeepUpStyle.card : .clear), in: Circle())
                                .overlay(Circle().stroke(planned ? Color(hex: 0xBABDC2) : .clear, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                                .padding(3)
                                .overlay(Circle().stroke(selected ? selectionColor : .clear, lineWidth: 1))
                                .frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .opacity(calendar.isDate(date, equalTo: selectedDate, toGranularity: .month) ? 1 : 0.35)
                            
                            .accessibilityLabel(Text(date, format: .dateTime.year().month().day()))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("day.\(day.rawValue)")
                    }
                }.padding(.horizontal, 8).padding(.top, 9)
                Button { setMonthMode(!isMonthMode) } label: {
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
            else { setMonthMode(value.translation.height > 0) }
        })
    }

    private func recordGrid(width: CGFloat) -> some View {
        let scale = width / 375
        let itemWidth = 88 * scale
        let spacing = (width - itemWidth * 3 - 34) / 4
        return ZStack(alignment: .bottom) {
            if !isMonthMode && visibleCardCount <= 3 {
                Image("pic_week_pass").resizable().scaledToFit().frame(height: 100).accessibilityHidden(true)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3), spacing: 20) {
                    ForEach(dayEntries.sorted { lhs, rhs in
                        if (lhs.cardID == "punchcard.63") != (rhs.cardID == "punchcard.63") { return lhs.cardID == "punchcard.63" }
                        return lhs.createdAt < rhs.createdAt
                    }) { entry in
                        if let card = model.card(for: entry) {
                            CalendarInteractiveCard(identifier: "entry.\(entry.id)", label: entryLabel(entry, card: card),
                                actions: menuActions(card: card, entry: entry), tap: { detail = entry }) {
                                CalendarTicketCard(card: card, scale: scale, entry: entry, wake: model.snapshot.wakeUps[entry.id], progress: weeklyProgress(card))
                            }
                        }
                    }
                    ForEach(daySchedules) { schedule in
                        if let card = model.snapshot.cards.first(where: { $0.id == schedule.cardID }) {
                            CalendarInteractiveCard(identifier: "schedule.card.\(card.id)", label: localized(card.titleKey, locale) + ", " + schedule.note,
                                actions: menuActions(card: card, schedule: schedule), tap: {
                                    if schedule.day == LocalDay(date: .now), canCheckIn(card) { checkInToday(card) }
                                    else { scheduleDetail = schedule }
                                }) {
                                CalendarTicketCard(card: card, scale: scale,
                                    badge: localized(schedule.day < LocalDay(date: .now) ? "schedule.expiredBadge" : "reminder.todo", locale),
                                    reminder: model.snapshot.targets.first { $0.cardID == card.id }?.reminderEnabled ?? false,
                                    progress: weeklyProgress(card))
                            }
                        }
                    }
                    ForEach(pendingCards.sorted { $0.id == "punchcard.63" && $1.id != "punchcard.63" }) { card in
                        CalendarInteractiveCard(identifier: "target.pending.\(card.id)", label: localized(card.titleKey, locale) + ", " + localized("reminder.todo", locale),
                            actions: menuActions(card: card), tap: {
                                if card.id == "punchcard.1" { pendingDay = selectedDay; pendingCard = card }
                                else { checkInToday(card) }
                            }) {
                            CalendarTicketCard(card: card, scale: scale,
                                badge: card.id == "punchcard.63" ? nil : localized("reminder.todo", locale),
                                reminder: model.snapshot.targets.first { $0.cardID == card.id }?.reminderEnabled ?? false,
                                progress: weeklyProgress(card))
                        }
                    }
                    if showsAddCard {
                        Button(action: openCatalog) {
                            CalendarAddCard(future: selectedDay > LocalDay(date: .now), scale: scale)
                        }.buttonStyle(.plain).accessibilityIdentifier("calendar.add")
                    }
                }.padding(.horizontal, spacing).padding(.vertical, 15)
            }
            .id(selectedDay)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(KeepUpStyle.background)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                selectedDate = calendar.date(byAdding: .day, value: value.translation.width < 0 ? 1 : -1, to: selectedDate)!
            })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.records")
    }

    private func setMonthMode(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isMonthMode = expanded }
    }

    private func weeklyProgress(_ card: HabitCard) -> Int? {
        guard selectedDay == LocalDay(date: .now),
              let target = model.snapshot.targets.first(where: { $0.cardID == card.id && $0.showsProgress }) else { return nil }
        return target.completedDays(entries: model.snapshot.entries, day: selectedDay).count
    }

    private func entryLabel(_ entry: CheckInEntry, card: HabitCard) -> String {
        var label = localized(card.titleKey, locale)
        if let quantity = entry.quantity {
            label += ", " + quantity.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + localized(entry.unit.titleKey, locale)
        }
        return label
    }

    private func canCheckIn(_ card: HabitCard) -> Bool {
        guard !model.snapshot.archivedCardIDs.contains(card.id),
              ![1].contains(OriginalCatalog.item(card)?.number ?? 0) else { return false }
        return card.id != "punchcard.63" || !model.entries(on: LocalDay(date: .now)).contains { $0.cardID == card.id }
    }

    private func checkInToday(_ card: HabitCard) {
        guard canCheckIn(card) else { return }
        // Original long-press check-in always records today, even on a past/future card.
        pendingDay = LocalDay(date: .now)
        pendingCard = card
    }

    private func menuActions(card: HabitCard, entry: CheckInEntry? = nil, schedule: ScheduledCard? = nil) -> [CalendarCardMenuAction] {
        let pinned = entry == nil && schedule == nil
        var actions = [CalendarCardMenuAction(kind: .delete,
            confirmation: localized(pinned ? "calendar.removePinnedConfirmation" : "calendar.deleteCardConfirmation", locale)) {
                Task {
                    if let entry { await model.delete(entry) }
                    else if let schedule { _ = await model.deleteSchedule(id: schedule.id) }
                    else if var target = model.snapshot.targets.first(where: { $0.cardID == card.id }) {
                        target.isPinned = false
                        target.reminderEnabled = false
                        target.showsProgress = false
                        _ = await model.saveTarget(target)
                    }
                }
            }]
        if canCheckIn(card), card.id != "punchcard.63" || (entry == nil && selectedDay == LocalDay(date: .now)) {
            actions.append(.init(kind: .checkIn) { checkInToday(card) })
        }
        if !model.snapshot.archivedCardIDs.contains(card.id), OriginalCatalog.item(card)?.number != 1 {
            actions.append(.init(kind: .reminder) { reminderCard = card })
        }
        return actions
    }

    private func movePage(_ offset: Int) {
        let component: Calendar.Component = isMonthMode ? .month : .weekOfYear
        let candidate = calendar.date(byAdding: component, value: offset, to: selectedDate)!
        selectedDate = candidate
    }
}
