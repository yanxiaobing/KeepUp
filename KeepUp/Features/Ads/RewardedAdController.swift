import Foundation
import Observation

/// These values must come from verified KeepUp resources and an approved reward rule.
struct RewardedAdPlacement: Equatable, Sendable {
    let providerID: String
    let adUnitID: String
    let rewardRuleID: String

    var isConfigured: Bool {
        [providerID, adUnitID, rewardRuleID].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct AdRewardReceipt: Equatable, Sendable {
    let requestID: UUID
    let placement: RewardedAdPlacement
}

enum RewardedAdEvent: Equatable {
    case presented
    case rewardEarned
    case closed
    case failed
    case unavailable
}

/// Adapters must forward the SDK's earned callback, never infer it from dismissal.
/// `closed` means the SDK reward decision is FINAL, not merely that its view dismissed.
/// For mediated SDKs which reward after dismissal, retain the session until that decision
/// and forward earned before closed. All callbacks use MainActor.
@MainActor protocol RewardedAdProvider: AnyObject {
    var providerID: String { get }
    func present(placement: RewardedAdPlacement, requestID: UUID,
                 receive: @escaping @MainActor (RewardedAdEvent) -> Void)
    func cancel(requestID: UUID)
    func preload(placement: RewardedAdPlacement) async -> Bool
    func invalidateCache()
}

extension RewardedAdProvider {
    // Lazy/test providers can continue through present; SDK providers override with real readiness.
    func preload(placement: RewardedAdPlacement) async -> Bool { true }
    func invalidateCache() {}
}

/// Implementations must atomically persist the receipt ID and apply its approved reward
/// in the same transaction. Return false for a receipt already applied; throw without
/// changing either value on failure. An SDK adapter must never grant rewards directly.
@MainActor protocol AdRewardLedger: AnyObject {
    @discardableResult func grantOnce(_ receipt: AdRewardReceipt) throws -> Bool
}

@MainActor final class DisabledRewardedAdProvider: RewardedAdProvider {
    let providerID = "disabled"
    func present(placement: RewardedAdPlacement, requestID: UUID,
                 receive: @escaping @MainActor (RewardedAdEvent) -> Void) {
        receive(.unavailable)
    }
    func cancel(requestID: UUID) {}
}

@MainActor final class DisabledAdRewardLedger: AdRewardLedger {
    enum Unconfigured: Error { case rewardRule }
    func grantOnce(_ receipt: AdRewardReceipt) throws -> Bool { throw Unconfigured.rewardRule }
}

/// A single coordinator should be shared by all reward entry points.
/// The default instance cannot load ads or issue rewards until explicitly configured.
@MainActor @Observable final class RewardedAdController {
    enum Completion: Equatable {
        case closed(rewardGranted: Bool), cancelled, failed, unavailable
    }
    enum State: Equatable {
        case idle, disabled, loading, presenting, rewarded, cancelled, failed, unavailable
    }

    private(set) var state: State = .disabled
    private(set) var isBusy = false
    private(set) var isEnabled = false
    @ObservationIgnored private let provider: any RewardedAdProvider
    @ObservationIgnored private let ledger: any AdRewardLedger
    @ObservationIgnored private var placement: RewardedAdPlacement?
    @ObservationIgnored private var activeRequest: UUID?
    @ObservationIgnored private var completion: (@MainActor (Completion) -> Void)?
    @ObservationIgnored private var earned = false
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private let timeout: Duration

    convenience init() {
        self.init(provider: DisabledRewardedAdProvider(), ledger: DisabledAdRewardLedger())
    }

    init(provider: any RewardedAdProvider, ledger: any AdRewardLedger,
         timeout: Duration = .seconds(120)) {
        self.provider = provider
        self.ledger = ledger
        self.timeout = timeout
    }

    /// Call on membership/privacy/configuration changes. Revocation cancels in-flight
    /// presentation and makes its subsequent callbacks inert.
    func updateEligibility(placement: RewardedAdPlacement?, canShowAds: Bool,
                           privacyAllowsAds: Bool) {
        let enabled = canShowAds && privacyAllowsAds && placement?.isConfigured == true
            && placement?.providerID == provider.providerID && provider.providerID != "disabled"
        let invalidate = self.placement != placement || !enabled
        // Publish new eligibility before cancellation callbacks can request another ad.
        self.placement = placement
        isEnabled = enabled
        if invalidate { cancel(); provider.invalidateCache() }
        if !isBusy { state = enabled ? .idle : .disabled }
    }

    func preload() async -> Bool {
        guard isEnabled, let placement else { return false }
        let ready = await provider.preload(placement: placement)
        return ready && isEnabled && self.placement == placement && !Task.isCancelled
    }

    @discardableResult func present(completion: (@MainActor (Completion) -> Void)? = nil) -> Bool {
        guard !isBusy else { return false }
        guard isEnabled, let placement else {
            state = .disabled
            return false
        }
        let requestID = UUID()
        activeRequest = requestID
        self.completion = completion
        earned = false
        isBusy = true
        state = .loading
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.handleTimeout(requestID: requestID)
        }
        provider.present(placement: placement, requestID: requestID) { [weak self] event in
            self?.receive(event, requestID: requestID, placement: placement)
        }
        return true
    }

    func cancel() {
        guard let requestID = activeRequest else { return }
        // Invalidate before calling the adapter: cancel can itself synchronously callback.
        activeRequest = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isBusy = false
        state = earned ? .rewarded : .cancelled
        provider.cancel(requestID: requestID)
        complete(.cancelled)
    }

    /// Separate from the clock so stale timers and no-callback failures are deterministic in tests.
    func handleTimeout(requestID: UUID) {
        guard activeRequest == requestID else { return }
        activeRequest = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isBusy = false
        state = earned ? .rewarded : .failed
        provider.cancel(requestID: requestID)
        complete(.failed)
    }

    private func receive(_ event: RewardedAdEvent, requestID: UUID,
                         placement: RewardedAdPlacement) {
        guard activeRequest == requestID else { return }
        switch event {
        case .presented:
            if !earned { state = .presenting }
        case .rewardEarned:
            guard !earned else { return }
            // Mark before invoking the ledger to reject reentrant/duplicate callbacks.
            earned = true
            do {
                guard try ledger.grantOnce(AdRewardReceipt(requestID: requestID, placement: placement)) else {
                    throw DuplicateReceipt.alreadyApplied
                }
                state = .rewarded
            } catch {
                activeRequest = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                isBusy = false
                state = .failed
                provider.cancel(requestID: requestID)
                complete(.failed)
            }
        case .closed, .failed, .unavailable:
            activeRequest = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            isBusy = false
            if earned { state = .rewarded }
            else if event == .closed { state = .cancelled }
            else if event == .unavailable { state = .unavailable }
            else { state = .failed }
            complete(event == .closed ? .closed(rewardGranted: earned) : event == .unavailable ? .unavailable : .failed)
        }
    }

    private enum DuplicateReceipt: Error { case alreadyApplied }
    private func complete(_ result: Completion) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}
