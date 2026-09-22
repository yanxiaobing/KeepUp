import Foundation
import Observation
import UIKit

/// Shared SDK resources; page rewards are resolved from the existing IAAP entry.
@MainActor @Observable final class AppAdvertising {
    let consent: AdMobConsentManager
    let features: RewardedFeatureAccess
    let presentation: AdPresentationCoordinator
    private(set) var configuration: IAAPAdConfiguration = .disabled
    private(set) var membershipReady = false
    @ObservationIgnored private let membership: MembershipStore
    @ObservationIgnored private var consentAttempted = false

    init(membership: MembershipStore, receiptURL: URL? = nil) {
        self.membership = membership
        let consent = AdMobConsentManager()
        self.consent = consent
        let allowed = { @MainActor in
            consent.canRequestAds && membership.canShowAds && Defaults[.privacyAccepted]
        }
        let appOpen = AdMobFullScreenAdController(format: .appOpen, privacyAllowsAds: allowed)
        let interstitial = AdMobFullScreenAdController(format: .interstitial, privacyAllowsAds: allowed)
        presentation = AdPresentationCoordinator(appOpen: appOpen, interstitial: interstitial,
            presentationAllowed: Self.hasUnobstructedWindow)
        features = RewardedFeatureAccess(provider: AdMobRewardedAdProvider(privacyAllowsAds: allowed),
            receiptStore: receiptURL.map { JSONRewardReceiptStore(url: $0) })
    }

    func update(configuration: IAAPConfiguration) {
        let bundle = Bundle.main
        let mapped = IAAPAdConfiguration(configuration: configuration,
            expectedAppID: bundle.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
            expectedUnitIDs: ["splash": "KeepUpAdMobAppOpenAdUnitID", "insert": "KeepUpAdMobInterstitialAdUnitID", "reward": "KeepUpAdMobRewardedAdUnitID"]
                .compactMapValues { bundle.object(forInfoDictionaryKey: $0) as? String })
        if self.configuration != mapped {
            features.cancel()
            consentAttempted = false
        }
        self.configuration = mapped
        synchronize()
    }

    func finishedMembershipRefresh() { membershipReady = true; synchronize() }

    func synchronize() {
        let canShow = membershipReady && membership.canShowAds && Defaults[.privacyAccepted]
        let privacy = consent.canRequestAds
        presentation.synchronize(configuration: configuration, canShowAds: canShow, privacyAllowsAds: privacy)
        let placement = configuration.rewardedAdUnitID.map {
            RewardedAdPlacement(providerID: "admob", adUnitID: $0, rewardRuleID: "keepup.feature-once.v1")
        }
        if !canShow || !privacy || placement == nil { features.cancel() }
        features.controller.updateEligibility(placement: placement, canShowAds: canShow, privacyAllowsAds: privacy)
    }

    /// Called only at a visible, unobstructed app opportunity; disabled advertising stays inert.
    func prepareConsentIfNeeded() async {
        guard configuration.enabled, membershipReady, membership.canShowAds, Defaults[.privacyAccepted],
              hasConfiguredOpportunity,
              !consent.isPrepared, !consentAttempted, Self.hasUnobstructedWindow(),
              let presenter = AdMobRewardedAdProvider.activePresenter() else { synchronize(); return }
        consentAttempted = true
        do { try await consent.prepare(from: presenter) } catch { /* No consent means no ad request. */ }
        synchronize()
    }

    private var hasConfiguredOpportunity: Bool {
        configuration.appOpenAdUnitID != nil || configuration.interstitialAdUnitID != nil
            || configuration.rewardedAdUnitID != nil
    }

    func requiresReward(for _: RewardedFeatureAccess.FeatureID) -> Bool {
        membershipReady && membership.canShowAds && Defaults[.privacyAccepted] && consent.canRequestAds
            && features.controller.isEnabled
    }

    func didEnterBackground() {
        presentation.didEnterBackground()
        features.cancel()
    }

    static func hasUnobstructedWindow() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard scenes.count == 1, let window = scenes[0].windows.first(where: \.isKeyWindow),
              let root = window.rootViewController else { return false }
        return root.presentedViewController == nil && !root.isBeingDismissed && !root.isBeingPresented
    }
}
