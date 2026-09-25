import SwiftUI

struct WeightTargetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var ready = false
    @State private var initial = 60.0
    @State private var target = 55.0
    @State private var end = Calendar.current.date(byAdding: .month, value: 3, to: Date.now)!
    @State private var targetID = UUID().uuidString
    @State private var datePicker = false
    @State private var reset = false
    @State private var busy = false
    @State private var error: String?
    private var proposed: WeightTarget { WeightTarget(id: targetID, initial: initial, target: target, start: LocalDay(date: .now), end: LocalDay(date: end)) }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width/375
                ScrollView {
                    if ready {
                        if editing { editor(scale: s) }
                        else if let current = model.snapshot.weightTarget { summary(current, scale: s) }
                    }
                }.background(Color(white: 246/255))
            }.navigationTitle(editing ? "weight.setTarget" : "profile.weightTarget").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button { if editing && model.snapshot.weightTarget != nil { editing = false } else { dismiss() } } label: { Image(systemName: "chevron.left") }.disabled(busy).accessibilityIdentifier("weightTarget.close").tint(KeepUpStyle.navigationTint) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { if editing { Task { await save() } } else { reset = true } } label: {
                            Image(systemName: editing ? "checkmark" : "arrow.counterclockwise")
                        }.disabled(busy || (editing && initial == target))
                            .accessibilityLabel(Text(LocalizedStringKey(editing ? "action.save" : "weight.reset")))
                            .accessibilityIdentifier("weightTarget.save")
                            .tint(KeepUpStyle.navigationTint)
                    }
                }
                .onAppear { guard !ready else { return }; initialize(); editing = model.snapshot.weightTarget == nil; ready = true }
                .confirmationDialog("weight.resetQuestion", isPresented: $reset, titleVisibility: .visible) {
                    Button("weight.reset") { initialize(); editing = true }.accessibilityIdentifier("weightTarget.confirmReset")
                    Button("action.cancel", role: .cancel) {}
                }
                .sheet(isPresented: $datePicker) {
                    NavigationStack {
                        DatePicker("weight.endDate", selection: $end,
                                   in: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!...Calendar.current.date(byAdding: .year, value: 1, to: .now)!, displayedComponents: .date)
                            .datePickerStyle(.wheel).labelsHidden().environment(\.calendar, Calendar(identifier: .gregorian)).accessibilityIdentifier("weightTarget.datePicker")
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button { datePicker = false } label: { Image(systemName: "checkmark") }.accessibilityLabel(Text("action.done")).accessibilityIdentifier("weightTarget.dateDone").tint(KeepUpStyle.navigationTint) } }
                    }.presentationDetents([.height(300)])
                }
                .alert("error.title", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("action.ok") {} } message: { Text(LocalizedStringKey(error ?? "error.storage")) }
        }
    }
    private func initialize() {
        initial = min(200, max(20, model.latestWeight))
        target = model.snapshot.profile.map { min(200, max(20, ((18.5+24.99)/2*pow($0.height/100, 2)*10).rounded()/10)) } ?? max(20, initial-5)
        end = Calendar.current.date(byAdding: .month, value: 3, to: .now)!; targetID = UUID().uuidString
    }
    private func editor(scale: CGFloat) -> some View {
        VStack(spacing: 10) {
            rulerPanel(title: "weight.current", value: $initial, identifier: "weightTarget.initial", height: 165, scale: scale)
            rulerPanel(title: "weight.goal", value: $target, identifier: "weightTarget.target", height: 208, scale: scale)
            VStack(spacing: 1) {
                dateRow(title: "weight.startDate", day: LocalDay(date: .now), detail: localized("calendar.today", locale), arrow: false, scale: scale)
                Button { datePicker = true } label: { dateRow(title: "weight.endDate", day: LocalDay(date: end), detail: nil, arrow: true, scale: scale) }.buttonStyle(.plain).accessibilityIdentifier("weightTarget.endDate")
            }
            VStack(spacing: 7) {
                Text(summaryText)
                Text(proposed.weeklyChange < 1 ? "weight.pace.easy" : proposed.weeklyChange <= 2 ? "weight.pace.medium" : "weight.pace.fast")
            }.font(.system(size: 14)).foregroundStyle(Color(white: 0.51)).multilineTextAlignment(.center).padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 25)
        }.padding(.top, 10)
    }
    private var summaryText: AttributedString {
        let amount = abs(target-initial).formatted(.number.precision(.fractionLength(1)).locale(locale))
        let weekly = proposed.weeklyChange.formatted(.number.precision(.fractionLength(2)).locale(locale))
        let text = String(format: localized(target < initial ? "weight.lossSummary %@ %@" : "weight.gainSummary %@ %@", locale), amount, weekly)
        var result = AttributedString(text)
        for value in [amount + "kg", weekly + "kg"] {
            if let range = result.range(of: value) { result[range].foregroundColor = Color(hex: 0xF9414D) }
        }
        return result
    }
    private func rulerPanel(title: String, value: Binding<Double>, identifier: String, height: CGFloat, scale: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.white
            Text(LocalizedStringKey(title)).font(.system(size: 14)).foregroundStyle(Color(white: 0.3)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15).padding(.top, 15)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "kg").font(.system(size: 30*scale)).foregroundStyle(Color(white: 0.3)).padding(.top, 7).accessibilityIdentifier(identifier + ".value")
            WeightRuler(value: value, identifier: identifier).frame(height: 53).padding(.top, 95)
            Image("target_weight__arrow_2").resizable().frame(width: 14, height: 71).padding(.top, 57).allowsHitTesting(false)
            if height > 165, let profile = model.snapshot.profile {
                let factor = pow(profile.height/100, 2)
                Text(String(format: localized("weight.range %@ %@", locale), (18.5*factor).formatted(.number.precision(.fractionLength(1)).locale(locale)), (24.99*factor).formatted(.number.precision(.fractionLength(1)).locale(locale))))
                    .font(.system(size: 14)).foregroundStyle(Color(white: 0.51)).padding(.top, 173)
            }
        }.frame(height: height)
    }
    private func summary(_ value: WeightTarget, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Text("weight.goal").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 160, height: 28).background(Color(hex: 0xF8424C))
                    Text(value.target.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "kg").font(.system(size: 30)).frame(maxWidth: .infinity).frame(height: 78).accessibilityIdentifier("weightTarget.savedValue")
                }.background(.white).padding(.top, 95)
                Image("target_weight_monkey").padding(.top, 30)
            }.frame(height: 201)
            dateRow(title: "weight.startDate", day: value.start, detail: nil, arrow: false, scale: scale).padding(.top, 30)
            dateRow(title: "weight.endDate", day: value.end, detail: value.end <= LocalDay(date: .now) ? localized("weight.expired", locale) : String(format: localized("weight.daysLeft %lld", locale), Calendar.current.dateComponents([.day], from: LocalDay(date: .now).date(), to: value.end.date()).day ?? 0), arrow: false, scale: scale).padding(.top, 1)
        }
    }
    private func dateRow(title: String, day: LocalDay, detail: String?, arrow: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 20*scale) {
            Image("target_weight_time").resizable().frame(width: 20*scale, height: 20*scale)
            Text(LocalizedStringKey(title)).font(.system(size: 17)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text(day.rawValue).font(.system(size: 17))
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Color(white: 0.7)) }
            }
            if arrow { Image("target_weight_flag_arrow").resizable().frame(width: 7*scale, height: 14*scale) } else { Color.clear.frame(width: 7*scale) }
        }.foregroundStyle(Color(white: 0.51)).padding(.horizontal, 20*scale).frame(height: 60).background(.white)
    }
    private func save() async {
        busy = true; defer { busy = false }
        if await model.saveWeightTarget(proposed) { dismiss() }
        else { error = model.actionError; model.actionError = nil }
    }
}
