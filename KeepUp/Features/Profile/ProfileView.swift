import SwiftUI

struct ProfileView: View {
    var isCurrentDestination: () -> Bool = { true }
    @Environment(AppAdvertising.self) private var advertising
    @Environment(MembershipStore.self) private var membership
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var showMembership = false
    @State private var showPersonalInfo = false
    @Default(.stepGoalChanges) private var stepGoalChanges
    @State private var showStepsTarget = false
    @State private var showWeightTarget = false
    @State private var showReminders = false
    @State private var showRunningStatistics = false
    @State private var pendingFeature: String?
    @State private var rewardGate: RewardGateRequest?
    @State private var rewardDecision: (RewardedFeatureAccess.FeatureID, RewardedFeatureAccessView.Decision)?
    @State private var preparingFeature = false
    @State private var privacyError = false
    @State private var contextID = UUID()
    @State private var featureTask: Task<Void, Never>?
    @State private var privacyTask: Task<Void, Never>?
    private var entries: [CheckInEntry] { model.snapshot.entries }

    var body: some View {
        Group {
            GeometryReader { geometry in
                let scale = geometry.size.width / 375
                ScrollView {
                    VStack(spacing: 10 * scale) {
                        header(scale: scale)
                        VStack(spacing: 0) {
                            row("profile.premium", subtitle: membership.isPremium ? "membership.active" : "profile.premiumSubtitle", image: "setting_ic_suggestion", scale: scale)
                            row("profile.ad", subtitle: "profile.adSubtitle", image: "setting_ic_week_pre", scale: scale, showsSeparator: advertising.consent.privacyOptionsRequired)
                            if advertising.consent.privacyOptionsRequired {
                                Button("ads.privacyOptions", action: presentPrivacyOptions)
                                    .font(.system(size: 14 * scale)).frame(maxWidth: .infinity, minHeight: 50 * scale)
                                    .disabled(advertising.consent.isBusy || preparingFeature)
                                    .accessibilityIdentifier("ads.privacyOptions")
                            }
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 12 * scale))
                        .padding(.horizontal, 15 * scale)
                        VStack(spacing: 0) {
                            row("profile.weightTarget", subtitle: model.snapshot.weightTarget.map { String(format: "%.1fkg", $0.target) } ?? "profile.noTarget", image: "setting_ic_weight_target", scale: scale)
                            row("profile.stepTarget", subtitle: StepsGoal.value(on: LocalDay(date: .now), changes: stepGoalChanges).map { String(format: localized("steps.goal %lld", locale), Int64($0)) } ?? "profile.noSteps", image: "setting_ic_walk_target", scale: scale)
                            row("profile.alarms", subtitle: nil, image: "setting_ic_manageclock", scale: scale)
                            row("runningStats.title", subtitle: nil, image: "figure.run", scale: scale, systemImage: true, showsSeparator: false)
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 12 * scale))
                        .padding(.horizontal, 15 * scale)
                        VStack(spacing: 0) {
                            row("profile.review", subtitle: "profile.reviewSubtitle", image: "setting_ic_review", scale: scale)
                            row("profile.contact", subtitle: "profile.contactSubtitle", image: "setting_ic_contact", scale: scale)
                            HStack(spacing: 15 * scale) {
                                Image("setting_ic_info").resizable().frame(width: 18 * scale, height: 18 * scale)
                                Text("profile.version").font(.system(size: 14 * scale))
                                Spacer()
                                Text("V" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"))
                                    .font(.system(size: 13 * scale)).foregroundStyle(Color(white: 0.6)).padding(.trailing, 20 * scale)
                            }.padding(.horizontal, 15 * scale).frame(height: 50 * scale)
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 12 * scale))
                        .padding(.horizontal, 15 * scale)
                    }
                    .padding(.bottom, 16 * scale)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectHidden(true, for: .all)
            }
                .background {
                    LinearGradient(colors: [KeepUpStyle.theme, .white], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
                .navigationTitle("nav.profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { ProfileSettingsView() } label: {
                            Image(systemName: "gearshape")
                        }
                        .tint(Color(white: 0.2))
                        .disabled(preparingFeature)
                        .accessibilityLabel(Text("settings.title"))
                        .accessibilityIdentifier("profile.settings")
                    }
                }
                .fullScreenCover(item: $rewardGate, onDismiss: finishRewardGate) { request in
                    RewardedFeatureAccessView(feature: request.feature) { decision in
                        rewardDecision = (request.feature, decision)
                        rewardGate = nil
                    }
                }
                .alert("error.title", isPresented: $privacyError) {
                    Button("action.ok") {}
                } message: { Text("ads.privacyError") }
                .fullScreenCover(isPresented: $showStepsTarget) { StepTargetView() }
                .fullScreenCover(isPresented: $showWeightTarget) { WeightTargetView() }
                .fullScreenCover(isPresented: $showReminders) { ReminderListView() }
                .fullScreenCover(isPresented: $showRunningStatistics) { RunningStatisticsView() }
                .navigationDestination(isPresented: $showPersonalInfo) { ProfileInfoView() }
                .fullScreenCover(isPresented: $showMembership) { MembershipView(onClose: { showMembership = false }) }
                .alert(Text(LocalizedStringKey(pendingFeature ?? "error.title")), isPresented: Binding(get: { pendingFeature != nil }, set: { if !$0 { pendingFeature = nil } })) {
                    Button("action.ok") { pendingFeature = nil }
                } message: { Text("feature.pending") }
        }
        .onDisappear { if !isCurrentDestination() { invalidateFeatureContext() } }
        .onChange(of: isCurrentDestination()) { _, active in
            if !active { invalidateFeatureContext() }
        }
    }

    private func invalidateFeatureContext() {
        contextID = UUID()
        featureTask?.cancel()
        featureTask = nil
        privacyTask?.cancel()
        privacyTask = nil
        rewardDecision = nil
        rewardGate = nil
        preparingFeature = false
        advertising.features.cancel()
        advertising.presentation.cancelAll()
    }

    private func requestFeature(_ feature: RewardedFeatureAccess.FeatureID) {
        guard isCurrentDestination(), !preparingFeature, rewardGate == nil else { return }
        preparingFeature = true
        let token = contextID
        featureTask = Task { @MainActor in
            await advertising.prepareConsentIfNeeded()
            guard contextID == token, isCurrentDestination() else { return }
            guard !Task.isCancelled, scenePhase == .active else { preparingFeature = false; return }
            if advertising.requiresReward(for: feature) {
                rewardGate = RewardGateRequest(feature: feature)
            } else {
                openFeature(feature)
            }
            preparingFeature = false
            featureTask = nil
        }
    }

    private func openFeature(_ feature: RewardedFeatureAccess.FeatureID) {
        guard isCurrentDestination(), scenePhase == .active else { return }
        switch feature {
        case .stepGoal: showStepsTarget = true
        case .weightTarget: showWeightTarget = true
        case .reminders: showReminders = true
        }
    }

    private func finishRewardGate() {
        guard isCurrentDestination(), let (feature, decision) = rewardDecision else {
            advertising.features.cancel()
            return
        }
        rewardDecision = nil
        switch decision {
        case .reward(let outcome):
            guard outcome.granted else { return }
            preparingFeature = true
            let token = contextID
            advertising.presentation.rewardDidDismiss(requestID: outcome.requestID) {
                guard contextID == token, isCurrentDestination() else { return }
                preparingFeature = false
                if scenePhase == .active && outcome.granted && advertising.features.consume(featureID: feature, requestID: outcome.requestID) {
                    openFeature(feature)
                }
            }
        case .bypass:
            openFeature(feature)
        case .premium:
            if membership.isPremium { openFeature(feature) }
        case .cancelled:
            break
        }
    }

    private func presentPrivacyOptions() {
        guard !advertising.consent.isBusy, !preparingFeature,
              let presenter = AdMobRewardedAdProvider.activePresenter() else { return }
        advertising.features.cancel()
        advertising.presentation.cancelAll()
        let token = contextID
        privacyTask = Task { @MainActor in
            do { try await advertising.consent.presentPrivacyOptions(from: presenter) }
            catch { if contextID == token && !Task.isCancelled { privacyError = true } }
            advertising.synchronize()
            if contextID == token { privacyTask = nil }
        }
    }

    @ViewBuilder private var profileAvatar: some View {
        if let data = model.snapshot.profile?.avatar, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().clipped() }
        else { Image("user_default_head").resizable() }
    }
    private func header(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 100 * scale)
            ZStack(alignment: .topLeading) {
                Color.clear
                Button { showPersonalInfo = true } label: {
                    profileAvatar.frame(width: 70 * scale, height: 70 * scale)
                        .clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .overlay(alignment: .bottomTrailing) { Image(model.snapshot.profile?.isMale == true ? "personal_ic_boy" : "personal_ic_girl").resizable().frame(width: 20 * scale, height: 20 * scale) }
                }.disabled(preparingFeature).offset(x: 20 * scale, y: -35 * scale)
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
    }
    private func row(_ title: String, subtitle: String?, image: String, scale: CGFloat, systemImage: Bool = false, showsSeparator: Bool = true) -> some View {
        Button { if title == "profile.premium" { showMembership = true } else if title == "profile.stepTarget" { requestFeature(.stepGoal) } else if title == "profile.weightTarget" { requestFeature(.weightTarget) } else if title == "profile.alarms" { requestFeature(.reminders) } else if title == "runningStats.title" { showRunningStatistics = true } else { pendingFeature = title } } label: {
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
            }.padding(.horizontal, 15 * scale).frame(height: 50 * scale)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if showsSeparator { Color.black.opacity(0.15).frame(height: 1/3).padding(.horizontal, 15 * scale) }
                }
        }.buttonStyle(.plain).disabled(preparingFeature).accessibilityIdentifier(title)
    }
}

