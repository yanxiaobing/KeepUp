import SwiftUI

struct ProfileView: View {
    var isCurrentDestination: () -> Bool = { true }
    @Environment(AppAdvertising.self) private var advertising
    @Environment(MembershipStore.self) private var membership
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var selectedLegalDocument: LegalDocument?
    @State private var contextID = UUID()
    @State private var featureTask: Task<Void, Never>?
    @State private var privacyTask: Task<Void, Never>?
    private var entries: [CheckInEntry] { model.snapshot.entries }
    private var profileNickname: String {
        let nickname = model.snapshot.profile?.nickname ?? ""
        return nickname.isEmpty ? localized("profile.nickname", locale) : nickname
    }
    private var profileMotto: String {
        let value = model.snapshot.profile?.motto ?? ""
        return value.isEmpty ? localized("profile.defaultMotto", locale) : value
    }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader
                    VStack(alignment: .leading, spacing: 18) {
                        membershipCard
                        section("profile.goals") {
                            rowGroup {
                                actionRow("profile.stepTarget", symbol: "figure.walk", value: stepGoalDescription, identifier: "profile.stepTarget") {
                                    requestFeature(.stepGoal)
                                }
                                separator
                                actionRow("profile.weightTarget", symbol: "scalemass", value: weightGoalDescription, identifier: "profile.weightTarget") {
                                    requestFeature(.weightTarget)
                                }
                            }
                        }
                        section("profile.activity") {
                            rowGroup {
                                actionRow("runningStats.title", symbol: "figure.run", identifier: "runningStats.title") { showRunningStatistics = true }
                                separator
                                actionRow("profile.alarms", symbol: "bell", identifier: "profile.alarms") { requestFeature(.reminders) }
                            }
                        }
                        section("profile.more") {
                            rowGroup {
                                actionRow("profile.review", symbol: "star", identifier: "profile.review") { pendingFeature = "profile.review" }
                                separator
                                actionRow("profile.contact", symbol: "envelope", identifier: "profile.contact") { pendingFeature = "profile.contact" }
                                separator
                                Button { selectedLegalDocument = .privacy } label: {
                                    rowLabel("legal.privacyPolicy", symbol: "hand.raised")
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.privacyPolicy")
                                separator
                                Button { selectedLegalDocument = .agreement } label: {
                                    rowLabel("legal.userAgreement", symbol: "doc.text")
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.userAgreement")
                                if advertising.consent.privacyOptionsRequired {
                                    separator
                                    actionRow("ads.privacyOptions", symbol: "hand.raised", identifier: "ads.privacyOptions") { presentPrivacyOptions() }
                                        .disabled(advertising.consent.isBusy || preparingFeature)
                                }
                            }
                        }
                        Text(verbatim: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .accessibilityIdentifier("profile.version")
                    }
                    .padding(.horizontal, 15)
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    Color.white
                    LinearGradient(stops: [
                        .init(color: KeepUpStyle.theme, location: 0),
                        .init(color: KeepUpStyle.theme.opacity(0.06), location: 0.78)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("nav.profile")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(item: $selectedLegalDocument) { document in
                LegalDocumentSafariView(document: document, locale: locale)
            }
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

    private var stepGoalDescription: String {
        StepsGoal.value(on: LocalDay(date: .now), changes: stepGoalChanges)
            .map { String(format: localized("steps.goal %lld", locale), Int64($0)) }
            ?? localized("profile.noSteps", locale)
    }

    private var weightGoalDescription: String {
        model.snapshot.weightTarget
            .map { $0.target.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " kg" }
            ?? localized("profile.noTarget", locale)
    }

    @ViewBuilder private var profileAvatar: some View {
        if let data = model.snapshot.profile?.avatar, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image("user_default_head").resizable().scaledToFill()
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 50) {
            Button { showPersonalInfo = true } label: {
                HStack(spacing: 14) {
                    profileAvatar
                        .frame(width: 66, height: 66)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: profileNickname)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: profileMotto)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.65))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(preparingFeature)
            .accessibilityIdentifier("profile.nickname")
            .accessibilityLabel(Text(verbatim: profileNickname))
            .accessibilityValue(Text(verbatim: profileMotto))

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { profileMilestones }
                } else {
                    HStack(spacing: 14) { profileMilestones }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            Image("me_bg_title")
                .resizable()
                .scaledToFill()
                .frame(height: 112)
                .clipped()
                .opacity(0.32)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var profileMilestones: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let days = ProfileDuration.dayCount(since: model.snapshot.profile?.createdAt ?? context.date, now: context.date)
            HStack(spacing: 6) {
                Image(systemName: "calendar").accessibilityHidden(true)
                Text(String(format: localized("profile.journey %lld", locale), Int64(days)))
                    .accessibilityIdentifier("profile.journey")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.82), in: Capsule())
        }

        HStack(spacing: 6) {
            Image(systemName: "flame.fill").foregroundStyle(KeepUpStyle.accent)
            Text(verbatim: String(format: localized("profile.streakFormat %lld", locale), Int64(RecordStatistics.streak(entries: entries, today: LocalDay(date: .now)))))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.white.opacity(0.82), in: Capsule())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.68))
                .padding(.leading, 3)
            content()
        }
    }

    private var membershipCard: some View {
        Button { showMembership = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(LinearGradient(colors: [KeepUpStyle.accent, Color(red: 1, green: 0.63, blue: 0.43)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("profile.premium")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.16))
                    Text(LocalizedStringKey(membership.isPremium ? "membership.active" : "profile.premiumSubtitle"))
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.43))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KeepUpStyle.accent)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.9), in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 17)
            .frame(minHeight: 84)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.99, blue: 0.97),
                                                  Color(red: 1, green: 0.94, blue: 0.89)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 92))
                            .foregroundStyle(KeepUpStyle.accent.opacity(0.07))
                            .rotationEffect(.degrees(-18))
                            .offset(x: 12, y: 10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(KeepUpStyle.accent.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: KeepUpStyle.accent.opacity(0.08), radius: 12, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(preparingFeature)
        .accessibilityIdentifier("profile.premium")
    }

    private func rowGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var separator: some View {
        Color.black.opacity(0.09).frame(height: 0.5).padding(.leading, 51).padding(.trailing, 16)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.primary.opacity(0.72))
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    private func rowLabel(_ title: String, symbol: String, value: String? = nil) -> some View {
        HStack(spacing: 13) {
            rowIcon(symbol)
            if dynamicTypeSize.isAccessibilitySize, let value {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                    Text(verbatim: value).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(LocalizedStringKey(title))
                Spacer(minLength: 6)
                if let value {
                    Text(verbatim: value)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func actionRow(_ title: String, symbol: String, value: String? = nil, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol, value: value) }
            .buttonStyle(.plain)
            .disabled(preparingFeature)
            .accessibilityIdentifier(identifier)
    }
}

struct ProfileSettingsView: View {
    @Environment(\.locale) private var locale
    @Default(.appLanguage) private var language
    @Default(.firstWeekday) private var firstWeekdaySelection
    var body: some View {
        List {
            Menu {
                ForEach(AppLanguage.allCases, id: \.rawValue) { item in
                    Button { language = item.rawValue } label: {
                        if language == item.rawValue {
                            Label(LocalizedStringKey(item.titleKey), systemImage: "checkmark")
                        } else {
                            Text(LocalizedStringKey(item.titleKey))
                        }
                    }.accessibilityIdentifier("language.\(item.rawValue)")
                }
            } label: {
                HStack(spacing: 8) {
                    Text("settings.language").foregroundStyle(Color.primary)
                    Spacer()
                    Text(LocalizedStringKey((AppLanguage(rawValue: language) ?? .system).titleKey))
                        .foregroundStyle(Color.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.language")
            Menu {
                ForEach([2, 1], id: \.self) { weekday in
                    Button { firstWeekdaySelection = weekday } label: {
                        let title = LocalizedStringKey(weekday == 2 ? "settings.monday" : "settings.sunday")
                        if WeekStartPreference.weekday(locale: locale, selection: firstWeekdaySelection) == weekday {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }.accessibilityIdentifier(weekday == 2 ? "firstWeekday.monday" : "firstWeekday.sunday")
                }
            } label: {
                HStack(spacing: 8) {
                    Text("settings.firstWeekday").foregroundStyle(Color.primary)
                    Spacer()
                    Text(LocalizedStringKey(WeekStartPreference.weekday(locale: locale, selection: firstWeekdaySelection) == 2
                        ? "settings.monday" : "settings.sunday"))
                        .foregroundStyle(Color.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.firstWeekday")
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
        .navigationTitle("profile.settings").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
private struct RewardGateRequest: Identifiable {
    let id = UUID()
    let feature: RewardedFeatureAccess.FeatureID
}
