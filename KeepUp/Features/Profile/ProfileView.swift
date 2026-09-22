import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var showMembership = false
    @State private var showPersonalInfo = false
    @Default(.stepGoalChanges) private var stepGoalChanges
    @State private var showStepsTarget = false
    @State private var showWeightTarget = false
    @State private var showReminders = false
    @State private var showRunningStatistics = false
    @State private var pendingFeature: String?
    private var entries: [CheckInEntry] { model.snapshot.entries }

    var body: some View {
        Group {
            GeometryReader { geometry in
                let scale = geometry.size.width / 375
                ScrollView {
                    VStack(spacing: 10 * scale) {
                        header(scale: scale)
                        VStack(spacing: 0) {
                            row("profile.premium", subtitle: "profile.premiumSubtitle", image: "setting_ic_suggestion", scale: scale)
                            row("profile.ad", subtitle: "profile.adSubtitle", image: "setting_ic_week_pre", scale: scale)
                        }
                        VStack(spacing: 0) {
                            row("profile.weightTarget", subtitle: model.snapshot.weightTarget.map { String(format: "%.1fkg", $0.target) } ?? "profile.noTarget", image: "setting_ic_weight_target", scale: scale)
                            row("profile.stepTarget", subtitle: StepsGoal.value(on: LocalDay(date: .now), changes: stepGoalChanges).map { String(format: localized("steps.goal %lld", locale), Int64($0)) } ?? "profile.noSteps", image: "setting_ic_walk_target", scale: scale)
                            row("profile.alarms", subtitle: nil, image: "setting_ic_manageclock", scale: scale)
                            row("runningStats.title", subtitle: nil, image: "figure.run", scale: scale, systemImage: true)
                        }
                        VStack(spacing: 0) {
                            row("profile.review", subtitle: "profile.reviewSubtitle", image: "setting_ic_review", scale: scale)
                            row("profile.contact", subtitle: "profile.contactSubtitle", image: "setting_ic_contact", scale: scale)
                            HStack(spacing: 15 * scale) {
                                Image("setting_ic_info").resizable().frame(width: 18 * scale, height: 18 * scale)
                                Text("profile.version").font(.system(size: 14 * scale))
                                Spacer()
                                Text("V" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"))
                                    .font(.system(size: 13 * scale)).foregroundStyle(Color(white: 0.6)).padding(.trailing, 20 * scale)
                            }.padding(.horizontal, 15 * scale).frame(height: 50 * scale).background(.white)
                        }
                    }
                }.background(Color(white: 246/255), ignoresSafeAreaEdges: [])
                    .overlay(alignment: .topTrailing) {
                        NavigationLink { ProfileSettingsView() } label: {
                            Image("gps_exercise_confirm_ic_set").resizable().frame(width: 24 * scale, height: 24 * scale)
                        }.padding(.trailing, 15 * scale).padding(.top, 10).accessibilityLabel(Text("settings.title"))
                            .accessibilityIdentifier("profile.settings")
                    }
            }.background(alignment: .top) { KeepUpStyle.theme.ignoresSafeArea(edges: .top) }
                .navigationTitle("nav.profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(KeepUpStyle.theme, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .fullScreenCover(isPresented: $showStepsTarget) { StepTargetView() }
                .fullScreenCover(isPresented: $showWeightTarget) { WeightTargetView() }
                .fullScreenCover(isPresented: $showReminders) { ReminderListView() }
                .fullScreenCover(isPresented: $showRunningStatistics) { RunningStatisticsView() }
                .fullScreenCover(isPresented: $showPersonalInfo) { ProfileInfoView() }
                .fullScreenCover(isPresented: $showMembership) { MembershipView(onClose: { showMembership = false }) }
                .alert(Text(LocalizedStringKey(pendingFeature ?? "error.title")), isPresented: Binding(get: { pendingFeature != nil }, set: { if !$0 { pendingFeature = nil } })) {
                    Button("action.ok") { pendingFeature = nil }
                } message: { Text("feature.pending") }
        }
    }
    @ViewBuilder private var profileAvatar: some View {
        if let data = model.snapshot.profile?.avatar, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().clipped() }
        else { Image("user_default_head").resizable() }
    }
    private func header(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Image("me_bg_title").resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.frame(height: 100 * scale).background(KeepUpStyle.theme)
            ZStack(alignment: .topLeading) {
                Color.white
                Button { showPersonalInfo = true } label: {
                    profileAvatar.frame(width: 70 * scale, height: 70 * scale)
                        .clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .overlay(alignment: .bottomTrailing) { Image(model.snapshot.profile?.isMale == true ? "personal_ic_boy" : "personal_ic_girl").resizable().frame(width: 20 * scale, height: 20 * scale) }
                }.offset(x: 20 * scale, y: -35 * scale)
                Text(verbatim: String(format: localized("profile.streakFormat %lld", locale), Int64(RecordStatistics.streak(entries: entries, today: LocalDay(date: .now)))))
                    .font(.system(size: 13 * scale, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 3 * scale)
                    .frame(height: 18 * scale).background(KeepUpStyle.accent, in: RoundedRectangle(cornerRadius: 2 * scale))
                    .offset(x: 100 * scale, y: 17 * scale)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let profile = model.snapshot.profile
                    let nickname = profile?.nickname ?? ""
                    let name = nickname.isEmpty ? localized("profile.nickname", locale) : nickname
                    let days = ProfileDuration.dayCount(since: profile?.createdAt ?? context.date, now: context.date)
                    Text(String(format: localized("profile.journey %@ %lld", locale), name, Int64(days)))
                        .font(.system(size: 16 * scale)).lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("profile.journey")
                }.padding(.horizontal, 20 * scale).frame(maxWidth: .infinity, alignment: .leading).offset(y: 50 * scale)
            }.frame(height: 90 * scale)
        }.frame(height: 190 * scale)
            .overlay(alignment: .bottom) { Color.black.opacity(0.15).frame(height: 1/3) }
    }
    private func row(_ title: String, subtitle: String?, image: String, scale: CGFloat, systemImage: Bool = false) -> some View {
        Button { if title == "profile.premium" { showMembership = true } else if title == "profile.stepTarget" { showStepsTarget = true } else if title == "profile.weightTarget" { showWeightTarget = true } else if title == "profile.alarms" { showReminders = true } else if title == "runningStats.title" { showRunningStatistics = true } else { pendingFeature = title } } label: {
            HStack(spacing: 15 * scale) {
                Group {
                    if systemImage { Image(systemName: image).resizable().scaledToFit().foregroundStyle(KeepUpStyle.accent) }
                    else { Image(image).resizable() }
                }.frame(width: 18 * scale, height: 18 * scale)
                Text(LocalizedStringKey(title)).font(.system(size: 14 * scale))
                Spacer(minLength: 0)
                HStack(spacing: 6 * scale) {
                    if let subtitle { Text(LocalizedStringKey(subtitle)).font(.system(size: 13 * scale)).foregroundStyle(Color(white: 0.6)).lineLimit(1).minimumScaleFactor(0.7) }
                    Image("me_arrow_ic").resizable().frame(width: 14 * scale, height: 14 * scale)
                }
            }.padding(.horizontal, 15 * scale).frame(height: 50 * scale).background(.white)
                .overlay(alignment: .bottom) { Color.black.opacity(0.15).frame(height: 1/3).padding(.leading, 15 * scale) }
        }.buttonStyle(.plain).accessibilityIdentifier(title)
    }
}

