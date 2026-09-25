import SwiftUI
import Combine

struct StepsView: View {
    let day: LocalDay
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: StepsController
    @State private var showingTarget = false
    @State private var showingHistory = false
    @State private var showingExplanation = false
    @State private var historyDay: HistoryDay?
    private struct HistoryDay: Identifiable {
        let day: LocalDay
        var id: LocalDay { day }
    }
    @State private var selectedStyle = StepsPosterStyle.details
    @State private var editing = false
    @State private var shareImage: StepsShareImage?
    @State private var shareFailed = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(day: LocalDay, followsToday: Bool? = nil) {
        self.day = day
        _controller = State(initialValue: StepsController(day: day, followsToday: followsToday))
    }

    private var selectedDay: LocalDay { controller.selectedDay }
    private var presentation: StepsPresentation {
        StepsPresentation(day: selectedDay, reading: controller.readings[selectedDay],
                          saved: model.snapshot.steps[selectedDay.rawValue], goal: StepsGoal.value(on: selectedDay))
    }
    private var count: Int? { presentation.steps }
    private var savedEntry: CheckInEntry? {
        model.entries(on: selectedDay).first { $0.cardID == "punchcard.1" }
    }
    private var encouragement: String {
        guard let card = OriginalCatalog.card(1),
              let entry = model.entries(on: selectedDay).first(where: { $0.cardID == card.id }) else {
            return localized("entry.encouragement.general", locale)
        }
        return EntryEncouragement.selected(entry: entry, card: card, entries: model.snapshot.entries,
                                          weight: nil, today: LocalDay(date: .now)).text(card: card, locale: locale)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                TabView(selection: $selectedStyle) {
                    ZStack {
                        VStack(spacing: 0) {
                            StepsOriginalDetails(data: presentation, isMale: model.snapshot.profile?.isMale == true, showsBackground: false)
                                .frame(maxHeight: 460 * geometry.size.width / 375).layoutPriority(1)
                            if !controller.loadingIntraday && controller.state == .ready && presentation.intraday?.isComplete != true {
                                Text("steps.intradayPartial").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("steps.intradayPartial")
                                Button("steps.retry") { refresh() }.padding(12).accessibilityIdentifier("steps.retryIntraday")
                            }
                            if controller.state != .ready && controller.state != .loading || controller.storageFailed {
                                status.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Color.clear.frame(height: geometry.size.width * 272 / 750 + 16)
                        }
                    }.tag(StepsPosterStyle.details)
                    StepsOriginalCard(data: presentation, encouragement: encouragement, showsBackground: false)
                        .tag(StepsPosterStyle.card)
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(alignment: .top) {
                        // Keep the shared backdrop outside the paging controller's safe-area clipping.
                        CardDetailThemeBackground()
                            .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.bottom)
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 5.5) {
                            ForEach(StepsPosterStyle.allCases, id: \.self) { style in
                                Button { withAnimation { selectedStyle = style } } label: {
                                    Circle().fill(selectedStyle == style ? Color(hex: 0x48484D) : Color(hex: 0xC1C1C1))
                                        .frame(width: 6, height: 6).padding(.vertical, 10)
                                }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(style.titleKey)))
                                    .accessibilityIdentifier("steps.page." + style.rawValue)
                                    .accessibilityAddTraits(selectedStyle == style ? .isSelected : [])
                            }
                        }.padding(.trailing, 15)
                    }
            }.background(.white)
                .navigationTitle(Text(verbatim: String(format: localized("entry.detailTitle %@", locale), localized("steps.title", locale))))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("action.close")).accessibilityIdentifier("steps.close")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if savedEntry != nil {
                            Button { editing = true } label: { Image(systemName: KeepUpStyle.editContentSymbol) }
                                .accessibilityLabel(Text("content.edit"))
                                .accessibilityIdentifier("steps.editContent")
                        }
                        Button {
                            guard let image = StepsPosterRenderer.render(data: presentation, style: selectedStyle, locale: locale,
                                                                        isMale: model.snapshot.profile?.isMale == true, encouragement: encouragement) else {
                                shareFailed = true; return
                            }
                            shareImage = StepsShareImage(image: image)
                        } label: { Image("card_detail_ic_share").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24) }
                            .accessibilityLabel(Text("entry.share")).accessibilityIdentifier("steps.share").disabled(count == nil)
                    }
                }
                .sheet(isPresented: $showingHistory, onDismiss: { refresh() }) {
                    NavigationStack {
                        ScrollView { history.padding(.top, 20) }.navigationTitle("steps.recent")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { showingHistory = false } } }
                    }
                    .fullScreenCover(item: $historyDay) { selection in StepsView(day: selection.day, followsToday: false) }
                }
                .alert("steps.measurementInfo", isPresented: $showingExplanation) {
                    Button("action.ok", role: .cancel) {}
                } message: { Text(localized("steps.energyExplanation", locale) + "\n\n" + localized("steps.activeExplanation", locale)) }
                .sheet(item: $shareImage) { EntrySharePreview(image: $0.image) }
                .fullScreenCover(isPresented: $editing) {
                    if let savedEntry, let card = model.card(for: savedEntry) {
                        EntryContentEditor(entry: savedEntry, card: card)
                    }
                }
                .alert("error.title", isPresented: $shareFailed) {
                    Button("action.ok", role: .cancel) {}
                } message: { Text("entry.shareError") }
                .sheet(isPresented: $showingTarget, onDismiss: { refresh() }) { StepTargetView() }
                .task { refresh() }
                .onDisappear { controller.stop() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refresh() } else { controller.stop() }
                }
                .onReceive(clock) { _ in
                    if scenePhase == .active && (controller.needsDateRefresh() ||
                        (!controller.loadingIntraday && selectedDay == LocalDay(date: .now) && Date.now.timeIntervalSince(controller.readings[selectedDay]?.intraday?.measuredThrough ?? .now) >= 300)) { refresh() }
                }
        }
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 12) {
            switch controller.state {
            case .loading: ProgressView("steps.loading").accessibilityIdentifier("steps.loading")
            case .permission:
                Text("steps.permission")
                Button("steps.authorize") { refresh(requestPermission: true) }.accessibilityIdentifier("steps.authorize")
            case .denied:
                Text("steps.denied").accessibilityIdentifier("steps.denied")
                Button("steps.settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.accessibilityIdentifier("steps.settings")
            case .unsupported: Text("steps.unsupported").accessibilityIdentifier("steps.unsupported")
            case .unavailable: Text("steps.unavailable")
            case .failed:
                Text("steps.failed")
                Button("steps.retry") { refresh() }.accessibilityIdentifier("steps.retry")
            case .ready: EmptyView()
            }
            if presentation.isSaved && controller.state != .ready {
                Text("steps.saved").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if controller.storageFailed {
                Text("error.storage")
                Button("steps.retry") { refresh() }.accessibilityIdentifier("steps.retrySave")
            }
        }.font(.system(size: 14)).multilineTextAlignment(.center)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("steps.recent").font(.system(size: 15, weight: .medium)).padding(.bottom, 12)
            ForEach(StepsDateRange.recentDays(now: .now, timeZone: .current), id: \.self) { date in
                let reading = controller.readings[date]?.steps ?? model.snapshot.steps[date.rawValue]?.steps
                Button { historyDay = HistoryDay(day: date) } label: {
                    HStack {
                        Text(date.rawValue).foregroundStyle(.secondary)
                        Spacer()
                        if let reading { Text(reading.formatted(.number.locale(locale)) + " " + localized("unit.steps", locale)) }
                        else { Text("steps.noData").foregroundStyle(.secondary) }
                    }.font(.system(size: 14)).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("steps.history.\(date.rawValue)")
                Divider()
            }
        }.padding(.horizontal, 24)
    }

    private func refresh(requestPermission: Bool = false) {
        controller.refresh(requestPermission: requestPermission, includeIntraday: true) { await model.saveSteps($0) }
    }
}

private struct StepsShareImage: Identifiable { let id = UUID(); let image: UIImage }
