import Foundation
import Testing
@testable import KeepUp

@MainActor struct AdMobRewardedAdProviderTests {
    @Test func missingAppConfigurationCannotStartSdkOrRequestAds() {
        var events: [RewardedAdEvent] = []
        let provider = AdMobRewardedAdProvider(appID: nil, privacyAllowsAds: { true }, presenter: { nil })
        provider.present(placement: placement, requestID: UUID()) { events.append($0) }
        #expect(events == [.unavailable])
    }

    @Test func privacyDenialStopsBeforeAccessingPresenter() {
        var events: [RewardedAdEvent] = []
        var didResolvePresenter = false
        let provider = AdMobRewardedAdProvider(appID: nil, privacyAllowsAds: { false }, presenter: {
            didResolvePresenter = true
            return nil
        })
        provider.present(placement: placement, requestID: UUID()) { events.append($0) }
        #expect(events == [.unavailable])
        #expect(!didResolvePresenter)
    }

    private var placement: RewardedAdPlacement {
        RewardedAdPlacement(providerID: "admob", adUnitID: "test-only-unit", rewardRuleID: "test-only-rule")
    }
}
