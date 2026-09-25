import SwiftUI

struct CalendarHomeView: View {
    @Binding var selectedDate: Date
    let today: LocalDay
    let openHistory: () -> Void
    let openProfile: () -> Void
    let openCatalog: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.monthMode) private var isMonthMode
    @State private var showingTheme = false
    @State private var showingRunning = false
    @State private var presentedRecoveredRun = false
    @State private var scheduleDetail: ScheduledCard?
    @State private var detail: CheckInEntry?
    @State private var pendingDay = LocalDay(date: .now)
    @State private var pendingCard: HabitCard?
    @State private var reminderCard: HabitCard?
    @State private var recordsAtTop = true
    @State private var recordsOverscroll: CGFloat = 0
    @State private var scopeProgress: CGFloat? = nil
    @State private var scopeDragOrigin: CGFloat? = nil
    @State private var scopeDragTranslation: CGFloat = 0
    @GestureState private var draggingScope = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = locale.identifier.hasPrefix("zh") ? 2 : 1
        return calendar
    }
    private var selectedDay: LocalDay { LocalDay(date: selectedDate) }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: selectedDate)!.start }
    private var monthOffset: Int { (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7 }
    private var monthDayCount: Int { ((monthOffset + calendar.range(of: .day, in: .month, for: selectedDate)!.count + 6) / 7) * 7 }
    private var selectedWeekRow: Int { (monthOffset + calendar.component(.day, from: selectedDate) - 1) / 7 }
    private var scopeTravel: CGFloat { CGFloat(monthDayCount / 7 - 1) * 32 }
    private var expansion: CGFloat { scopeProgress ?? (isMonthMode ? 1 : 0) }
    private var monthTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    private var dayEntries: [CheckInEntry] { model.entries(on: selectedDay) }
    private var daySchedules: [ScheduledCard] {
        model.snapshot.schedules.filter { $0.day == selectedDay && ($0.cardID != "punchcard.1" || measuredStepCard == nil) }
    }
    private var measuredStepCard: HabitCard? {
        guard selectedDay <= today,
              let measurement = model.snapshot.steps[selectedDay.rawValue], measurement.checkInDeleted != true,
              !dayEntries.contains(where: { $0.cardID == "punchcard.1" }),
              model.snapshot.targets.contains(where: { $0.cardID == "punchcard.1" && $0.isPinned }),
              !model.snapshot.archivedCardIDs.contains("punchcard.1") else { return nil }
        return model.snapshot.cards.first { $0.id == "punchcard.1" }
    }
    private var pendingCards: [HabitCard] {
        guard selectedDay == today else { return [] }
        let recorded = Set(dayEntries.map(\.cardID))
        let scheduled = Set(daySchedules.map(\.cardID))
        return model.snapshot.targets.filter { $0.isPinned }.compactMap { target in
            guard !recorded.contains(target.cardID), !scheduled.contains(target.cardID),
                  !(target.cardID == "punchcard.1" && measuredStepCard != nil),
                  !model.snapshot.archivedCardIDs.contains(target.cardID) else { return nil }
            return model.snapshot.cards.first { $0.id == target.cardID }
        }
    }
    private var showsAddCard: Bool {
        selectedDay > today || selectedDay < today
    }
    var body: some View {
        Group {
            GeometryReader { geometry in
                let cityImageHeight = geometry.size.width * 272 / 750
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            calendarHeader
                            calendarBody
                        }
                        .padding(.vertical, 8)
                        if model.running.session != nil {
                            Button { showingRunning = true } label: {
                                Label("running.resumeActivity", systemImage: model.running.session?.kind == .cycling ? "bicycle" : "figure.run")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .frame(width: recordGridLayout(width: geometry.size.width).contentWidth)
                                .padding(.top, 10).accessibilityIdentifier("running.resumeActivity")
                        }
                        recordGrid(width: geometry.size.width)
                    }.padding(.horizontal, 15)
                }
                .padding(.top, 12)
                .background {
                    ZStack(alignment: .bottom) {
                        LinearGradient(stops: [
                            .init(color: CalendarTheme.selected.color, location: 0),
                            .init(color: .white, location: 0.72)
                        ], startPoint: .top, endPoint: .bottom)
                        Image(CalendarTheme.selected.transparentCityImage)
                            .resizable().scaledToFit()
                            .frame(width: geometry.size.width, height: cityImageHeight)
                            .accessibilityHidden(true)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: openCatalog) {
                        Image(systemName: "plus")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(Color(white: 0.15))
                            .frame(width: 60, height: 60)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(Text("action.checkIn"))
                    .accessibilityIdentifier("tab.calendar")
                    .padding(.trailing, 24)
                    .padding(.bottom, cityImageHeight - geometry.safeAreaInsets.bottom + 10)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: openHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel(Text("nav.history"))
                    .accessibilityIdentifier("tab.history")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingTheme = true } label: { Image(systemName: "paintpalette") }
                        .accessibilityLabel(Text("theme.preview"))
                        .accessibilityIdentifier("theme.open")
                    Button(action: openProfile) { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel(Text("nav.profile"))
                        .accessibilityIdentifier("tab.profile")
                }
            }
            .tint(Color(white: 0.2))
            .fullScreenCover(isPresented: $showingTheme) { ThemeListView() }
            .fullScreenCover(isPresented: $showingRunning) { RunningView() }
            .onAppear {
                guard !presentedRecoveredRun, model.running.isRecovered,
                      model.running.session != nil else { return }
                presentedRecoveredRun = true
                showingRunning = true
            }
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
            Text(monthTitle)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityIdentifier("calendar.month")
            Spacer(minLength: 4)
            Button { movePage(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(isMonthMode ? "calendar.previousMonth" : "calendar.previousWeek"))
            .accessibilityIdentifier(isMonthMode ? "calendar.previousMonth" : "calendar.previousWeek")
            if selectedDay != today {
                Button { selectedDate = .now } label: {
                    Image(systemName: "scope")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("calendar.today"))
                .accessibilityIdentifier("calendar.today")
            }
            Button { movePage(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(isMonthMode ? "calendar.nextMonth" : "calendar.nextWeek"))
            .accessibilityIdentifier(isMonthMode ? "calendar.nextMonth" : "calendar.nextWeek")
        }
        .font(.system(size: 15, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 0.24))
        .padding(.leading, 20).padding(.trailing, 8)
    }

    private var calendarBody: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                DatePicker("calendar.chooseDate", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .environment(\.colorScheme, .light)
                    .frame(maxWidth: .infinity).padding(14)
            } else {
                let start = calendar.date(byAdding: .day, value: -monthOffset, to: monthStart)!
                let measuredStepDays = model.isStepCardEnabled
                    ? model.snapshot.steps.values.filter { $0.checkInDeleted != true }.map(\.day) : []
                let daysWithRecords = Set(model.snapshot.entries.map(\.day)).union(measuredStepDays)
                let plannedDays = Set(model.snapshot.schedules.filter { $0.day >= today }.map(\.day))
                let weekdays = calendar.veryShortStandaloneWeekdaySymbols
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdays[(index + calendar.firstWeekday - 1) % 7]).font(.system(size: 12)).foregroundStyle(Color.gray)
                            .frame(maxWidth: .infinity).frame(height: 22)
                    }
                }.padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 6)
                // Keep all month rows alive: collapse by clipping and translating the selected week.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach((0..<monthDayCount).map { calendar.date(byAdding: .day, value: $0, to: start)! }, id: \.self) { date in
                        let day = LocalDay(date: date)
                        let selected = day == selectedDay
                        let isToday = day == today
                        let recorded = daysWithRecords.contains(day)
                        let planned = plannedDays.contains(day) && !recorded && !isToday
                        let selectionColor = isToday ? KeepUpStyle.day : (recorded ? KeepUpStyle.card : (planned ? Color(hex: 0xBABDC2) : KeepUpStyle.day))
                        Button { selectedDate = date } label: {
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.custom("HelveticaNeue-Light", size: 12))
                                .foregroundStyle(recorded && !isToday ? Color.white : Color(white: 0.3))
                                .frame(width: 26, height: 26)
                                .background(isToday ? KeepUpStyle.day : (recorded ? KeepUpStyle.card : .clear), in: Circle())
                                .overlay(Circle().stroke(planned ? Color(hex: 0xBABDC2) : .clear, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                                .padding(3)
                                .overlay(Circle().stroke(selected ? selectionColor : .clear, lineWidth: 1))
                                .frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .opacity(calendar.isDate(date, equalTo: selectedDate, toGranularity: .month) ? 1 : 0.35)
                            
                            .accessibilityLabel(Text(date, format: .dateTime.year().month().day()))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("day.\(day.rawValue)")
                            .accessibilityHidden(expansion == 0 && !calendar.isDate(date, equalTo: selectedDate, toGranularity: .weekOfYear))
                    }
                }.padding(.horizontal, 8)
                    .offset(y: -CGFloat(selectedWeekRow) * 32 * (1 - expansion))
                    .frame(height: 32 + scopeTravel * expansion, alignment: .top)
                    .clipped()
                    .contentShape(Rectangle())

            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.grid")
        .accessibilityAction(named: Text(isMonthMode ? "calendar.showWeek" : "calendar.showMonth")) {
            setMonthMode(!isMonthMode)
        }
        .gesture(scopeGesture(fromCards: false))

    }

    private func recordGridLayout(width: CGFloat) -> (itemWidth: CGFloat, spacing: CGFloat, contentWidth: CGFloat) {
        let scale = width / 375
        let itemWidth = 88 * scale
        let spacing = (width - itemWidth * 3 - 34) / 4
        return (itemWidth, spacing, itemWidth * 3 + spacing * 2)
    }

    private func recordGrid(width: CGFloat) -> some View {
        let scale = width / 375
        let layout = recordGridLayout(width: width)
        let itemWidth = layout.itemWidth
        let spacing = layout.spacing
        return ZStack(alignment: .bottom) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3), spacing: 20) {
                    ForEach(dayEntries.sorted { lhs, rhs in
                        if (lhs.cardID == "punchcard.63") != (rhs.cardID == "punchcard.63") { return lhs.cardID == "punchcard.63" }
                        return lhs.createdAt < rhs.createdAt
                    }) { entry in
                        if let card = model.card(for: entry) {
                            CalendarInteractiveCard(identifier: "entry.\(entry.id)", label: entryLabel(entry, card: card),
                                actions: menuActions(card: card, entry: entry), tap: { detail = entry }) {
                                CalendarTicketCard(card: card, scale: scale, entry: entry, wake: model.snapshot.wakeUps[entry.id], progress: weeklyProgress(card), steps: model.snapshot.steps[entry.day.rawValue], stepGoal: StepsGoal.value(on: entry.day))
                            }
                        }
                    }
                    if let card = measuredStepCard, let measurement = model.snapshot.steps[selectedDay.rawValue] {
                        CalendarInteractiveCard(
                            identifier: selectedDay == today ? "target.pending.punchcard.1" : "steps.measurement.\(selectedDay.rawValue)",
                            label: localized(card.titleKey, locale) + ", " + measurement.steps.formatted(.number.locale(locale)),
                            actions: selectedDay == today ? menuActions(card: card) : [],
                            tap: { pendingDay = selectedDay; pendingCard = card }
                        ) {
                            CalendarTicketCard(card: card, scale: scale, steps: measurement, stepGoal: measurement.goal)
                        }
                    }
                    ForEach(daySchedules) { schedule in
                        if let card = model.snapshot.cards.first(where: { $0.id == schedule.cardID }) {
                            CalendarInteractiveCard(identifier: "schedule.card.\(card.id)", label: localized(card.titleKey, locale) + ", " + schedule.note,
                                actions: menuActions(card: card, schedule: schedule), tap: {
                                    if schedule.day == today, canCheckIn(card) { checkInToday(card) }
                                    else { scheduleDetail = schedule }
                                }) {
                                CalendarTicketCard(card: card, scale: scale,
                                    badge: localized(schedule.day < today ? "schedule.expiredBadge" : "reminder.todo", locale),
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
                                progress: weeklyProgress(card), steps: model.snapshot.steps[selectedDay.rawValue], stepGoal: StepsGoal.value(on: selectedDay))
                        }
                    }
                    if showsAddCard {
                        Button(action: openCatalog) {
                            CalendarAddCard(future: selectedDay > today, scale: scale)
                        }.buttonStyle(.plain).accessibilityIdentifier("calendar.add")
                    }
                }.padding(.horizontal, spacing).padding(.top, 15).padding(.bottom, 110)
                    // The calendar consumes downward overscroll; don't move the tickets twice.
                    .offset(y: recordsOverscroll)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                recordsAtTop = offset <= 1
                recordsOverscroll = min(0, offset)
            }
            .id(selectedDay)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(scopeGesture(fromCards: true))
            .onChange(of: draggingScope) { _, dragging in
                // A cancelled gesture must settle too, rather than leave a partial calendar.
                if !dragging, scopeDragOrigin != nil {
                    scopeDragOrigin = nil
                    setMonthMode(expansion > 0.5)
                }
            }
            .onChange(of: selectedDay) { _, _ in recordsAtTop = true }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.records")
    }

    private func scopeGesture(fromCards: Bool) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($draggingScope) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !dynamicTypeSize.isAccessibilitySize,
                      abs(value.translation.height) > abs(value.translation.width) * 1.5 else { return }
                if scopeDragOrigin == nil {
                    guard !fromCards || isMonthMode || (recordsAtTop && value.translation.height > 0) else { return }
                    scopeDragOrigin = expansion
                    // When a long list reaches the top, only consume the remaining drag.
                    scopeDragTranslation = fromCards && !isMonthMode ? value.translation.height : 0
                }
                guard let origin = scopeDragOrigin else { return }
                scopeProgress = min(1, max(0, origin + (value.translation.height - scopeDragTranslation) / scopeTravel))
            }
            .onEnded { value in
                if scopeDragOrigin != nil {
                    settleScope(projectedTranslation: value.predictedEndTranslation.height)
                } else if abs(value.translation.width) > max(30, abs(value.translation.height) * 1.5) {
                    if fromCards {
                        selectedDate = calendar.date(byAdding: .day, value: value.translation.width < 0 ? 1 : -1, to: selectedDate)!
                    } else { movePage(value.translation.width < 0 ? 1 : -1) }
                }
            }
    }

    private func settleScope(projectedTranslation: CGFloat) {
        guard let origin = scopeDragOrigin else { return }
        let projected = origin + (projectedTranslation - scopeDragTranslation) / scopeTravel
        scopeDragOrigin = nil
        setMonthMode(projected > 0.5)
    }

    private func setMonthMode(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) {
            isMonthMode = expanded
            scopeProgress = nil
        }
    }

    private func weeklyProgress(_ card: HabitCard) -> Int? {
        guard selectedDay == today,
              let target = model.snapshot.targets.first(where: { $0.cardID == card.id && $0.showsProgress }) else { return nil }
        return target.completedDays(entries: model.snapshot.entries, day: selectedDay).count
    }

    private func entryLabel(_ entry: CheckInEntry, card: HabitCard) -> String {
        var label = localized(card.titleKey, locale)
        if let quantity = entry.quantity {
            let digits = ["punchcard.2", "punchcard.96"].contains(card.id) ? 2...2 : 0...1
            label += ", " + quantity.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + localized(entry.unit.titleKey, locale)
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
        if canCheckIn(card), card.id != "punchcard.63" || (entry == nil && selectedDay == today) {
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