struct ProfileSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var selectedLegalDocument: LegalDocument?
    @Default(.appLanguage) private var language
    var body: some View {
        List {
            Section {
                NavigationLink { ProfileInfoView() } label: {
                    HStack { Text("info.title"); Spacer(); Text(model.snapshot.profile?.nickname ?? "").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("profile.edit")
            }
            NavigationLink { LanguageSettingsView() } label: {
                HStack {
                    Text("settings.language")
                    Spacer()
                    Text(LocalizedStringKey((AppLanguage(rawValue: language) ?? .system).titleKey)).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("settings.language")
            Section {
                Button("legal.privacyPolicy") { selectedLegalDocument = .privacy }
                    .accessibilityIdentifier("settings.privacyPolicy")
                Button("legal.userAgreement") { selectedLegalDocument = .agreement }
                    .accessibilityIdentifier("settings.userAgreement")
            }
        }.listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .background {
            LinearGradient(colors: [KeepUpStyle.theme, .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $selectedLegalDocument) { document in
            LegalDocumentSafariView(document: document, locale: locale)
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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .background {
            LinearGradient(colors: [KeepUpStyle.theme, .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("settings.language").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

private struct RewardGateRequest: Identifiable {
    let id = UUID()
    let feature: RewardedFeatureAccess.FeatureID
}
