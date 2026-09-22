import SwiftUI

enum AppTab: Hashable { case calendar, history, profile }

struct RootView: View {
    @Default(.privacyAccepted) private var privacyAccepted
    @Binding var selectedTab: AppTab
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showWelcomeMembership = false
    @State private var completingOnboarding = false
    @State private var homeIsVisible = false
    @State private var stepPermission = HomeStepPermission()
    @State private var selectedDate = Date.now
    @State private var catalogRequest: CatalogRequest?

    var body: some View {
        Group {
            if model.isReady && !privacyAccepted && model.snapshot.profile == nil && !skipOnboardingForTests {
                StartupPrivacyView { privacyAccepted = true }
            } else if model.isReady && model.snapshot.profile == nil && !skipOnboardingForTests {
                UserInfoFlowView { profile in
                    completingOnboarding = true
                    let saved = await model.saveProfile(profile)
                    if saved {
                        let membership = MembershipStore()
                        await membership.refreshEntitlements()
                        if !membership.isPremium && !membership.configuration.offers.isEmpty {
                            showWelcomeMembership = true
                        } else { completingOnboarding = false }
                    } else { completingOnboarding = false }
                    return saved
                }
            } else if model.isReady {
                NavigationStack(path: Binding(
                    get: { selectedTab == .calendar ? [] : [selectedTab] },
                    set: { selectedTab = $0.last ?? .calendar }
                )) {
                    CalendarHomeView(selectedDate: $selectedDate,
                                     openHistory: { selectedTab = .history },
                                     openProfile: { selectedTab = .profile },
                                     openCatalog: { openCatalog() })
                        .background(HomeVisibilityObserver { homeIsVisible = $0 })
                        .navigationDestination(for: AppTab.self) { destination in
                            switch destination {
                            case .history: HistoryView()
                            case .profile: ProfileView()
                            case .calendar: EmptyView()
                            }
                        }
                }
                .fullScreenCover(item: $catalogRequest) { request in
                    CardCatalogView(day: request.day, initialCardID: request.initialCardID)
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
        .fullScreenCover(isPresented: $showWelcomeMembership, onDismiss: { completingOnboarding = false }) {
            MembershipView(isOnboarding: true, onClose: { showWelcomeMembership = false })
        }
        .task(id: canRequestStepPermission) {
            await stepPermission.requestIfNeeded(profileComplete: model.snapshot.profile != nil,
                                                 homeVisible: canRequestStepPermission)
        }
        .task {
            await model.load()
            if model.snapshot.profile != nil { privacyAccepted = true }
            openRequestedReminder()
            #if DEBUG
            await ReminderNotificationDelegate.scheduleRouteTestIfRequested()
            #endif
        }
        .onChange(of: model.isReady) { _, ready in if ready { openRequestedReminder() } }
        .onChange(of: model.snapshot.profile != nil) { _, _ in openRequestedReminder() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .alert("error.title", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("action.ok") { model.actionError = nil }
        } message: { Text(LocalizedStringKey(model.actionError ?? "error.storage")) }
    }

    private var canRequestStepPermission: Bool {
        model.isReady && model.snapshot.profile != nil && selectedTab == .calendar && homeIsVisible &&
        scenePhase == .active && !completingOnboarding && !showWelcomeMembership && catalogRequest == nil
    }

    private var skipOnboardingForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-skip-onboarding")
        #else
        false
        #endif
    }

    private func openRequestedReminder() {
        guard model.isReady, model.snapshot.profile != nil || skipOnboardingForTests,
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
