import SwiftUI

enum AppTab: Hashable { case calendar, history, profile }

struct RootView: View {
    @Default(.privacyAccepted) private var privacyAccepted
    @Binding var selectedTab: AppTab
    @Environment(AppModel.self) private var model
    @Environment(MembershipStore.self) private var membership
    @Environment(IAAPConfigurationStore.self) private var iaap
    @Environment(AppAdvertising.self) private var advertising
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showWelcomeMembership = false
    @State private var completingOnboarding = false
    @State private var homeIsVisible = false
    @State private var stepPermission = HomeStepPermission()
    @State private var selectedDate = Date.now
    @State private var currentDay = LocalDay(date: .now)
    @State private var currentTimeZone = TimeZone.current
    @State private var catalogRequest: CatalogRequest?
    @State private var startupFinished = false
    @State private var showLaunchMembership = false
    @State private var launchMembershipID: UUID?

    var body: some View {
        Group {
            if model.isReady && !privacyAccepted && model.snapshot.profile == nil && !skipOnboardingForTests {
                StartupPrivacyView { privacyAccepted = true }
            } else if model.isReady && model.snapshot.profile == nil && !skipOnboardingForTests {
                UserInfoFlowView { profile in
                    completingOnboarding = true
                    let saved = await model.saveProfile(profile)
                    if saved {
                        await membership.refreshEntitlements()
                        if !membership.isPremium && !iaap.configuration.membershipConfiguration(for: "guide").offers.isEmpty {
                            showWelcomeMembership = true
                        } else { await finishOnboardingAdvertising() }
                    } else { completingOnboarding = false }
                    return saved
                }
            } else if model.isReady {
                NavigationStack(path: Binding(
                    get: { selectedTab == .calendar ? [] : [selectedTab] },
                    set: { selectedTab = $0.last ?? .calendar }
                )) {
                    CalendarHomeView(selectedDate: $selectedDate, today: currentDay,
                                     openHistory: { selectedTab = .history },
                                     openProfile: { selectedTab = .profile },
                                     openCatalog: { openCatalog() })
                        .background(HomeVisibilityObserver { homeIsVisible = $0 })
                        .navigationDestination(for: AppTab.self) { destination in
                            switch destination {
                            case .history: HistoryView()
                            case .profile: ProfileView(isCurrentDestination: { selectedTab == .profile })
                            case .calendar: EmptyView()
                            }
                        }
                }
                .fullScreenCover(item: $catalogRequest) { request in
                    CardCatalogView(day: request.day, initialCardID: request.initialCardID, onStepsAdded: { selectedDate = .now })
                        .environment(\.dynamicTypeSize, dynamicTypeSize)
                }
            } else if let error = model.loadError {
                ContentUnavailableView {
                    Label("error.openTitle", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text(LocalizedStringKey(error)) } actions: {
                    Button("action.retry") { Task { await model.load() } }.buttonStyle(.borderedProminent)
                }
            } else { ProgressView("app.loading") }
        }
        .overlay {
            if model.isReady && !startupFinished {
                ZStack { Color(uiColor: .systemBackground).ignoresSafeArea(); ProgressView("app.loading") }
            }
        }
        .fullScreenCover(isPresented: $showWelcomeMembership, onDismiss: {
            Task { await finishOnboardingAdvertising() }
        }) {
            MembershipView(isOnboarding: true, onClose: { showWelcomeMembership = false })
        }
        .fullScreenCover(isPresented: $showLaunchMembership, onDismiss: {
            if let id = launchMembershipID { advertising.presentation.launchMembershipDidDismiss(requestID: id) }
            launchMembershipID = nil
        }) {
            MembershipView(onClose: { showLaunchMembership = false }, entryPoint: "launch")
        }
        .onChange(of: advertising.presentation.launchMembershipRequestID) { _, id in
            guard let id else { showLaunchMembership = false; return }
            guard !membership.isPremium, catalogRequest == nil, !showWelcomeMembership,
                  !iaap.configuration.membershipConfiguration(for: "launch").offers.isEmpty else {
                advertising.presentation.launchMembershipDidDismiss(requestID: id)
                return
            }
            launchMembershipID = id
            showLaunchMembership = true
        }
        .task(id: canRequestStepPermission) {
            await stepPermission.requestIfNeeded(profileComplete: model.snapshot.profile != nil,
                                                 homeVisible: canRequestStepPermission)
        }
        .task {
            await model.load()
            if model.snapshot.profile != nil { privacyAccepted = true }
            await handleColdStart()
            openRequestedReminder()
            #if DEBUG
            await ReminderNotificationDelegate.scheduleRouteTestIfRequested()
            #endif
        }
        .onChange(of: selectedTab) { _, _ in
            advertising.features.cancel()
            advertising.presentation.cancelAll()
        }
        .onChange(of: model.isReady) { _, ready in if ready { openRequestedReminder() } }
        .onChange(of: model.snapshot.profile != nil) { _, _ in openRequestedReminder() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshCalendarDay()
                Task { await model.load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCalendarDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshCalendarDay()
        }
        .alert("error.title", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("action.ok") { model.actionError = nil }
        } message: { Text(LocalizedStringKey(model.actionError ?? "error.storage")) }
    }

    private var canRequestStepPermission: Bool {
        model.isReady && model.snapshot.profile != nil && selectedTab == .calendar && homeIsVisible &&
        scenePhase == .active && startupFinished && !advertising.presentation.isRunning &&
        !completingOnboarding && !showWelcomeMembership && !showLaunchMembership && catalogRequest == nil
    }

    @MainActor private func finishOnboardingAdvertising() async {
        defer { completingOnboarding = false }
        await advertising.prepareConsentIfNeeded()
        guard !Task.isCancelled else { return }
        advertising.presentation.guideDidDismiss()
        while advertising.presentation.isRunning {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    @MainActor private func handleColdStart() async {
        guard !startupFinished else { return }
        defer {
            advertising.presentation.invalidateColdStartOpportunity()
            startupFinished = true
        }
        // Use the already loaded bundle/cache. A late network response is not a launch opportunity.
        advertising.update(configuration: iaap.configuration)
        guard model.snapshot.profile != nil, !skipOnboardingForTests, catalogRequest == nil else {
            advertising.presentation.coldStart(isExistingUser: false)
            return
        }
        for _ in 0..<20 where !advertising.membershipReady {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard advertising.membershipReady, !Task.isCancelled else { return }
        if advertising.configuration.enabled, advertising.configuration.appOpenAdUnitID != nil {
            await advertising.prepareConsentIfNeeded()
        }
        guard !Task.isCancelled else { return }
        advertising.presentation.coldStart(isExistingUser: true)
        while advertising.presentation.isRunning {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled, !membership.isPremium, catalogRequest == nil,
              !iaap.configuration.membershipConfiguration(for: "launch").offers.isEmpty else { return }
        advertising.presentation.requestLaunchMembership()
    }

    private var skipOnboardingForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-skip-onboarding")
        #else
        false
        #endif
    }

    private func openRequestedReminder() {
        guard model.isReady, startupFinished, model.snapshot.profile != nil || skipOnboardingForTests,
              let cardID = ReminderRoute.shared.cardID else { return }
        ReminderRoute.shared.cardID = nil
        guard !model.snapshot.archivedCardIDs.contains(cardID), model.snapshot.cards.contains(where: { $0.id == cardID }) else { return }
        selectedTab = .calendar; selectedDate = .now
        catalogRequest = CatalogRequest(day: LocalDay(date: .now), initialCardID: cardID)
    }

    private func openCatalog() {
        // Capture the chosen civil day in the presentation item; a Boolean sheet
        // can reuse its earlier closure and incorrectly submit a backfill for today.
        catalogRequest = CatalogRequest(day: LocalDay(date: selectedDate))
    }

    private func refreshCalendarDay() {
        let timeZone = TimeZone.current
        let today = LocalDay(date: .now)
        let zoneChanged = timeZone.identifier != currentTimeZone.identifier
        guard today != currentDay || zoneChanged else { return }
        let selectedDay = LocalDay(date: selectedDate, timeZone: currentTimeZone)
        if selectedDay == currentDay { selectedDate = .now }
        else if zoneChanged { selectedDate = selectedDay.date(in: timeZone) }
        currentDay = today
        currentTimeZone = timeZone
    }
}

private struct CatalogRequest: Identifiable {
    let day: LocalDay
    var initialCardID: String? = nil
    var id: String { day.rawValue + (initialCardID ?? "") }
}

/// A selected tab is not proof that its screen has appeared (especially during onboarding).
private struct HomeVisibilityObserver: UIViewControllerRepresentable {
    let onVisibilityChanged: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onVisibilityChanged = onVisibilityChanged
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onVisibilityChanged = onVisibilityChanged
    }

    final class Controller: UIViewController {
        var onVisibilityChanged: ((Bool) -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onVisibilityChanged?(true)
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onVisibilityChanged?(false)
        }
    }
}
