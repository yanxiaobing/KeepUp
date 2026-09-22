import Foundation
import Testing
@testable import KeepUp

@MainActor struct RewardedAdTests {
    private let placement = RewardedAdPlacement(providerID: "test", adUnitID: "test-only-unit", rewardRuleID: "test-only-rule")

    @Test func unconfiguredControllerCannotPresent() {
        let controller = RewardedAdController()
        controller.updateEligibility(placement: placement, canShowAds: true, privacyAllowsAds: true)
        #expect(!controller.present())
        #expect(controller.state == .disabled)
    }

    @Test func earnedCallbackGrantsOnceEvenBeforePresentationCallback() {
        let (controller, provider, ledger) = makeController()
        #expect(controller.present())
        provider.emit(.rewardEarned)
        provider.emit(.rewardEarned)
        provider.emit(.presented)
        #expect(controller.state == .rewarded)
        #expect(controller.isBusy)
        #expect(!controller.present())
        provider.emit(.closed)
        provider.emit(.rewardEarned)
        #expect(ledger.receipts.count == 1)
        #expect(!controller.isBusy)
        #expect(controller.state == .rewarded)
    }

    @Test func cancellationFailureAndNoFillNeverGrant() {
        for event in [RewardedAdEvent.closed, .failed, .unavailable] {
            let (controller, provider, ledger) = makeController()
            controller.present()
            provider.emit(event)
            provider.emit(.rewardEarned)
            provider.emit(event)
            #expect(ledger.receipts.isEmpty)
            #expect(!controller.isBusy)
            #expect(controller.state == (event == .closed ? .cancelled : event == .failed ? .failed : .unavailable))
        }
    }

    @Test func callbacksFromPreviousPresentationCannotRewardNextRequest() {
        let (controller, provider, ledger) = makeController()
        controller.present()
        let oldCallback = provider.callback
        controller.cancel()
        controller.present()
        oldCallback?(.rewardEarned)
        oldCallback?(.closed)
        #expect(ledger.receipts.isEmpty)
        #expect(controller.isBusy)
        provider.emit(.rewardEarned)
        provider.emit(.closed)
        #expect(ledger.receipts.count == 1)
    }

    @Test func membershipOrPrivacyRevocationCancelsAndIgnoresCallbacks() {
        for privacyRevoked in [false, true] {
            let (controller, provider, ledger) = makeController()
            controller.present()
            controller.updateEligibility(placement: placement, canShowAds: privacyRevoked,
                                         privacyAllowsAds: !privacyRevoked)
            provider.emit(.rewardEarned)
            #expect(ledger.receipts.isEmpty)
            #expect(provider.cancelled.count == 1)
            #expect(controller.state == .disabled)
            #expect(!controller.present())
        }
    }

    @Test func changingPlacementInvalidatesInflightCallbacks() {
        let (controller, provider, ledger) = makeController()
        controller.present()
        controller.updateEligibility(placement: nil, canShowAds: true, privacyAllowsAds: true)
        provider.emit(.rewardEarned)
        #expect(ledger.receipts.isEmpty)
        #expect(!controller.isEnabled)
    }

    @Test func grantFailureDoesNotRetryOnRepeatedCallback() {
        let (controller, provider, ledger) = makeController()
        ledger.shouldFail = true
        controller.present()
        provider.emit(.rewardEarned)
        provider.emit(.rewardEarned)
        provider.emit(.closed)
        #expect(ledger.calls == 1)
        #expect(ledger.receipts.isEmpty)
        #expect(controller.state == .failed)
    }

    @Test func successSurvivesSubsequentSdkFailureAndNewRequestIsIndependent() {
        let (controller, provider, ledger) = makeController()
        controller.present()
        provider.emit(.rewardEarned)
        provider.emit(.failed)
        #expect(controller.state == .rewarded)
        controller.present()
        provider.emit(.rewardEarned)
        provider.emit(.closed)
        #expect(ledger.receipts.count == 2)
        #expect(Set(ledger.receipts.map(\.requestID)).count == 2)
    }

    @Test func missingRuleOrWrongProviderDisablesAds() {
        let (controller, _, _) = makeController()
        for value in [RewardedAdPlacement(providerID: "test", adUnitID: "unit", rewardRuleID: " "),
                      RewardedAdPlacement(providerID: "other", adUnitID: "unit", rewardRuleID: "rule")] {
            controller.updateEligibility(placement: value, canShowAds: true, privacyAllowsAds: true)
            #expect(!controller.present())
        }
    }

    @Test func noCallbackTimeoutAllowsRetryAndStaleTimerDoesNotCancelNewAd() {
        let (controller, provider, ledger) = makeController()
        controller.present()
        let oldID = provider.requestID!
        controller.handleTimeout(requestID: oldID)
        #expect(controller.state == .failed)
        #expect(!controller.isBusy)
        provider.emit(.rewardEarned)
        #expect(ledger.receipts.isEmpty)
        #expect(controller.present())
        controller.handleTimeout(requestID: oldID)
        #expect(controller.isBusy)
        provider.emit(.rewardEarned)
        controller.handleTimeout(requestID: provider.requestID!)
        #expect(controller.state == .rewarded)
        #expect(ledger.receipts.count == 1)
        #expect(!controller.isBusy)
    }

    private func makeController() -> (RewardedAdController, TestProvider, TestLedger) {
        let provider = TestProvider()
        let ledger = TestLedger()
        let controller = RewardedAdController(provider: provider, ledger: ledger)
        controller.updateEligibility(placement: placement, canShowAds: true, privacyAllowsAds: true)
        return (controller, provider, ledger)
    }
}

@MainActor private final class TestProvider: RewardedAdProvider {
    let providerID = "test"
    var callback: (@MainActor (RewardedAdEvent) -> Void)?
    var cancelled: [UUID] = []
    var requestID: UUID?
    func present(placement: RewardedAdPlacement, requestID: UUID,
                 receive: @escaping @MainActor (RewardedAdEvent) -> Void) { callback = receive; self.requestID = requestID }
    func cancel(requestID: UUID) {
        cancelled.append(requestID)
        callback?(.rewardEarned) // Exercise a badly behaved/reentrant adapter.
    }
    func emit(_ event: RewardedAdEvent) { callback?(event) }
}

@MainActor private final class TestLedger: AdRewardLedger {
    enum Failure: Error { case rejected }
    var shouldFail = false
    var calls = 0
    var receipts: [AdRewardReceipt] = []
    func grantOnce(_ receipt: AdRewardReceipt) throws -> Bool {
        calls += 1
        if shouldFail { throw Failure.rejected }
        guard !receipts.contains(where: { $0.requestID == receipt.requestID }) else { return false }
        receipts.append(receipt)
        return true
    }
}
