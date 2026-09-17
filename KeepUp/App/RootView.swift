import SwiftUI

enum AppTab: Hashable { case calendar, history, profile }

struct RootView: View {
    @Binding var selectedTab: AppTab
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showWelcomeMembership = false
    @State private var selectedDate = Date.now
    @State private var catalogRequest: CatalogRequest?

    var body: some View {
        Group {
            if model.isReady && model.snapshot.profile == nil && !skipOnboardingForTests {
                UserInfoFlowView { profile in
                    let saved = await model.saveProfile(profile)
                    if saved { showWelcomeMembership = true }
                    return saved
                }
            } else if model.isReady {
                Group {
                    switch selectedTab {
                    case .calendar: CalendarHomeView(selectedDate: $selectedDate) { openCatalog() }
                    case .history: HistoryView()
                    case .profile: ProfileView()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
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
        .fullScreenCover(isPresented: $showWelcomeMembership) { MembershipView(isOnboarding: true, onClose: { showWelcomeMembership = false }) }
        .task {
            await model.load(); openRequestedReminder()
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

    private var skipOnboardingForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-skip-onboarding")
        #else
        false
        #endif
    }

    private var tabBar: some View {
        HStack(alignment: .center, spacing: 0) {
            tab(.history, title: "nav.history", image: "homepage_tab_btn_store")
            Button {
                if selectedTab == .calendar { openCatalog() }
                else { selectedTab = .calendar }
            } label: {
                Group {
                    if selectedTab == .calendar {
                        Image("homepage_btn_go").resizable().scaledToFit().frame(width: 64.5, height: 67).offset(y: -16.5)
                    } else {
                        VStack(spacing: 6) {
                            Image("homepage_tab_btn_homepage_n").resizable().scaledToFit().frame(width: 24, height: 24)
                            Text("nav.calendar").font(.system(size: 10))
                        }
                    }
                }.frame(maxWidth: .infinity).frame(height: 49).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(selectedTab == .calendar ? "action.checkIn" : "nav.calendar"))
                .accessibilityIdentifier("tab.calendar")
            tab(.profile, title: "nav.profile", image: "homepage_tab_btn_my")
        }
        .foregroundStyle(Color.black.opacity(0.65))
        .background(KeepUpStyle.theme.ignoresSafeArea(edges: .bottom))
    }

    private func tab(_ tab: AppTab, title: LocalizedStringKey, image: String) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 6) {
                Image(image + (selectedTab == tab ? "_p" : "_n"))
                    .resizable().scaledToFit().frame(width: 24, height: 24)
                Text(title).font(.system(size: 10))
            }.frame(maxWidth: .infinity).frame(height: 49).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier(tab == .history ? "tab.history" : "tab.profile")
            .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
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
