import Foundation
import Testing
@testable import KeepUp

@MainActor private final class FeatureAdProvider: RewardedAdProvider {
    let providerID = "fixture"
    var callbacks: [(@MainActor (RewardedAdEvent) -> Void)] = []
    var requests: [UUID] = []
    var cancelled: [UUID] = []
    func present(placement: RewardedAdPlacement, requestID: UUID, receive: @escaping @MainActor (RewardedAdEvent) -> Void) {
        requests.append(requestID); callbacks.append(receive)
    }
    func cancel(requestID: UUID) { cancelled.append(requestID) }
    func emit(_ event: RewardedAdEvent, index: Int = 0) { callbacks[index](event) }
}
@MainActor private final class FeatureReceiptFixture: RewardReceiptStore {
    var receipts: Set<UUID> = []
    var fails = false
    var duplicate = false
    func insertIfNew(_ receiptID: UUID) throws -> Bool {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        return !duplicate && receipts.insert(receiptID).inserted
    }
}
@MainActor private func featureAccess(_ provider: FeatureAdProvider, _ receipts: FeatureReceiptFixture) -> RewardedFeatureAccess {
    let access = RewardedFeatureAccess(provider: provider, receiptStore: receipts)
    access.controller.updateEligibility(placement: .init(providerID: "fixture", adUnitID: "fixture-unit", rewardRuleID: "keepup.feature-once.v1"), canShowAds: true, privacyAllowsAds: true)
    return access
}

@Test @MainActor func featureAccessWaitsForEarnedAndClosedAndConsumesExactlyOnce() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    #expect(access.request(featureID: .stepGoal) { outcomes.append($0) })
    provider.emit(.rewardEarned)
    provider.emit(.rewardEarned)
    #expect(outcomes.isEmpty && receipts.receipts.count == 1)
    provider.emit(.closed)
    provider.emit(.closed)
    #expect(outcomes.count == 1)
    let outcome = outcomes[0]
    #expect(outcome.granted && outcome.didDismiss)
    #expect(!access.consume(featureID: .reminders, requestID: outcome.requestID))
    #expect(!access.consume(featureID: .stepGoal, requestID: UUID()))
    #expect(access.consume(featureID: .stepGoal, requestID: outcome.requestID))
    #expect(!access.consume(featureID: .stepGoal, requestID: outcome.requestID))
}

@Test @MainActor func featureAccessEarlyCloseAndLateEarnedCannotGrant() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    access.request(featureID: .reminders) { outcomes.append($0) }
    provider.emit(.closed)
    provider.emit(.rewardEarned)
    #expect(outcomes.count == 1 && !outcomes[0].granted && outcomes[0].didDismiss)
    #expect(receipts.receipts.isEmpty)
}

@Test @MainActor func featureAccessCancellationInvalidatesEarnedPermitAndCompletesOnce() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    access.request(featureID: .stepGoal) { outcomes.append($0) }
    provider.emit(.rewardEarned)
    access.cancel()
    provider.emit(.closed)
    provider.emit(.rewardEarned)
    #expect(outcomes.count == 1 && !outcomes[0].granted && !outcomes[0].didDismiss)
    #expect(outcomes[0].terminal == .cancelled)
    #expect(!access.consume(featureID: .stepGoal, requestID: outcomes[0].requestID))
    #expect(receipts.receipts.count == 1)
}

@Test @MainActor func featureAccessFailuresNoFillAndLedgerErrorsNeverGrant() {
    for event in [RewardedAdEvent.failed, .unavailable] {
        let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
        let access = featureAccess(provider, receipts)
        var outcome: RewardedFeatureAccess.Outcome?
        access.request(featureID: .reminders) { outcome = $0 }
        provider.emit(.rewardEarned)
        provider.emit(event)
        #expect(outcome?.granted == false && outcome?.didDismiss == false)
        #expect(outcome?.terminal == (event == .failed ? .failed : .unavailable))
    }
    for duplicate in [false, true] {
        let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
        receipts.fails = !duplicate; receipts.duplicate = duplicate
        let access = featureAccess(provider, receipts)
        var outcomes: [RewardedFeatureAccess.Outcome] = []
        access.request(featureID: .reminders) { outcomes.append($0) }
        provider.emit(.rewardEarned)
        provider.emit(.closed)
        #expect(outcomes.count == 1 && outcomes[0].terminal == .failed && !outcomes[0].granted)
    }
}

