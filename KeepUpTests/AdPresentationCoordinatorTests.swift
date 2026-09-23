import Foundation
import Testing
@testable import KeepUp

@MainActor struct AdPresentationCoordinatorTests {
    @Test func launchMembershipDoesNotRequireAdvertisingAndSurvivesConfigRefresh() throws {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: .disabled, canShowAds: true, privacyAllowsAds: false)
        coordinator.coldStart(isExistingUser: true)
        coordinator.requestLaunchMembership()
        let id = try #require(coordinator.launchMembershipRequestID)
        coordinator.synchronize(configuration: .disabled, canShowAds: true, privacyAllowsAds: false)
        #expect(coordinator.launchMembershipRequestID == id)
        coordinator.launchMembershipDidDismiss(requestID: id)
        coordinator.requestLaunchMembership()
        #expect(coordinator.launchMembershipRequestID == nil)
        #expect(open.loads == 0 && insert.loads == 0)
    }

    @Test func launchMembershipSurvivesBackgroundAndHotActivation() async throws {
        let open = PresentationDriver(), insert = PresentationDriver()
        var now = 0.0
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, now: { now })
        coordinator.synchronize(configuration: .disabled, canShowAds: true, privacyAllowsAds: false)
        coordinator.coldStart(isExistingUser: true)
        coordinator.requestLaunchMembership()
        let id = try #require(coordinator.launchMembershipRequestID)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)

        coordinator.didEnterBackground()
        #expect(coordinator.launchMembershipRequestID == id)
        now = 31
        #expect(coordinator.hasHotStartOpportunity)
        coordinator.didBecomeActive()
        #expect(coordinator.launchMembershipRequestID == id)
        #expect(open.loads == 0)

        coordinator.launchMembershipDidDismiss(requestID: id)
        await waitUntil { insert.presentationContinuation != nil }
        #expect(coordinator.launchMembershipRequestID == nil)
        insert.finish(.closed)
    }

    @Test func disabledAndFirstInstallNeverRequestAds() async {
        for existing in [false, true] {
            let open = PresentationDriver(), insert = PresentationDriver()
            let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
            coordinator.synchronize(configuration: existing ? .disabled : config(), canShowAds: true, privacyAllowsAds: true)
            coordinator.coldStart(isExistingUser: existing)
            coordinator.didBecomeActive()
            await waitUntil { !coordinator.isRunning }
            #expect(open.loads == 0)
            #expect(insert.loads == 0)
        }
    }

    @Test func hotStartRequiresBackgroundAndExactThreshold() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        var now = 0.0
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, now: { now })
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.didBecomeActive()
        coordinator.didEnterBackground()
        now = 29.99
        coordinator.didBecomeActive()
        await waitUntil { !coordinator.isRunning }
        #expect(open.loads == 0)
        now = 100 // Use an exactly representable baseline for the exact 30-second boundary.
        coordinator.didEnterBackground()
        now = 130
        coordinator.didBecomeActive()
        coordinator.didBecomeActive()
        await waitUntil { open.presentationContinuation != nil }
        #expect(open.presentations == 1)
        open.finish(.closed)
        await waitUntil { insert.presentationContinuation != nil }
        insert.finish(.closed)
    }

    @Test func hotOpportunityIsIndependentOfConsentAndConsumedExactlyOnce() {
        let open = PresentationDriver(), insert = PresentationDriver()
        let context = PresentationContext()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, now: { context.time })
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: false)
        #expect(!coordinator.hasHotStartOpportunity)
        coordinator.didBecomeActive()
        #expect(!coordinator.hasHotStartOpportunity)
        coordinator.didEnterBackground()
        context.time = 29.99
        #expect(!coordinator.hasHotStartOpportunity)
        context.time = 30
        #expect(coordinator.hasHotStartOpportunity)
        coordinator.didBecomeActive()
        #expect(!coordinator.hasHotStartOpportunity)
        #expect(open.loads == 0) // Opportunity alone cannot bypass missing consent.
    }

    @Test func interstitialWaitsForRealHotSplashClosure() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        var now = 0.0
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, now: { now })
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.didEnterBackground()
        now = 30
        coordinator.didBecomeActive()
        await waitUntil { open.presentationContinuation != nil }
        #expect(open.presentations == 1)
        #expect(insert.presentations == 0)
        open.finish(.closed)
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.presentations == 1)
        insert.finish(.closed)
    }

    @Test func coldSplashRequestsMembershipAndOnlyDismissalTriggersInsert() async throws {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.coldStart(isExistingUser: true)
        coordinator.coldStart(isExistingUser: true)
        await waitUntil { open.presentationContinuation != nil }
        #expect(open.presentations == 1)
        #expect(coordinator.launchMembershipRequestID == nil)
        open.finish(.closed)
        await waitUntil { coordinator.launchMembershipRequestID != nil && !coordinator.isRunning }
        let token = try #require(coordinator.launchMembershipRequestID)
        #expect(insert.presentations == 0)
        coordinator.launchMembershipDidDismiss(requestID: token)
        coordinator.launchMembershipDidDismiss(requestID: token)
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.presentations == 1)
        insert.finish(.closed)
    }

    @Test func hostInvalidatesSlowColdLoadBeforeMainContent() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        open.pauseLoad = true
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.coldStart(isExistingUser: true)
        await waitUntil { open.loadContinuation != nil }
        coordinator.invalidateColdStartOpportunity()
        open.finishLoad()
        await waitUntil { open.loadReturns == 1 }
        #expect(open.presentations == 0)
        #expect(!coordinator.isRunning)
        #expect(coordinator.launchMembershipRequestID == nil)
    }

    @Test func revokedQualificationDoesNotContinueAfterVisibleAdCloses() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.coldStart(isExistingUser: true)
        await waitUntil { open.presentationContinuation != nil }
        coordinator.synchronize(configuration: config(), canShowAds: false, privacyAllowsAds: true)
        open.finish(.closed)
        await waitUntil { !coordinator.isRunning }
        #expect(coordinator.launchMembershipRequestID == nil)
        #expect(insert.loads == 0)
    }

    @Test func guideAndRewardEventsAreDeduplicatedAndBusyEventsNotQueued() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.guideDidDismiss()
        coordinator.guideDidDismiss()
        coordinator.rewardDidDismiss(requestID: UUID())
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.presentations == 1)
        insert.finish(.closed)
        await waitUntil { !coordinator.isRunning }
        let reward = UUID()
        coordinator.rewardDidDismiss(requestID: reward)
        coordinator.rewardDidDismiss(requestID: reward)
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.presentations == 2)
        insert.finish(.closed)
    }

    @Test func hostPresentationGuardSuppressesAdsOverEditorOrMembership() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, presentationAllowed: { false })
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.guideDidDismiss()
        await waitUntil { !coordinator.isRunning }
        #expect(insert.presentations == 0)
        #expect(insert.loads == 0)
    }

    @Test func rewardCompletionWaitsForInterstitialTerminalEvent() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        var completed = false
        coordinator.rewardDidDismiss(requestID: UUID()) { completed = true }
        await waitUntil { insert.presentationContinuation != nil }
        #expect(!completed)
        insert.finish(.closed)
        await waitUntil { completed }
        #expect(completed)
    }

    @Test func coldLoadingDeadlineExpiresOpportunityWithoutShowingLateAd() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        open.pauseLoad = true
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, coldLoadTimeout: .milliseconds(20))
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.coldStart(isExistingUser: true)
        await waitUntil { !coordinator.isRunning }
        open.finishLoad()
        await waitUntil { open.loadReturns == 1 }
        #expect(open.presentations == 0)
        #expect(coordinator.launchMembershipRequestID == nil)
    }

    @Test func rewardLoadTimeoutCompletesHostWithoutWaitingForSdkAndRejectsLateAd() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        insert.pauseLoad = true
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, loadTimeout: .milliseconds(20))
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        var completions = 0
        coordinator.rewardDidDismiss(requestID: UUID()) { completions += 1 }
        await waitUntil { completions == 1 }
        #expect(!coordinator.isRunning)
        #expect(insert.presentations == 0)
        insert.finishLoad()
        await waitUntil { insert.loadReturns == 1 }
        #expect(insert.presentations == 0)
        #expect(completions == 1)
    }

    @Test func allCancellationPathsCompletePendingRewardLoadWithoutSdkResponse() async {
        for cancellation in 0..<3 {
            let open = PresentationDriver(), insert = PresentationDriver()
            insert.pauseLoad = true
            let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
            coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
            var completions = 0
            coordinator.rewardDidDismiss(requestID: UUID()) { completions += 1 }
            await waitUntil { insert.loadContinuation != nil }
            if cancellation == 0 { coordinator.cancelAll() }
            else if cancellation == 1 { coordinator.didEnterBackground() }
            else { coordinator.synchronize(configuration: .disabled, canShowAds: false, privacyAllowsAds: false) }
            await waitUntil { completions == 1 }
            #expect(completions == 1)
            #expect(!coordinator.isRunning)
            insert.finishLoad()
            await waitUntil { insert.loadReturns == 1 }
            #expect(insert.presentations == 0)
            #expect(completions == 1)
        }
    }

    @Test func cancellingVisibleRewardInsertStillWaitsForRealDismissal() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        var completions = 0
        coordinator.rewardDidDismiss(requestID: UUID()) { completions += 1 }
        await waitUntil { insert.presentationContinuation != nil }
        coordinator.cancelAll()
        await waitUntil { !coordinator.isRunning }
        #expect(completions == 0)
        insert.finish(.cancelled)
        await waitUntil { completions == 1 }
        #expect(completions == 1)
    }

    @Test func hostGuardIsCheckedAgainAfterLoading() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        insert.pauseLoad = true
        let context = PresentationContext()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert, presentationAllowed: { context.allowed })
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        var completed = false
        coordinator.rewardDidDismiss(requestID: UUID()) { completed = true }
        await waitUntil { insert.loadContinuation != nil }
        context.allowed = false
        insert.finishLoad()
        await waitUntil { completed }
        #expect(insert.presentations == 0)
        #expect(completed)
    }

    @Test func rewardWithoutPageInsertNeverFallsBackToGeneralInsert() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(rewardInsertEnabled: false), canShowAds: true, privacyAllowsAds: true)
        var completions = 0
        coordinator.rewardDidDismiss(requestID: UUID()) { completions += 1 }
        #expect(completions == 1)
        #expect(insert.loads == 0)
        coordinator.guideDidDismiss()
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.presentations == 1)
        insert.finish(.closed)
    }

    @Test func pageRewardInsertDoesNotEnableMissingGeneralInsert() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(generalInsertIDPresent: false), canShowAds: true, privacyAllowsAds: true)
        coordinator.rewardDidDismiss(requestID: UUID())
        await waitUntil { insert.presentationContinuation != nil }
        insert.finish(.closed)
        await waitUntil { !coordinator.isRunning }
        coordinator.guideDidDismiss()
        #expect(insert.loads == 1)
        #expect(!coordinator.isRunning)
    }

    @Test func everyInsertFlowSelectsItsSlotAndRefreshDoesNotResetActiveFlow() async {
        let open = PresentationDriver(), insert = PresentationDriver()
        let coordinator = AdPresentationCoordinator(appOpen: open, interstitial: insert)
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        coordinator.rewardDidDismiss(requestID: UUID())
        await waitUntil { insert.presentationContinuation != nil }
        let rewardUpdates = insert.eligibilityIDs.count
        coordinator.synchronize(configuration: config(), canShowAds: true, privacyAllowsAds: true)
        #expect(insert.eligibilityIDs.count == rewardUpdates)
        insert.finish(.closed)
        await waitUntil { !coordinator.isRunning }
        coordinator.guideDidDismiss()
        await waitUntil { insert.presentationContinuation != nil }
        #expect(insert.eligibilityIDs.count == rewardUpdates + 1)
        #expect(insert.eligibilityIDs.last! == config().interstitialAdUnitID)
        insert.finish(.closed)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool,
                           sourceLocation: SourceLocation = #_sourceLocation) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "Timed out waiting for the required test event", sourceLocation: sourceLocation)
    }

    private func config(rewardInsertEnabled: Bool = true, generalInsertIDPresent: Bool = true) -> IAAPAdConfiguration {
        let appID = "ca-app-pub-1111111111111111~1111111111"
        let unit = "ca-app-pub-1111111111111111/1111111111"
        let page = IAAPConfiguration.Page(type: "limited", closeAlpha: nil, priceAlpha: nil,
            showGiveUp: false, iap: .init(pids: [], timeInterval: nil, hidePageControl: nil),
            reward: .init(rewardId: .init(oversea: unit),
                          insertId: .init(oversea: rewardInsertEnabled ? unit : nil), count: 1))
        var insert: [String: IAAPConfiguration.JSONValue] = ["enabled": .bool(true)]
        if generalInsertIDPresent { insert["oversea"] = .string(unit) }
        let raw = IAAPConfiguration(system: [:], ads: ["enabled": .bool(true), "admobAppId": .string(appID),
            "splash": .object(["enabled": .bool(true), "oversea": .string(unit)]),
            "reward": .object(["enabled": .bool(true), "oversea": .string(unit)]),
            "insert": .object(insert)], skus: [], iaaps: [page])
        return IAAPAdConfiguration(configuration: raw, expectedAppID: appID,
                                   expectedUnitIDs: ["splash": unit, "insert": unit, "reward": unit])
    }

}

@MainActor private final class PresentationDriver: FullScreenAdDriving {
    var loads = 0
    var loadReturns = 0
    var presentations = 0
    var pauseLoad = false
    var loadContinuation: CheckedContinuation<Void, Never>?
    var presentationContinuation: CheckedContinuation<FullScreenAdCompletion, Never>?
    var eligibilityIDs: [String?] = []
    func updateEligibility(adUnitID: String?, canShowAds: Bool) { eligibilityIDs.append(adUnitID) }
    func load() async {
        loads += 1
        if pauseLoad { await withCheckedContinuation { loadContinuation = $0 } }
        loadReturns += 1
    }
    func presentAndWait() async -> FullScreenAdCompletion {
        presentations += 1
        return await withCheckedContinuation { presentationContinuation = $0 }
    }
    func cancel() {}
    func finishLoad() { loadContinuation?.resume(); loadContinuation = nil }
    func finish(_ outcome: FullScreenAdCompletion) {
        presentationContinuation?.resume(returning: outcome)
        presentationContinuation = nil
    }
}

@MainActor private final class PresentationContext {
    var allowed = true
    var time = 0.0
}
