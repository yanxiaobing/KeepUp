import Foundation
import Observation
import UIKit

/// No lifecycle hooks or frequency policy: all load/present operations are explicit.
enum AdMobFullScreenFormat: Sendable {
    case appOpen, interstitial
    // SDK cache validity, not a business frequency rule.
    var maximumCacheAge: TimeInterval { self == .appOpen ? 4 * 3600 : 3600 }
}

enum FullScreenAdCompletion: Equatable, Sendable { case closed, failed, notPresented, cancelled }

@MainActor protocol FullScreenAdDriving: AnyObject {
    func updateEligibility(adUnitID: String?, canShowAds: Bool)
    func load() async
    func presentAndWait() async -> FullScreenAdCompletion
    func cancel()
}

enum FullScreenAdEvent { case presented, closed, failed }
enum FullScreenAdLoadError: Error { case unavailable }

@MainActor protocol LoadedFullScreenAd: AnyObject, Sendable {
    func present(from presenter: UIViewController, receive: @escaping @MainActor (FullScreenAdEvent) -> Void)
}

@MainActor protocol FullScreenAdLoading: AnyObject {
    func load(format: AdMobFullScreenFormat, adUnitID: String) async throws -> any LoadedFullScreenAd
}

@MainActor @Observable final class AdMobFullScreenAdController: FullScreenAdDriving {
    enum State: Equatable { case disabled, idle, loading, ready, presenting, closed, cancelled, failed, unavailable, expired, busy }
    private(set) var state: State = .disabled
    private(set) var isEnabled = false
    private let format: AdMobFullScreenFormat
    @ObservationIgnored private let loader: any FullScreenAdLoading
    @ObservationIgnored private let gate: FullScreenAdGate
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let presenter: @MainActor () -> UIViewController?
    @ObservationIgnored private let canPresent: @MainActor (UIViewController) -> Bool
    @ObservationIgnored private let privacyAllowsAds: @MainActor () -> Bool
    @ObservationIgnored private var adUnitID: String?
    @ObservationIgnored private var cached: (ad: any LoadedFullScreenAd, time: TimeInterval)?
    @ObservationIgnored private var displayed: (ad: any LoadedFullScreenAd, token: UUID)?
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var loadingTask: Task<any LoadedFullScreenAd, Error>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var completion: CheckedContinuation<FullScreenAdCompletion, Never>?
    @ObservationIgnored private var presentationCancelled = false
    @ObservationIgnored private let loadTimeout: Duration

    init(format: AdMobFullScreenFormat, loader: (any FullScreenAdLoading)? = nil,
         gate: FullScreenAdGate? = nil, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         privacyAllowsAds: @escaping @MainActor () -> Bool,
         presenter: @escaping @MainActor () -> UIViewController? = AdMobRewardedAdProvider.activePresenter,
         canPresent: @escaping @MainActor (UIViewController) -> Bool = {
             $0.viewIfLoaded?.window != nil && !$0.isBeingDismissed && !$0.isBeingPresented
         }, loadTimeout: Duration = .seconds(120)) {
        self.format = format
        self.loader = loader ?? AdMobFullScreenAdLoader()
        self.gate = gate ?? .shared
        self.now = now
        self.privacyAllowsAds = privacyAllowsAds
        self.presenter = presenter
        self.canPresent = canPresent
        self.loadTimeout = loadTimeout
    }

    func updateEligibility(adUnitID: String?, canShowAds: Bool) {
        let value = adUnitID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = canShowAds && privacyAllowsAds() && value?.isEmpty == false
        if self.adUnitID != value || !enabled { cancel() }
        self.adUnitID = value
        isEnabled = enabled
        if !enabled { state = .disabled }
        else if displayed == nil && loadID == nil { state = cached == nil ? .idle : .ready }
    }

    func load() async {
        guard isEnabled, privacyAllowsAds(), let adUnitID else { state = .disabled; return }
        guard loadID == nil, displayed == nil else { return }
        if hasValidCache { state = .ready; return }
        cached = nil
        let token = UUID()
        loadID = token
        state = .loading
        timeoutTask = Task { [weak self, loadTimeout] in
            do { try await Task.sleep(for: loadTimeout) } catch { return }
            self?.handleLoadTimeout(token: token)
        }
        do {
            let task = Task { [loader, format] in try await loader.load(format: format, adUnitID: adUnitID) }
            loadingTask = task
            let ad = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard loadID == token else { return }
            stopLoading()
            guard isEnabled, privacyAllowsAds(), !Task.isCancelled else { state = .cancelled; return }
            cached = (ad, now())
            state = .ready
        } catch {
            guard loadID == token else { return }
            stopLoading()
            state = error is CancellationError || Task.isCancelled ? .cancelled
                : error is FullScreenAdLoadError ? .unavailable : .failed
        }
    }

    @discardableResult func present() -> Bool {
        guard isEnabled, privacyAllowsAds() else { cancel(); state = .disabled; return false }
        guard displayed == nil else { return false }
        guard let cached else { state = .unavailable; return false }
        guard hasValidCache else { self.cached = nil; state = .expired; return false }
        guard let presenter = presenter(), canPresent(presenter) else { state = .unavailable; return false }
        let token = UUID()
        guard gate.acquire(token) else { state = .busy; return false }
        self.cached = nil
        displayed = (cached.ad, token)
        state = .presenting
        cached.ad.present(from: presenter) { [weak self] event in
            self?.receive(event, token: token)
        }
        return true
    }

    /// Completes only on a real SDK terminal callback when an ad was presented.
    /// Cancellation invalidates its outcome but does not pretend a visible ad dismissed.
    func presentAndWait() async -> FullScreenAdCompletion {
        guard completion == nil, displayed == nil, !Task.isCancelled else { return .notPresented }
        return await withCheckedContinuation { continuation in
            completion = continuation
            presentationCancelled = false
            if !present() {
                completion = nil
                continuation.resume(returning: .notPresented)
            }
        }
    }

    func cancel() {
        if displayed != nil { presentationCancelled = true }
        stopLoading()
        cached = nil
        // Retain the visible ad and lease until its SDK terminal event.
        state = .cancelled
    }

    private var hasValidCache: Bool {
        guard let cached else { return false }
        let age = now() - cached.time
        return age >= 0 && age < format.maximumCacheAge
    }

    func handleLoadTimeout(token: UUID) {
        guard loadID == token else { return }
        stopLoading()
        state = .failed
    }

    private func stopLoading() {
        loadID = nil
        loadingTask?.cancel()
        loadingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func receive(_ event: FullScreenAdEvent, token: UUID) {
        guard displayed?.token == token else { return }
        switch event {
        case .presented:
            break // A cancelled/disabled visible ad must not reactivate eligibility.
        case .closed, .failed:
            displayed = nil
            gate.release(token)
            let outcome: FullScreenAdCompletion = presentationCancelled ? .cancelled : event == .closed ? .closed : .failed
            let continuation = completion
            completion = nil
            presentationCancelled = false
            continuation?.resume(returning: outcome)
            if state != .cancelled && state != .disabled { state = event == .closed ? .closed : .failed }
        }
    }
}
