import Foundation
import Observation

/// Business opportunities are explicit. Configuration gates, membership and UMP must
/// all agree; lifecycle positions are client-owned and remote slots only enable resources.
@MainActor @Observable final class AdPresentationCoordinator {
    private(set) var launchMembershipRequestID: UUID?
    private(set) var isRunning = false
    @ObservationIgnored private let appOpen: any FullScreenAdDriving
    @ObservationIgnored private let interstitial: any FullScreenAdDriving
    @ObservationIgnored private let presentationAllowed: @MainActor () -> Bool
    @ObservationIgnored private let coldLoadTimeout: Duration
    @ObservationIgnored private let loadTimeout: Duration
    @ObservationIgnored private var pendingLoad: PendingLoad?
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private var configuration: IAAPAdConfiguration?
    @ObservationIgnored private var eligible = false
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var backgroundTime: TimeInterval?
    @ObservationIgnored private var coldStartConsumed = false
    @ObservationIgnored private var launchMembershipRequested = false
    @ObservationIgnored private var coldOpportunityValid = true
    @ObservationIgnored private var guideDismissed = false
    @ObservationIgnored private var handledRewards = Set<UUID>()
    @ObservationIgnored private var flowID: UUID?
    @ObservationIgnored private var flowTask: Task<Void, Never>?

    init(appOpen: any FullScreenAdDriving, interstitial: any FullScreenAdDriving,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         presentationAllowed: @escaping @MainActor () -> Bool = { true },
         coldLoadTimeout: Duration = .seconds(3), loadTimeout: Duration = .seconds(3)) {
        self.appOpen = appOpen
        self.interstitial = interstitial
        self.now = now
        self.presentationAllowed = presentationAllowed
        self.coldLoadTimeout = coldLoadTimeout
        self.loadTimeout = loadTimeout
    }

    func synchronize(configuration: IAAPAdConfiguration, canShowAds: Bool, privacyAllowsAds: Bool) {
        let allowed = configuration.enabled && canShowAds && privacyAllowsAds
        // Replacing slots invalidates queued opportunities from the old config.
        let changed = self.configuration != configuration
        if changed || !allowed { cancelFlow(preserveMembership: true) }
        self.configuration = configuration
        eligible = allowed
        appOpen.updateEligibility(adUnitID: configuration.appOpenAdUnitID, canShowAds: allowed)
        // A routine refresh must not overwrite a page-specific reward interstitial
        // while it is loading or visible. Each new flow sets its own exact slot.
        if changed || !allowed || !isRunning {
            interstitial.updateEligibility(adUnitID: configuration.interstitialAdUnitID, canShowAds: allowed)
        }
    }

    func coldStart(isExistingUser: Bool) {
        guard !coldStartConsumed else { return }
        coldStartConsumed = true
        guard isExistingUser, coldOpportunityValid, configuration?.appOpenAdUnitID != nil else { return }
        start(cold: true) { coordinator, token in
            guard await coordinator.loadBounded(coordinator.appOpen, token: token,
                                                timeout: coordinator.coldLoadTimeout) else { return }
            guard coordinator.isCurrent(token), coordinator.coldOpportunityValid, coordinator.presentationAllowed() else { return }
            let outcome = await coordinator.appOpen.presentAndWait()
            guard coordinator.isCurrent(token), outcome == .closed else { return }
            coordinator.requestLaunchMembership()
        }
    }

    /// Membership eligibility belongs to the host and does not require an ad or UMP consent.
    func requestLaunchMembership() {
        guard coldStartConsumed, coldOpportunityValid, isForeground, !launchMembershipRequested else { return }
        launchMembershipRequested = true
        launchMembershipRequestID = UUID()
    }

    /// Host calls this before releasing its launch/loading gate to main content.
    /// Never present an ad that finished loading after this launch opportunity ended.
    func invalidateColdStartOpportunity() {
        coldOpportunityValid = false
        // Only cold-start work needs invalidation; a visible ad retains its SDK lock.
        if coldFlowActive { cancelFlow() }
    }

    @ObservationIgnored private var coldFlowActive = false

