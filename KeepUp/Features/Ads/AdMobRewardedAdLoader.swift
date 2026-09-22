import GoogleMobileAds
import UIKit

@MainActor protocol LoadedRewardedAd: AnyObject, Sendable {
    func present(from presenter: UIViewController, receive: @escaping @MainActor (RewardedAdEvent) -> Void)
}

@MainActor protocol RewardedAdLoading: AnyObject {
    func load(adUnitID: String) async throws -> any LoadedRewardedAd
}

enum RewardedAdLoadError: Error { case unavailable }

/// Reference RewardGadService's slot map and loader lifetime, adapted to async callers.
/// Loading does not present. Cached ads are single-use and expire after one hour.
@MainActor final class RewardedAdLoader {
    private struct Pending {
        let id: UUID
        let work: Task<Void, Never>
        let deadline: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Void, Error>]
    }
    private let source: any RewardedAdLoading
    private let now: () -> TimeInterval
    private let timeout: Duration
    private var cache: [String: (ad: any LoadedRewardedAd, date: TimeInterval)] = [:]
    private var pending: [String: Pending] = [:]

    init(source: any RewardedAdLoading, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         timeout: Duration = .seconds(120)) {
        self.source = source
        self.now = now
        self.timeout = timeout
    }

    func isPrepared(_ id: String) -> Bool {
        guard let value = cache[id] else { return false }
        let age = now() - value.date
        return age >= 0 && age < 3600
    }

    func preload(_ id: String) async throws {
        try Task.checkCancellation()
        if isPrepared(id) { return }
        let waiter = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if pending[id] != nil {
                    pending[id]?.waiters[waiter] = continuation
                    return
                }
                cache[id] = nil
                let token = UUID()
                let work = Task { [weak self, source] in
                    do {
                        let ad = try await source.load(adUnitID: id)
                        self?.resolve(id, token: token, result: .success(ad))
                    } catch { self?.resolve(id, token: token, result: .failure(error)) }
                }
                let deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.resolve(id, token: token, result: .failure(URLError(.timedOut)))
                }
                pending[id] = Pending(id: token, work: work, deadline: deadline, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id, waiter: waiter) }
        }
    }

    private func resolve(_ id: String, token: UUID, result: Result<any LoadedRewardedAd, Error>) {
        guard let load = pending[id], load.id == token else { return }
        pending[id] = nil
        load.work.cancel()
        load.deadline.cancel()
        if case .success(let ad) = result { cache[id] = (ad, now()) }
        for continuation in load.waiters.values {
            // Completion belongs to the load generation, not to a cache another waiter may consume.
            continuation.resume(with: result.map { _ in () })
        }
    }

    private func cancelWaiter(_ id: String, waiter: UUID) {
        guard let continuation = pending[id]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if let load = pending[id], load.waiters.isEmpty {
            resolve(id, token: load.id, result: .failure(CancellationError()))
        }
    }

    func take(_ id: String) -> (any LoadedRewardedAd)? {
        guard isPrepared(id) else { cache[id] = nil; return nil }
        return cache.removeValue(forKey: id)?.ad
    }

    func invalidate() {
        for (id, load) in Array(pending) {
            resolve(id, token: load.id, result: .failure(CancellationError()))
        }
        cache.removeAll()
    }
}

@MainActor final class AdMobRewardedAdLoader: RewardedAdLoading {
    func load(adUnitID: String) async throws -> any LoadedRewardedAd {
        guard AdMobRuntime.isConfigured else { throw RewardedAdLoadError.unavailable }
        await AdMobRuntime.initializeIfNeeded()
        try Task.checkCancellation()
        do { return AdMobLoadedRewardedAd(try await RewardedAd.load(with: AdMobAdUnit.resolve(adUnitID, format: .rewarded), request: Request())) }
        catch {
            let error = error as NSError
            if error.domain == GADErrorDomain && error.code == RequestError.Code.noFill.rawValue {
                throw RewardedAdLoadError.unavailable
            }
            throw error
        }
    }
}

@MainActor private final class AdMobLoadedRewardedAd: NSObject, LoadedRewardedAd, FullScreenContentDelegate {
    private let ad: RewardedAd
    private var callback: (@MainActor (RewardedAdEvent) -> Void)?
    private var didPresent = false
    init(_ ad: RewardedAd) { self.ad = ad }
    func present(from presenter: UIViewController, receive: @escaping @MainActor (RewardedAdEvent) -> Void) {
        guard !didPresent else { receive(.failed); return }
        didPresent = true
        callback = receive
        ad.fullScreenContentDelegate = self
        ad.present(from: presenter) { [weak self] in self?.callback?(.rewardEarned) }
    }
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) { callback?(.presented) }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) { finish(.closed) }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish(.failed) }
    private func finish(_ event: RewardedAdEvent) {
        let callback = callback
        self.callback = nil
        ad.fullScreenContentDelegate = nil
        callback?(event)
    }
}
