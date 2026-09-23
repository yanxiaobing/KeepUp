import SwiftUI

struct CardCatalogView: View {
    let day: LocalDay
    var initialCardID: String? = nil
    var onStepsAdded: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var search = ""
    @State private var category = Category.recommended
    @State private var scheduledCard: HabitCard?
    @State private var showingSteps = false
    @State private var addingSteps = false
    @State private var stepsAdded = false
    @State private var runningRequest: RunningRequest?
    private struct RunningRequest: Identifiable {
        let kind: RunningKind
        var id: RunningKind { kind }
    }
    @State private var wakeIntro = false
    @State private var wakeReminder = false
    @State private var selectedCard: HabitCard?
    @State private var pendingFeature: String?
    @State private var creatingCustom = false
    @State private var archiving: HabitCard?
    @State private var archiveError = false
    private enum Category: String, CaseIterable {
        case recommended, fitness, sports, life, health, recent
        var key: String { "catalog." + rawValue }
        var numbers: [Int] {
            switch self {
            case .recommended, .recent: []
            case .fitness: [2,3,7,8,14,15,16,17,48,49,51,53,54,55,58,59,60,61,62]
            case .sports: [4,10,11,13,52,56,57]
            case .life: [1,63,5,6,9,12,18,19]
            case .health: [50,64,65,66,67,68,70,71,72,73]
            }
        }
    }
    private var future: Bool { day > LocalDay(date: .now) }
    private var cards: [HabitCard] {
        if future && category == .recommended && search.isEmpty { return [50,2,12,5,8,19,18,17,16,3].compactMap(OriginalCatalog.card) }
        let recentIDs = Array(NSOrderedSet(array: model.snapshot.entries.map(\.cardID))) as? [String] ?? []
        if !search.isEmpty {
            return model.snapshot.cards.filter { !model.snapshot.archivedCardIDs.contains($0.id) }.filter { card in
                [locale, Locale(identifier: "en"), Locale(identifier: "zh-Hans")].contains {
                    localized(card.titleKey, $0).localizedStandardContains(search)
                }
            }
        }
        if category == .recent {
            let ids = Array(recentIDs.prefix(20)) + model.snapshot.cards.filter(\.isCustom).map(\.id)
            var seen: Set<String> = []
            return ids.filter { seen.insert($0).inserted && !model.snapshot.archivedCardIDs.contains($0) }.compactMap { id in model.snapshot.cards.first { $0.id == id } }
        }
        return category.numbers.compactMap { OriginalCatalog.card($0) }
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 375
            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    Button { dismiss() } label: {
                        Image("base_icon_close").resizable().frame(width: 24, height: 24)
                    }.buttonStyle(.plain).accessibilityLabel(Text("action.cancel")).accessibilityIdentifier("catalog.close")
                    HStack(spacing: 6) {
                        Image("choose_card_ic_search").resizable().frame(width: 14, height: 14)
                        TextField("catalog.search", text: $search).font(.system(size: 13)).accessibilityIdentifier("catalog.search")
                    }.padding(.horizontal, 10).frame(height: 32).background(Color(red: 242/255, green: 242/255, blue: 244/255), in: RoundedRectangle(cornerRadius: 4))
                    Button { creatingCustom = true } label: { Text("catalog.create").font(.system(size: 15, weight: .bold)).fixedSize() }
                        .buttonStyle(.plain).accessibilityIdentifier("catalog.create")
                }.padding(.horizontal, 15).padding(.top, 3).frame(height: 46)
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 36) {
                        ForEach(Category.allCases, id: \.self) { item in
                            Button { category = item } label: {
                                Text(LocalizedStringKey(item.key)).font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(category == item ? Color(white: 34/255) : Color(red: 152/255, green: 152/255, blue: 158/255))
                                    .frame(height: 46 * scale)
                                    .overlay(alignment: .bottom) {
                                        if category == item { Rectangle().fill(Color(white: 34/255)).frame(height: 2).padding(.horizontal, -15) }
                                    }
                            }.buttonStyle(.plain).accessibilityIdentifier("catalog." + item.rawValue).id(item)
                        }
                    }.padding(.horizontal, 15)
                }.fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .bottom) { Color(white: 0.92).frame(height: 0.5) }
                .onChange(of: category) { _, value in withAnimation { proxy.scrollTo(value, anchor: .trailing) } }
                }
                if category == .recommended && search.isEmpty && !future { recommendations(scale: scale) }
                else { cardList }
            }.background(.white)
                .overlay {
                    if let card = selectedCard {
                        ComposeEntryView(card: card, day: day, onSaved: { dismiss() }, onCancel: { selectedCard = nil })
                            .transition(.opacity).zIndex(1)
                    }
                }
                .fullScreenCover(isPresented: $addingSteps, onDismiss: { if stepsAdded { onStepsAdded(); dismiss() } }) {
                    StepTargetView(onSaved: { stepsAdded = true })
                }
                .fullScreenCover(isPresented: $showingSteps) { StepsView(day: min(day, LocalDay(date: .now))) }
                .fullScreenCover(item: $runningRequest) { request in RunningView(kind: request.kind) }
                .fullScreenCover(item: $scheduledCard) { card in
                    ScheduledCardView(card: card, day: day, existing: model.snapshot.schedules.first { $0.cardID == card.id && $0.day == day }, onSaved: { dismiss() })
                }
                .overlay { if wakeIntro { WakeUpIntroView(onClose: { wakeIntro = false }, onConfirm: { alarm in Task { await activateWakeUp(alarm: alarm) } }) } }
                .fullScreenCover(isPresented: $wakeReminder, onDismiss: { dismiss() }) { if let card = OriginalCatalog.card(63) { ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) } }
                .fullScreenCover(isPresented: $creatingCustom) {
                    CustomCardView { _ in category = .recent; search = "" }
                }
                .confirmationDialog("custom.removeQuestion", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
                    Button("action.delete", role: .destructive) {
                        if let card = archiving { Task { archiveError = !(await model.archiveCustomCard(id: card.id)); model.actionError = nil; archiving = nil } }
                    }.accessibilityIdentifier("custom.removeConfirm")
                    Button("action.cancel", role: .cancel) { archiving = nil }
                } message: { Text("custom.removeHelp") }
                .alert("error.title", isPresented: $archiveError) { Button("action.ok") {} } message: { Text("error.storage") }
                .alert(Text(LocalizedStringKey(pendingFeature ?? "error.title")), isPresented: Binding(get: { pendingFeature != nil }, set: { if !$0 { pendingFeature = nil } })) {
                    Button("action.ok") { pendingFeature = nil }
                } message: { Text(LocalizedStringKey(["wake.todayOnly", "wake.duplicate", "schedule.duplicate", "running.todayOnly"].contains(pendingFeature ?? "") ? pendingFeature! : "feature.pending")) }
        }.background(Color.white.ignoresSafeArea())
            .task { if let id = initialCardID, let card = model.snapshot.cards.first(where: { $0.id == id }) { choose(card) } }
            .foregroundStyle(Color(red: 72/255, green: 72/255, blue: 77/255))
    }
    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cards) { card in
                    HStack(spacing: 0) {
                        Button { choose(card) } label: {
                            HStack(spacing: category == .recent ? 14 : 20) {
                                CardSymbol(card: card, size: 44)
                                Text(verbatim: localized(card.titleKey, locale) + (card.isCustom ? localized("custom.suffix", locale) : "")).font(.system(size: 14))
                                Spacer()
                                if !card.isCustom { Image("life_ic_go").resizable().frame(width: 24, height: 24) }
                            }.padding(.leading, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("card.\(card.id)")
                        if card.isCustom {
                            Button { archiving = card } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityIdentifier("custom.more.\(card.id)")
                        }
                    }.padding(.trailing, 15).frame(height: category == .recent ? 64 : 80)
                        .overlay(alignment: .bottom) { Color.black.opacity(0.1).frame(height: 0.5).padding(.leading, 15) }
                }
                if cards.isEmpty { Text("catalog.empty").font(.system(size: 14)).foregroundStyle(.secondary).padding(40) }
            }
        }.scrollDismissesKeyboard(.interactively)
    }
    private func recommendations(scale: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    featured(50, background: "weight", icon: "weight", subtitle: "Weight")
                    featured(2, background: "run", icon: "running", subtitle: "Run")
                    featured(96, background: "cycle", icon: "cycle", subtitle: "Cycle")
                }.padding(.horizontal, 15).padding(.vertical, 20)
                HStack(spacing: 10) {
                    Rectangle().fill(.black.opacity(0.1)).frame(height: 0.5)
                    Text("catalog.more").font(.system(size: 12, weight: .bold)).fixedSize()
                    Rectangle().fill(.black.opacity(0.1)).frame(height: 0.5)
                }.padding(.horizontal, 15).frame(height: 16)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    shortcut(image: "sport_ic_recent", title: "catalog.recentCheckIns", color: Color(red: 196/255, green: 198/255, blue: 203/255)) { category = .recent }
                    shortcut(image: "sport_ic_white_wake_up", title: "catalog.addWakeUp", color: Color(red: 61/255, green: 185/255, blue: 169/255)) { if let card = OriginalCatalog.card(63) { choose(card) } }
                    ForEach([1,12,5,8,19,18,17,16,3], id: \.self) { number in
                        if let card = OriginalCatalog.card(number) {
                            shortcut(image: card.whiteImage, title: LocalizedStringKey(card.titleKey), color: Color(red: 71/255, green: 206/255, blue: 253/255)) { choose(card) }
                                .accessibilityIdentifier("card.\(card.id)")
                        }
                    }
                }.padding(.horizontal, 15).padding(.vertical, 20 * scale)
            }
        }
    }
    private func featured(_ number: Int, background: String, icon: String, subtitle: String) -> some View {
        Button { if let card = OriginalCatalog.card(number) { choose(card) } } label: {
            VStack(spacing: 0) {
                Image("choose_card_ic_" + icon).resizable().frame(width: 60, height: 60).padding(.top, 7)
                Text(LocalizedStringKey(OriginalCatalog.card(number)?.titleKey ?? "")).font(.system(size: 17)).padding(.top, 10)
                Text(subtitle).font(.system(size: 11)).padding(.top, 4)
                Spacer(minLength: 0)
            }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 120)
                .background { Image("choose_card_btn_" + background + "_bg").resizable() }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topTrailing) {
                    if number != 50 {
                        Image("choose_card_ic_setting").resizable().frame(width: 20, height: 20).padding(3)
                    }
                }
        }.buttonStyle(.plain).accessibilityIdentifier("catalog.featured.\(number)")
    }
    private func shortcut(image: String, title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(image).resizable().frame(width: 32, height: 32)
                Text(title).font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }.padding(.horizontal, 4).frame(height: 40).foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
    }
    private func activateWakeUp(alarm: Bool) async {
        var target = model.snapshot.targets.first { $0.cardID == "punchcard.63" } ?? CardTarget(cardID: "punchcard.63")
        target.isPinned = true; target.hour = 8; target.minute = 0
        if await model.saveTarget(target) { wakeIntro = false; if alarm { wakeReminder = true } else { dismiss() } }
        else { archiveError = true }
    }
    private func choose(_ card: HabitCard) {
        if card.id == "punchcard.1" {
            if StepsGoal.value(on: LocalDay(date: .now)) == nil ||
                !model.isStepCardEnabled {
                addingSteps = true
            } else { showingSteps = true }
            return
        }
        if future {
            if model.snapshot.schedules.contains(where: { $0.cardID == card.id && $0.day == day }) { pendingFeature = "schedule.duplicate" }
            else { scheduledCard = card }
            return
        }
        if card.id == "punchcard.63" {
            guard day == LocalDay(date: .now) else { pendingFeature = "wake.todayOnly"; return }
            if model.entries(on: day).contains(where: { $0.cardID == card.id }) { pendingFeature = "wake.duplicate"; return }
            if !model.snapshot.targets.contains(where: { $0.cardID == card.id && $0.isPinned }) { wakeIntro = true; return }
        }
        if ["punchcard.2", "punchcard.96"].contains(card.id) {
            guard day == LocalDay(date: .now) else { pendingFeature = "running.todayOnly"; return }
            runningRequest = RunningRequest(kind: card.id == "punchcard.96" ? .cycling : .outdoor)
            return
        }
        selectedCard = card
    }
}
