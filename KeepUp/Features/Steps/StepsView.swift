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
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(day: LocalDay) {
        self.day = day
        _controller = State(initialValue: StepsController(day: day))
    }

    private var selectedDay: LocalDay { controller.selectedDay }
    private var count: Int? { controller.readings[selectedDay]?.steps ?? model.snapshot.steps[selectedDay.rawValue]?.steps }
    private var distance: Double? {
        if let reading = controller.readings[selectedDay] { return reading.distance }
        return model.snapshot.steps[selectedDay.rawValue]?.distance
    }
    private var goal: Int? { model.snapshot.steps[selectedDay.rawValue]?.goal ?? StepsGoal.value(on: selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    summary
                    status.padding(.horizontal, 24).padding(.vertical, 18)
                    if let distance {
                        VStack(spacing: 6) {
                            Text((distance / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale)))
                                .font(.system(size: 28, weight: .light))
                            Text("unit.kilometers").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.bottom, 20).accessibilityLabel(Text("steps.distance"))
                    }
                    history
                    Image(model.snapshot.profile?.isMale == true ? "card_details_walk_male" : "card_details_walk_female")
                        .resizable().scaledToFit().opacity(0.2).accessibilityHidden(true)
                }
            }.background(.white)
                .navigationTitle("steps.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.accessibilityIdentifier("steps.close")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingTarget = true } label: { Image("setting_ic_walk_target").resizable().frame(width: 22, height: 22) }
                            .accessibilityLabel(Text("steps.targetSettings")).accessibilityIdentifier("steps.target")
                    }
                }
                .sheet(isPresented: $showingTarget, onDismiss: { refresh() }) { StepTargetView() }
                .task { refresh() }
                .onDisappear { controller.stop() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refresh() } else { controller.stop() }
                }
                .onReceive(clock) { _ in
                    if scenePhase == .active && controller.needsDateRefresh() { refresh() }
                }
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 2)
                if let count, let goal {
                    Circle().trim(from: 0, to: min(1, CGFloat(count) / CGFloat(goal)))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                VStack(spacing: 8) {
                    Text(selectedDay == LocalDay(date: .now) ? localized("steps.today", locale) : selectedDay.rawValue)
                        .font(.system(size: 12))
                    Text(count.map { $0.formatted(.number.locale(locale)) } ?? "—")
                        .font(.system(size: 32, weight: .light)).minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityIdentifier("steps.count")
                    if let goal { Text(String(format: localized("steps.goal %lld", locale), Int64(goal))).font(.system(size: 11)) }
                }.padding(10)
            }.frame(width: 150, height: 150)
            if let count, let goal, count >= goal {
                Text("steps.goalReached").font(.system(size: 12)).accessibilityIdentifier("steps.goalReached")
            }
        }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(LinearGradient(colors: [Color(hex: 0x66E8D6), Color(hex: 0x3EABD3)], startPoint: .top, endPoint: .bottom))
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
            if model.snapshot.steps[selectedDay.rawValue] != nil && controller.state != .ready {
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
                HStack {
                    Text(date.rawValue).foregroundStyle(.secondary)
                    Spacer()
                    if let reading { Text(reading.formatted(.number.locale(locale)) + " " + localized("unit.steps", locale)) }
                    else { Text("steps.noData").foregroundStyle(.secondary) }
                }.font(.system(size: 14)).padding(.vertical, 12)
                    .accessibilityIdentifier("steps.history.\(date.rawValue)")
                Divider()
            }
        }.padding(.horizontal, 24)
    }

    private func refresh(requestPermission: Bool = false) {
        controller.refresh(requestPermission: requestPermission) { await model.saveSteps($0) }
    }
}
