import SwiftUI
import Combine
import UserNotifications

enum AppLanguage: String, CaseIterable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        default: Locale(identifier: rawValue)
        }
    }
    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .simplifiedChinese: "language.chinese"
        }
    }
}

@main
struct KeepUpApp: App {
    @Default(.privacyAccepted) private var privacyAccepted
    @Default(.appLanguage) private var language
    @Default(.themeID) private var themeID
    @Default(.stepGoalChanges) private var stepGoalChanges
    @Default(.runningSettings) private var runningSettings
    @State private var stepMonitor = StepsController(day: LocalDay(date: .now))
    private let stepClock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.calendar
    @State private var membership: MembershipStore
    @State private var advertising: AppAdvertising
    @State private var iaap: IAAPConfigurationStore

    init() {
        #if DEBUG
        let isolatedConfiguration = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        let isolatedConfiguration = false
        #endif
        _iaap = State(initialValue: IAAPConfigurationStore(
            remoteURL: isolatedConfiguration ? nil : IAAPConfigurationStore.configuredRemoteURL,
            cacheURL: isolatedConfiguration ? nil : IAAPConfigurationStore.defaultCacheURL
        ))
        let membership = MembershipStore()
        _membership = State(initialValue: membership)
        let advertising = AppAdvertising(membership: membership, receiptURL: isolatedConfiguration
            ? URL.applicationSupportDirectory.appendingPathComponent("KeepUp/ui-tests/reward-receipts.json") : nil)
        _advertising = State(initialValue: advertising)
        UNUserNotificationCenter.current().delegate = ReminderNotificationDelegate.shared
        let support = URL.applicationSupportDirectory.appendingPathComponent("KeepUp", isDirectory: true)
        var databaseURL = support.appendingPathComponent("keepup.sqlite")
        #if DEBUG
        // UI tests use an isolated file and never reset a developer's normal app data.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            databaseURL = support.appendingPathComponent("ui-tests/keepup.sqlite")
            if ProcessInfo.processInfo.arguments.contains("-reset-test-data") {
                try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
                AppPreferences.reset()
            }
        }
        #endif
        _model = State(initialValue: AppModel(repository: LocalStore(fileURL: databaseURL)))
    }

    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
                .environment(model)
                .environment(membership)
                .environment(advertising)
                .environment(advertising.consent)
                .task(id: "\(membership.canShowAds)-\(privacyAccepted)-\(advertising.consent.canRequestAds)") {
                    advertising.synchronize()
                }
                .onChange(of: iaap.configuration) { _, configuration in
                    advertising.update(configuration: configuration)
                    membership.applyConfiguration(configuration: configuration.membershipConfiguration(), entitlementProductIDs: iaap.entitlementProductIDs)
                }
                .task(id: Set(iaap.configuration.iaaps.flatMap { $0.iap.pids })) {
                    await membership.prefetchProducts(ids: Set(iaap.configuration.iaaps.flatMap { $0.iap.pids }))
                }
                .environment(iaap)
                .task {
                    membership.applyConfiguration(configuration: iaap.configuration.membershipConfiguration(), entitlementProductIDs: iaap.entitlementProductIDs)
                    advertising.update(configuration: iaap.configuration)
                    await membership.start()
                    advertising.finishedMembershipRefresh()
                    await iaap.refresh()
                    membership.applyConfiguration(configuration: iaap.configuration.membershipConfiguration(), entitlementProductIDs: iaap.entitlementProductIDs)
                    await membership.refreshEntitlements()
                }
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
                // Rebuild navigation titles as well as content after an in-app language change.
                .id("\(language)-\(themeID)-\(ReminderRoute.shared.requestID)")
                .tint(KeepUpStyle.accent)
                .task(id: "\(model.revision)-\(language)-\(scenePhase)") {
                    if scenePhase == .active && model.isReady {
                        await ReminderScheduler.shared.synchronize(model.snapshot, locale: (AppLanguage(rawValue: language) ?? .system).locale)
                    }
                }
                .task(id: "\(model.isReady)-\(model.snapshot.profile != nil)-\(scenePhase)-\(stepGoalChanges.sorted { $0.key < $1.key })") {
                    refreshStepMonitoring()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await membership.refreshEntitlements()
                            guard scenePhase == .active else { return }
                            advertising.synchronize()
                            if advertising.presentation.hasHotStartOpportunity {
                                await advertising.prepareConsentIfNeeded()
                            }
                            guard scenePhase == .active else { return }
                            advertising.presentation.didBecomeActive()
                        }
                    }
                    if phase == .background {
                        advertising.didEnterBackground()
                    }
                    if model.running.session != nil { Task { await model.running.tick() } }
                }
                .onChange(of: runningSettings) { _, _ in model.refreshRunningSettings() }
                .onChange(of: language) { _, _ in model.refreshRunningSettings() }
                .onReceive(stepClock) { _ in
                    guard scenePhase == .active, model.isReady else { return }
                    if stepMonitor.needsDateRefresh() || stepMonitor.state == .permission || stepMonitor.state == .failed {
                        refreshStepMonitoring()
                    }
                }
                #if DEBUG
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("-ui-testing-large-type") { size = .accessibility3 }
                }
                .preferredColorScheme(.light)
                #endif
        }
    }

    private func refreshStepMonitoring() {
        guard scenePhase == .active, model.isReady, model.snapshot.profile != nil,
              StepsGoal.value(on: LocalDay(date: .now), changes: stepGoalChanges) != nil else {
            stepMonitor.stop()
            return
        }
        // Monitoring never requests permission; RootView waits for the home screen, or StepsView requests it explicitly.
        stepMonitor.refresh { await model.saveSteps($0) }
    }

}
