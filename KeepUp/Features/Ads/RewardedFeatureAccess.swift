import Foundation
import Observation

@MainActor protocol RewardReceiptStore: AnyObject {
    /// Commit before returning true. A duplicate must return false without mutation.
    func insertIfNew(_ receiptID: UUID) throws -> Bool
}

/// The app owns one instance. Re-read on each commit to support independently reopened stores.
/// Only receipts persist: an interrupted feature request cannot be resumed after relaunch.
@MainActor final class JSONRewardReceiptStore: RewardReceiptStore {
    private let url: URL
    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("KeepUp/reward-receipts.json")) {
        self.url = url
    }
    func insertIfNew(_ receiptID: UUID) throws -> Bool {
        var receipts: Set<UUID> = []
        if FileManager.default.fileExists(atPath: url.path) {
            receipts = try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: url))
        }
        guard receipts.insert(receiptID).inserted else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(receipts).write(to: url, options: .atomic)
        return true
    }
}

@MainActor private final class FeatureRewardLedger: AdRewardLedger {
    let receipts: any RewardReceiptStore
    var armed: UUID?
    var earned: UUID?
    init(receipts: any RewardReceiptStore) { self.receipts = receipts }
    func grantOnce(_ receipt: AdRewardReceipt) throws -> Bool {
        guard receipt.placement.rewardRuleID == "keepup.feature-once.v1", let armed, earned == nil else { return false }
        guard try receipts.insertIfNew(receipt.requestID) else { return false }
        // The durable receipt and transient grant are committed synchronously on MainActor.
        earned = armed
        return true
    }
    func reset() { armed = nil; earned = nil }
}

/// Completing the configured number of videos authorizes one pending feature action.
/// Call only when the entry has an enabled IAAP reward configuration. Disabled ads
/// bypass this object to preserve the existing free functionality.
@MainActor @Observable final class RewardedFeatureAccess {
    enum FeatureID: String, CaseIterable { case stepGoal, weightTarget, reminders }
    struct Outcome {
        let requestID: UUID
        let featureID: FeatureID
        let granted: Bool
        let didDismiss: Bool
        let terminal: RewardedAdController.Completion
    }
    let controller: RewardedAdController
    private(set) var isBusy = false
    private(set) var completedCount = 0
    private var requiredCount = 1
    private var progressFeature: FeatureID?
    @ObservationIgnored private let ledger: FeatureRewardLedger
    @ObservationIgnored private var active: (id: UUID, feature: FeatureID)?
    @ObservationIgnored private var permit: (id: UUID, feature: FeatureID)?
    @ObservationIgnored private var completion: (@MainActor (Outcome) -> Void)?

    init(provider: any RewardedAdProvider, receiptStore: (any RewardReceiptStore)? = nil,
         timeout: Duration = .seconds(120)) {
        let ledger = FeatureRewardLedger(receipts: receiptStore ?? JSONRewardReceiptStore())
        self.ledger = ledger
        controller = RewardedAdController(provider: provider, ledger: ledger, timeout: timeout)
    }

    /// Completion runs once. `didDismiss` is true only for an actual SDK closed event.
    /// A grant can be consumed only after both earned and closed, by the same request/feature.
    @discardableResult func request(featureID: FeatureID, requiredCount: Int = 1, completion: @escaping @MainActor (Outcome) -> Void) -> Bool {
        guard active == nil, !controller.isBusy else { return false }
        if progressFeature != featureID || self.requiredCount != requiredCount || permit != nil {
            completedCount = 0
        }
        progressFeature = featureID
        self.requiredCount = max(1, requiredCount)
        permit = nil
        let request = (id: UUID(), feature: featureID)
        active = request
        self.completion = completion
        isBusy = true
        ledger.reset()
        ledger.armed = request.id
        let started = controller.present { [weak self] terminal in self?.finish(terminal) }
        if !started { finish(.unavailable) }
        return started
    }

    @discardableResult func consume(featureID: FeatureID, requestID: UUID) -> Bool {
        guard permit?.id == requestID, permit?.feature == featureID else { return false }
        permit = nil
        completedCount = 0
        progressFeature = nil
        return true
    }

    func cancel() {
        completedCount = 0
        progressFeature = nil
        permit = nil
        ledger.reset()
        let cancelledID = active?.id
        controller.cancel()
        if let cancelledID, active?.id == cancelledID { finish(.cancelled) }
    }

    private func finish(_ terminal: RewardedAdController.Completion) {
        guard let request = active else { return }
        let dismissed: Bool
        let granted: Bool
        if case .closed(let rewarded) = terminal {
            dismissed = true
            if rewarded && ledger.earned == request.id { completedCount += 1 }
            granted = rewarded && ledger.earned == request.id && completedCount >= requiredCount
        } else {
            dismissed = false
            granted = false
        }
        permit = granted ? request : nil
        active = nil
        isBusy = false
        ledger.reset()
        let callback = completion
        completion = nil
        callback?(Outcome(requestID: request.id, featureID: request.feature, granted: granted, didDismiss: dismissed, terminal: terminal))
    }
}
