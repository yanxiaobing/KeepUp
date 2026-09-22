import Foundation
import Testing
import UIKit
@testable import KeepUp

@MainActor struct FullScreenAdTests {
    @Test func disabledDoesNotLoadOrPresent() async {
        let loader = TestFullScreenLoader()
        let controller = make(loader: loader)
        await controller.load()
        #expect(loader.calls == 0)
        #expect(!controller.present())
    }

    @Test func explicitLoadNeverAutomaticallyPresents() async {
        let loader = TestFullScreenLoader()
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        await controller.load()
        #expect(controller.state == .ready)
        #expect(loader.ad.presentCount == 0)
        #expect(controller.present())
        loader.ad.emit(.presented)
        loader.ad.emit(.closed)
        loader.ad.emit(.failed)
        #expect(controller.state == .closed)
    }

    @Test func appOpenCacheExpiresAtFourHoursAndClockRollback() async {
        for age in [14400.0, -1] {
            let loader = TestFullScreenLoader()
            var now = 100.0
            let controller = make(loader: loader, now: { now })
            controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
            await controller.load()
            now += age
            #expect(!controller.present())
            #expect(controller.state == .expired)
            #expect(loader.ad.presentCount == 0)
        }
    }

    @Test func interstitialCacheExpiresAtOneHour() async {
        let loader = TestFullScreenLoader()
        var now = 0.0
        let controller = make(loader: loader, format: .interstitial, now: { now })
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        await controller.load()
        now = 3600
        #expect(!controller.present())
        #expect(controller.state == .expired)
    }

    @Test func formatsShareGateAndCancelledVisibleAdRetainsLease() async {
        let gate = FullScreenAdGate()
        let firstLoader = TestFullScreenLoader()
        let secondLoader = TestFullScreenLoader()
        let first = make(loader: firstLoader, gate: gate)
        let second = make(loader: secondLoader, format: .interstitial, gate: gate)
        first.updateEligibility(adUnitID: "open", canShowAds: true)
        second.updateEligibility(adUnitID: "interstitial", canShowAds: true)
        await first.load()
        await second.load()
        #expect(first.present())
        first.cancel()
        #expect(!second.present())
        #expect(second.state == .busy)
        firstLoader.ad.emit(.presented)
        #expect(first.state == .cancelled)
        firstLoader.ad.emit(.closed)
        #expect(second.present())
        let lease = gate.owner
        firstLoader.ad.emit(.closed)
        #expect(gate.owner == lease)
        secondLoader.ad.emit(.failed)
        #expect(gate.owner == nil)
        #expect(second.state == .failed)
    }

    @Test func revokedEligibilityDropsLoadedAd() async {
        let loader = TestFullScreenLoader()
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        await controller.load()
        controller.updateEligibility(adUnitID: "test-only", canShowAds: false)
        #expect(!controller.present())
        #expect(loader.ad.presentCount == 0)
    }

    @Test func noFillAndFailureAreDistinct() async {
        for noFill in [true, false] {
            let loader = TestFullScreenLoader()
            loader.failure = noFill ? FullScreenAdLoadError.unavailable : TestFullScreenLoader.Failure.failed
            let controller = make(loader: loader)
            controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
            await controller.load()
            #expect(controller.state == (noFill ? .unavailable : .failed))
        }
    }

    @Test func cancelledLoadIgnoresLateResultAndCanRetry() async {
        let loader = TestFullScreenLoader()
        loader.pause = true
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        let task = Task { await controller.load() }
        while loader.continuation == nil { await Task.yield() }
        controller.cancel()
        loader.continuation?.resume()
        await task.value
        #expect(controller.state == .cancelled)
        #expect(!controller.present())
        loader.pause = false
        await controller.load()
        #expect(controller.state == .ready)
    }

    @Test func rewardPresentationLeaseBlocksOtherFormatsAndStaleReleaseIsIgnored() async {
        let gate = FullScreenAdGate()
        let rewardToken = UUID()
        #expect(gate.acquire(rewardToken))
        let loader = TestFullScreenLoader()
        let controller = make(loader: loader, gate: gate)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        await controller.load()
        #expect(!controller.present())
        gate.release(UUID())
        #expect(!controller.present())
        gate.release(rewardToken)
        #expect(controller.present())
        loader.ad.emit(.closed)
    }