@Test @MainActor func featureAccessReceiptsDeduplicateAcrossRestartWithoutRestoringPermit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("receipts.json")
    let id = UUID()
    #expect(try JSONRewardReceiptStore(url: url).insertIfNew(id))
    #expect(try !JSONRewardReceiptStore(url: url).insertIfNew(id))
    let access = RewardedFeatureAccess(provider: FeatureAdProvider(), receiptStore: JSONRewardReceiptStore(url: url))
    #expect(!access.consume(featureID: .stepGoal, requestID: id))
    try Data("invalid".utf8).write(to: url)
    #expect(throws: (any Error).self) { try JSONRewardReceiptStore(url: url).insertIfNew(UUID()) }
}

@Test @MainActor func featureAccessStaleEventsCannotGrantNextRequestAndCancelClearsUnusedPermit() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var first: RewardedFeatureAccess.Outcome?
    access.request(featureID: .stepGoal) { first = $0 }
    provider.emit(.rewardEarned); provider.emit(.closed)
    access.cancel()
    #expect(!access.consume(featureID: .stepGoal, requestID: first!.requestID))
    var second: RewardedFeatureAccess.Outcome?
    access.request(featureID: .weightTarget) { second = $0 }
    provider.emit(.rewardEarned); provider.emit(.closed)
    #expect(second == nil)
    provider.emit(.rewardEarned, index: 1); provider.emit(.closed, index: 1)
    #expect(second?.granted == true)
    #expect(access.consume(featureID: .weightTarget, requestID: second!.requestID))
}

@Test @MainActor func featureAccessDisabledAndRevokedEligibilityResolvePendingRequest() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = RewardedFeatureAccess(provider: provider, receiptStore: receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    #expect(!access.request(featureID: .stepGoal) { outcomes.append($0) })
    #expect(outcomes.count == 1 && outcomes[0].terminal == .unavailable)
    access.controller.updateEligibility(placement: .init(providerID: "fixture", adUnitID: "fixture", rewardRuleID: "keepup.feature-once.v1"), canShowAds: true, privacyAllowsAds: true)
    access.request(featureID: .stepGoal) { outcomes.append($0) }
    access.controller.updateEligibility(placement: nil, canShowAds: false, privacyAllowsAds: false)
    provider.emit(.rewardEarned); provider.emit(.closed)
    #expect(outcomes.count == 2 && outcomes[1].terminal == .cancelled && !outcomes[1].granted)
}

@Test @MainActor func featureAccessTimeoutTerminatesAndBusyRequestCannotReplaceOwner() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    access.request(featureID: .stepGoal) { outcomes.append($0) }
    #expect(!access.request(featureID: .reminders) { _ in Issue.record("Busy request replaced owner") })
    provider.emit(.rewardEarned)
    access.controller.handleTimeout(requestID: provider.requests[0])
    provider.emit(.closed)
    #expect(outcomes.count == 1 && outcomes[0].terminal == .failed && !outcomes[0].didDismiss)
    #expect(!access.consume(featureID: .stepGoal, requestID: outcomes[0].requestID))
}

@Test @MainActor func featureAccessMultipleVideosCountOnceAndGrantOnlyAtTarget() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    var outcomes: [RewardedFeatureAccess.Outcome] = []
    access.request(featureID: .stepGoal, requiredCount: 2) { outcomes.append($0) }
    provider.emit(.rewardEarned); provider.emit(.rewardEarned); provider.emit(.closed); provider.emit(.closed)
    #expect(access.completedCount == 1 && outcomes.count == 1 && !outcomes[0].granted)
    #expect(!access.consume(featureID: .stepGoal, requestID: outcomes[0].requestID))
    access.request(featureID: .stepGoal, requiredCount: 2) { outcomes.append($0) }
    provider.emit(.failed, index: 1)
    #expect(access.completedCount == 1 && !outcomes[1].granted)
    access.request(featureID: .stepGoal, requiredCount: 2) { outcomes.append($0) }
    provider.emit(.rewardEarned, index: 2); provider.emit(.closed, index: 2)
    #expect(access.completedCount == 2 && outcomes[2].granted)
    #expect(access.consume(featureID: .stepGoal, requestID: outcomes[2].requestID))
    #expect(!access.consume(featureID: .stepGoal, requestID: outcomes[2].requestID))
    #expect(access.completedCount == 0)
}

@Test @MainActor func featureAccessCancelClearsPartialProgress() {
    let provider = FeatureAdProvider(), receipts = FeatureReceiptFixture()
    let access = featureAccess(provider, receipts)
    access.request(featureID: .reminders, requiredCount: 2) { _ in }
    provider.emit(.rewardEarned); provider.emit(.closed)
    #expect(access.completedCount == 1)
    access.cancel()
    #expect(access.completedCount == 0)
    var result: RewardedFeatureAccess.Outcome?
    access.request(featureID: .reminders, requiredCount: 2) { result = $0 }
    provider.emit(.rewardEarned, index: 1); provider.emit(.closed, index: 1)
    #expect(result?.granted == false && access.completedCount == 1)
}