    func didEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        backgroundTime = now()
        coldOpportunityValid = false
        cancelFlow(preserveMembership: true)
    }

    /// Read before consuming foreground activation. This intentionally does not require
    /// consent eligibility, so the host can prepare UMP for a real hot-start opportunity.
    var hasHotStartOpportunity: Bool {
        guard !isForeground, let backgroundTime, configuration?.enabled == true,
              configuration?.appOpenAdUnitID != nil else { return false }
        return now() - backgroundTime >= 30
    }

    func didBecomeActive() {
        guard !isForeground else { return } // First launch active is never a hot start.
        let shouldShow = hasHotStartOpportunity
        isForeground = true
        backgroundTime = nil
        guard shouldShow else { return }
        start { coordinator, token in
            guard await coordinator.loadBounded(coordinator.appOpen, token: token, timeout: coordinator.loadTimeout) else { return }
            guard coordinator.isCurrent(token), coordinator.presentationAllowed() else { return }
            let outcome = await coordinator.appOpen.presentAndWait()
            guard coordinator.isCurrent(token), outcome == .closed,
                  coordinator.configuration?.interstitialAdUnitID != nil else { return }
            await coordinator.showInterstitial(token: token, adUnitID: coordinator.configuration?.interstitialAdUnitID)
        }
    }

    func guideDidDismiss() {
        guard !guideDismissed else { return }
        guideDismissed = true
        guard configuration?.interstitialAdUnitID != nil else { return }
        start { coordinator, token in await coordinator.showInterstitial(token: token, adUnitID: coordinator.configuration?.interstitialAdUnitID) }
    }

    func launchMembershipDidDismiss(requestID: UUID) {
        guard launchMembershipRequestID == requestID else { return }
        launchMembershipRequestID = nil
        guard configuration?.interstitialAdUnitID != nil else { return }
        start { coordinator, token in await coordinator.showInterstitial(token: token, adUnitID: coordinator.configuration?.interstitialAdUnitID) }
    }

    /// This means the reward SDK's full screen CLOSED, not its earned callback.
    func rewardDidDismiss(requestID: UUID, completion: @escaping @MainActor () -> Void = {}) {
        guard handledRewards.insert(requestID).inserted else { return }
        guard configuration?.rewardInterstitialAdUnitID != nil else { completion(); return }
        start(completion: completion) { coordinator, token in
            await coordinator.showInterstitial(token: token, adUnitID: coordinator.configuration?.rewardInterstitialAdUnitID)
        }
    }

    private func start(cold: Bool = false, completion: @escaping @MainActor () -> Void = {}, _ action: @escaping @MainActor (AdPresentationCoordinator, UUID) async -> Void) {
        guard eligible, isForeground, !isRunning, launchMembershipRequestID == nil, presentationAllowed() else { completion(); return }
        let token = UUID()
        flowID = token
        isRunning = true
        coldFlowActive = cold
        flowTask = Task { [weak self] in
            guard let self else { return }
            await action(self, token)
            if self.flowID == token {
                self.flowID = nil
                self.flowTask = nil
                self.isRunning = false
                self.coldFlowActive = false
            }
            completion()
        }
    }

    private func showInterstitial(token: UUID, adUnitID: String?) async {
        guard isCurrent(token), let adUnitID else { return }
        interstitial.updateEligibility(adUnitID: adUnitID, canShowAds: eligible)
        guard await loadBounded(interstitial, token: token, timeout: loadTimeout) else { return }
        guard isCurrent(token), presentationAllowed() else { return }
        _ = await interstitial.presentAndWait()
    }

    /// Does not await a cancelled SDK request's eventual callback. The request keeps
    /// its own resources until the SDK returns, while the host continuation is released.
    private func loadBounded(_ driver: any FullScreenAdDriving, token: UUID, timeout: Duration) async -> Bool {
        guard isCurrent(token), presentationAllowed() else { return false }
        let loadID = UUID()
        return await withCheckedContinuation { continuation in
            let work = Task { [weak self] in
                guard self?.flowID == token, !Task.isCancelled else { return }
                await driver.load()
                self?.resolveLoad(loadID, success: true)
            }
            let deadline = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                guard let self, self.pendingLoad?.id == loadID else { return }
                driver.cancel()
                self.resolveLoad(loadID, success: false)
            }
            pendingLoad = PendingLoad(id: loadID, continuation: continuation, work: work, deadline: deadline)
        }
    }

    private func resolveLoad(_ id: UUID, success: Bool) {
        guard let load = pendingLoad, load.id == id else { return }
        pendingLoad = nil
        load.work.cancel()
        load.deadline.cancel()
        load.continuation.resume(returning: success)
    }

    private struct PendingLoad {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        let work: Task<Void, Never>
        let deadline: Task<Void, Never>
    }

    private func isCurrent(_ token: UUID) -> Bool {
        flowID == token && eligible && isForeground && !Task.isCancelled
    }

    func cancelAll() { cancelFlow() }

    private func cancelFlow(preserveMembership: Bool = false) {
        flowID = nil
        if let pendingLoad { resolveLoad(pendingLoad.id, success: false) }
        flowTask?.cancel()
        flowTask = nil
        appOpen.cancel()
        interstitial.cancel()
        isRunning = false
        coldFlowActive = false
        if !preserveMembership { launchMembershipRequestID = nil }
    }
}
