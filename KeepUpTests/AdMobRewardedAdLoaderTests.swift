import Foundation
import Testing
import UIKit
@testable import KeepUp

@MainActor struct AdMobRewardedAdLoaderTests {
    @Test func preloadSharesRequestsAndCacheIsSingleUseAndExpires() async throws {
        let source = RewardLoaderFixture()
        var now = 0.0
        let loader = RewardedAdLoader(source: source, now: { now })
        let first = Task { try await loader.preload("one") }
        while source.waiting.isEmpty { await Task.yield() }
        let second = Task { try await loader.preload("one") }
        await Task.yield()
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        try await first.value; try await second.value
        #expect(source.calls == ["one"] && loader.isPrepared("one"))
        #expect(loader.take("one") != nil && loader.take("one") == nil)
        let next = Task { try await loader.preload("one") }
        while source.waiting.isEmpty { await Task.yield() }
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        try await next.value
        now = 3600
        #expect(!loader.isPrepared("one") && loader.take("one") == nil)
    }

    @Test func invalidatedLateLoadCannotFillCacheAndFailuresCanRetry() async throws {
        let source = RewardLoaderFixture(), loaderSource = RewardLoaderFixture()
        let loader = RewardedAdLoader(source: source)
        let old = Task { try await loader.preload("old") }
        while source.waiting.isEmpty { await Task.yield() }
        loader.invalidate()
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        do { try await old.value; Issue.record("Stale load accepted") } catch {}
        #expect(loader.take("old") == nil)
        let retryLoader = RewardedAdLoader(source: loaderSource)
        let failed = Task { try await retryLoader.preload("new") }
        while loaderSource.waiting.isEmpty { await Task.yield() }
        loaderSource.waiting.removeFirst().resume(throwing: RewardedAdLoadError.unavailable)
        do { try await failed.value; Issue.record("Expected no fill") } catch {}
        let retry = Task { try await retryLoader.preload("new") }
        while loaderSource.waiting.isEmpty { await Task.yield() }
        loaderSource.waiting.removeFirst().resume(returning: RewardAdFixture())
        try await retry.value
        #expect(loaderSource.calls.count == 2 && retryLoader.isPrepared("new"))
    }
    @Test func timeoutReleasesWaitersAndLateResultCannotPoisonRetry() async throws {
        let source = RewardLoaderFixture()
        let loader = RewardedAdLoader(source: source, timeout: .milliseconds(30))
        do { try await loader.preload("one"); Issue.record("Expected timeout") }
        catch { #expect((error as? URLError)?.code == .timedOut) }
        let retry = Task { try await loader.preload("one") }
        while source.calls.count < 2 { await Task.yield() }
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        for _ in 0..<10 { await Task.yield() }
        #expect(!loader.isPrepared("one"))
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        try await retry.value
        #expect(loader.isPrepared("one") && source.calls.count == 2)
    }

    @Test func cancelledLastWaiterDoesNotBlockNewRequest() async throws {
        let source = RewardLoaderFixture()
        let actual = RewardedAdLoader(source: source)
        let old = Task { try await actual.preload("one") }
        while source.waiting.isEmpty { await Task.yield() }
        old.cancel()
        do { try await old.value; Issue.record("Expected cancellation") } catch {}
        let retry = Task { try await actual.preload("one") }
        while source.calls.count < 2 { await Task.yield() }
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        try await retry.value
        #expect(actual.isPrepared("one"))
    }

    @Test func consumingCacheDoesNotChangeOtherWaitersSuccessfulResult() async throws {
        let source = RewardLoaderFixture()
        let actual = RewardedAdLoader(source: source)
        let consumer = Task { try await actual.preload("one"); return actual.take("one") != nil }
        while source.waiting.isEmpty { await Task.yield() }
        let observer = Task { try await actual.preload("one") }
        for _ in 0..<20 { await Task.yield() }
        source.waiting.removeFirst().resume(returning: RewardAdFixture())
        #expect(try await consumer.value)
        try await observer.value
        #expect(source.calls.count == 1)
    }

}

@MainActor private final class RewardLoaderFixture: RewardedAdLoading {
    var calls: [String] = []
    var waiting: [CheckedContinuation<any LoadedRewardedAd, Error>] = []
    func load(adUnitID: String) async throws -> any LoadedRewardedAd {
        calls.append(adUnitID)
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
}
@MainActor private final class RewardAdFixture: LoadedRewardedAd {
    func present(from presenter: UIViewController, receive: @escaping @MainActor (RewardedAdEvent) -> Void) {}
}