struct ProfileSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editProfile = false
    @Default(.appLanguage) private var language
    var body: some View {
        List {
            Section {
                Button { editProfile = true } label: {
                    HStack { Text("info.title"); Spacer(); Text(model.snapshot.profile?.nickname ?? "").foregroundStyle(.secondary); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("profile.edit")
            }
            NavigationLink { LanguageSettingsView() } label: {
                HStack {
                    Text("settings.language")
                    Spacer()
                    Text(LocalizedStringKey((AppLanguage(rawValue: language) ?? .system).titleKey)).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("settings.language")
        }.fullScreenCover(isPresented: $editProfile) {
            ProfileInfoView()
        }.navigationTitle("profile.settings").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
struct LanguageSettingsView: View {
    @Default(.appLanguage) private var language
    var body: some View {
        List {
            ForEach(AppLanguage.allCases, id: \.rawValue) { item in
                Button { language = item.rawValue } label: {
                    HStack {
                        Text(LocalizedStringKey(item.titleKey)).foregroundStyle(.primary)
                        Spacer()
                        if language == item.rawValue { Image(systemName: "checkmark").foregroundStyle(KeepUpStyle.accent) }
                    }
                }.accessibilityIdentifier("language.\(item.rawValue)")
            }
        }.navigationTitle("settings.language").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