    @Test func privacyRevocationDuringInitializationCancelsBeforeNetworkRequest() async {
        let loader = TestFullScreenLoader()
        loader.pause = true
        loader.checkCancellationBeforeRequest = true
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        let task = Task { await controller.load() }
        while loader.continuation == nil { await Task.yield() }
        controller.updateEligibility(adUnitID: "test-only", canShowAds: false)
        loader.continuation?.resume()
        await task.value
        #expect(loader.networkRequests == 0)
        #expect(controller.state == .disabled)
    }

    @Test func loadingTimeoutInvalidatesLateResultAndAllowsRetry() async {
        let loader = TestFullScreenLoader()
        loader.pause = true
        let controller = AdMobFullScreenAdController(format: .appOpen, loader: loader,
            gate: FullScreenAdGate(), privacyAllowsAds: { true }, presenter: { UIViewController() },
            canPresent: { _ in true }, loadTimeout: .milliseconds(10))
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        let task = Task { await controller.load() }
        while loader.continuation == nil { await Task.yield() }
        while controller.state == .loading { await Task.yield() }
        #expect(controller.state == .failed)
        loader.continuation?.resume()
        await task.value
        #expect(controller.state == .failed)
        loader.pause = false
        await controller.load()
        #expect(controller.state == .ready)
    }

    @Test func cancellingCallerCancelsChildRequestAndReportsCancelled() async {
        let loader = TestFullScreenLoader()
        loader.pause = true
        loader.checkCancellationBeforeRequest = true
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        let task = Task { await controller.load() }
        while loader.continuation == nil { await Task.yield() }
        task.cancel()
        loader.continuation?.resume()
        await task.value
        #expect(loader.networkRequests == 0)
        #expect(controller.state == .cancelled)
    }

    @Test func awaitedPresentationCompletesOnlyAfterSdkClosesEvenWhenCancelled() async {
        let loader = TestFullScreenLoader()
        let controller = make(loader: loader)
        controller.updateEligibility(adUnitID: "test-only", canShowAds: true)
        await controller.load()
        var outcome: FullScreenAdCompletion?
        let task = Task { outcome = await controller.presentAndWait() }
        while loader.ad.presentCount == 0 { await Task.yield() }
        controller.cancel()
        for _ in 0..<10 { await Task.yield() }
        #expect(outcome == nil)
        loader.ad.emit(.closed)
        await task.value
        #expect(outcome == .cancelled)
        loader.ad.emit(.failed)
        #expect(outcome == .cancelled)
    }

    @Test func awaitedDisabledPresentationReturnsWithoutSdkCallback() async {
        let controller = make(loader: TestFullScreenLoader())
        #expect(await controller.presentAndWait() == .notPresented)
    }

    private func make(loader: TestFullScreenLoader, format: AdMobFullScreenFormat = .appOpen,
                      gate: FullScreenAdGate? = nil, now: @escaping () -> TimeInterval = { 0 }) -> AdMobFullScreenAdController {
        AdMobFullScreenAdController(format: format, loader: loader, gate: gate ?? FullScreenAdGate(),
                                   now: now, privacyAllowsAds: { true }, presenter: { UIViewController() },
                                   canPresent: { _ in true })
    }
}

@MainActor private final class TestFullScreenLoader: FullScreenAdLoading {
    enum Failure: Error { case failed }
    let ad = TestLoadedFullScreenAd()
    var calls = 0
    var failure: Error?
    var pause = false
    var checkCancellationBeforeRequest = false
    var networkRequests = 0
    var continuation: CheckedContinuation<Void, Never>?
    func load(format: AdMobFullScreenFormat, adUnitID: String) async throws -> any LoadedFullScreenAd {
        calls += 1
        if pause { await withCheckedContinuation { continuation = $0 } }
        if checkCancellationBeforeRequest { try Task.checkCancellation() }
        networkRequests += 1
        if let failure { throw failure }
        return ad
    }
}

@MainActor private final class TestLoadedFullScreenAd: LoadedFullScreenAd {
    var presentCount = 0
    var callback: (@MainActor (FullScreenAdEvent) -> Void)?
    func present(from presenter: UIViewController, receive: @escaping @MainActor (FullScreenAdEvent) -> Void) {
        presentCount += 1
        callback = receive
    }
    func emit(_ event: FullScreenAdEvent) { callback?(event) }
}
