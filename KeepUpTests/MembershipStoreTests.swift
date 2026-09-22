import Foundation
import StoreKit
import Testing
@testable import KeepUp

@MainActor
private final class MembershipGatewayStub: MembershipTransactions {
    var values: [MembershipTransaction] = []
    var finished: [UInt64] = []
    var syncCount = 0
    var streams = 0
    var continuation: AsyncStream<MembershipTransaction>.Continuation?
    var suspended: CheckedContinuation<[MembershipTransaction], Never>?
    var suspendNext = false
    func currentEntitlements() async -> [MembershipTransaction] {
        if suspendNext {
            suspendNext = false
            return await withCheckedContinuation { suspended = $0 }
        }
        return values
    }
    func updates() -> AsyncStream<MembershipTransaction> {
        streams += 1
        return AsyncStream { continuation = $0 }
    }
    var purchaseResult: MembershipPurchaseResult = .cancelled
    var purchaseFails = false
    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        if purchaseFails { throw StoreKitError.unknown }
        return purchaseResult
    }
    var loadedIDs: [[String]] = []
    func loadProducts(_ ids: [String]) async throws -> [Product] { loadedIDs.append(ids); return [] }
    func canPurchase(_ id: String) -> Bool { true }
    func synchronize() async throws { syncCount += 1 }
    func finish(_ id: UInt64) async { finished.append(id) }
}
private let membershipFixture = MembershipConfiguration(offers: [.init(id: "keepup.premium", kind: "lifetime", months: 0)], carouselInterval: 5, closeAlpha: 1, priceAlpha: 1)
private func entitlement(_ id: UInt64 = 1, product: String = "keepup.premium", expiry: Date? = nil, revoked: Bool = false, verified: Bool = true, upgraded: Bool = false) -> MembershipTransaction {
    .init(id: id, productID: product, expirationDate: expiry, revocationDate: revoked ? .now : nil, isUpgraded: upgraded, verified: verified)
}

@Test @MainActor func membershipRejectsUnverifiedRevokedExpiredUpgradedAndUnknown() async {
    let gateway = MembershipGatewayStub()
    let now = Date.now
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway, now: { now })
    for transaction in [entitlement(verified: false), entitlement(revoked: true), entitlement(expiry: now), entitlement(upgraded: true), entitlement(product: "other.app")] {
        gateway.values = [transaction]
        await store.refreshEntitlements()
        #expect(!store.isPremium)
        #expect(store.canShowAds)
    }
    gateway.values = [entitlement()]
    await store.refreshEntitlements()
    #expect(store.isPremium)
    #expect(!store.canShowAds)
}

@Test @MainActor func membershipHiddenOfferRetainsOwnershipAndRestoreRefreshes() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    store.applyConfiguration(configuration: .init(offers: [], carouselInterval: 5, closeAlpha: 1, priceAlpha: 1), entitlementProductIDs: [])
    gateway.values = [entitlement()]
    await store.restore()
    #expect(gateway.syncCount == 1)
    #expect(store.isPremium)
    gateway.values = []
    await store.restore()
    #expect(!store.isPremium)
    #expect(store.message == "membership.noPurchases")
}

@Test @MainActor func membershipStartsSingleListenerAndRefreshesOnRevocation() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    gateway.values = [entitlement()]
    await store.start()
    await store.start()
    #expect(gateway.streams == 1)
    #expect(store.isPremium)
    gateway.values = [entitlement(revoked: true)]
    gateway.continuation?.yield(entitlement(revoked: true))
    for _ in 0..<100 where gateway.finished.isEmpty { await Task.yield() }
    #expect(!store.isPremium)
    #expect(gateway.finished == [1])
    gateway.continuation?.finish()
}

@Test @MainActor func membershipStaleRefreshCannotOverwriteNewerSnapshot() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    gateway.suspendNext = true
    let stale = Task { await store.refreshEntitlements() }
    while gateway.suspended == nil { await Task.yield() }
    gateway.values = []
    await store.refreshEntitlements()
    gateway.suspended?.resume(returning: [entitlement()])
    await stale.value
    #expect(!store.isPremium)
}

@Test @MainActor func membershipExpiresWithoutReopeningScreen() async throws {
    let gateway = MembershipGatewayStub()
    gateway.values = [entitlement(expiry: .now.addingTimeInterval(0.03))]
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    await store.refreshEntitlements()
    #expect(store.isPremium)
    try await Task.sleep(for: .milliseconds(80))
    #expect(!store.isPremium)
}

@Test @MainActor func membershipPurchaseResultsNeverGrantUnverifiedOrPendingOwnership() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    let offer = membershipFixture.offers[0]
    gateway.purchaseResult = .pending
    await store.purchase(offer)
    #expect(store.message == "membership.pending")
    #expect(!store.isPremium && !store.busy)
    store.message = nil
    gateway.purchaseResult = .cancelled
    await store.purchase(offer)
    #expect(store.message == nil && !store.isPremium)
    gateway.purchaseResult = .success(entitlement(verified: false))
    await store.purchase(offer)
    #expect(store.message == "membership.verifyError")
    #expect(gateway.finished.isEmpty && !store.isPremium)
    gateway.purchaseFails = true
    await store.purchase(offer)
    #expect(store.message == "membership.purchaseError" && !store.busy)
    gateway.purchaseFails = false
    gateway.values = [entitlement()]
    gateway.purchaseResult = .success(entitlement())
    await store.purchase(offer)
    #expect(store.isPremium && !store.busy)
    #expect(gateway.finished == [1])
}

@Test @MainActor func membershipExpirationPreservesIndependentLifetimeOwnership() async throws {
    let gateway = MembershipGatewayStub()
    gateway.values = [entitlement(expiry: .now.addingTimeInterval(0.03)), entitlement(2)]
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    await store.refreshEntitlements()
    try await Task.sleep(for: .milliseconds(80))
    #expect(store.isPremium)
}

@Test @MainActor func membershipOlderPageLoadCannotOverrideNewerCatalog() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    gateway.suspendNext = true
    let stale = Task { await store.load(offers: [.init(id: "old", kind: "lifetime", months: 0)]) }
    while gateway.suspended == nil { await Task.yield() }
    await store.load(offers: [.init(id: "new", kind: "lifetime", months: 0)])
    gateway.suspended?.resume(returning: [])
    await stale.value
    #expect(gateway.loadedIDs == [["new"]])
    gateway.continuation?.finish()
}

@Test @MainActor func membershipCancelledRefreshPreservesExistingOwnership() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    gateway.values = [entitlement()]
    await store.refreshEntitlements()
    #expect(store.isPremium)
    gateway.suspendNext = true
    let cancelled = Task { await store.refreshEntitlements() }
    while gateway.suspended == nil { await Task.yield() }
    cancelled.cancel()
    gateway.suspended?.resume(returning: [])
    await cancelled.value
    #expect(store.isPremium)
}

@Test @MainActor func membershipMissingProductsShowsInlineErrorWithoutAlert() async {
    let gateway = MembershipGatewayStub()
    let store = MembershipStore(configuration: membershipFixture, transactions: gateway)
    await store.load()
    #expect(store.productLoadError == "membership.unavailable")
    #expect(store.message == nil)
    await store.load(cache: false)
    #expect(gateway.loadedIDs.count == 2)
    #expect(store.message == nil)
    gateway.continuation?.finish()
}

@Test func adMobUsesFormatSpecificUnitsForCurrentBuild() {
    let configured = "ca-app-pub-1234567890123456/1234567890"
    #if DEBUG
    #expect(AdMobAdUnit.resolve(configured, format: .appOpen) == "ca-app-pub-3940256099942544/5575463023")
    #expect(AdMobAdUnit.resolve(configured, format: .interstitial) == "ca-app-pub-3940256099942544/4411468910")
    #expect(AdMobAdUnit.resolve(configured, format: .rewarded) == "ca-app-pub-3940256099942544/1712485313")
    #else
    #expect(AdMobAdUnit.resolve(configured, format: .appOpen) == configured)
    #expect(AdMobAdUnit.resolve(configured, format: .interstitial) == configured)
    #expect(AdMobAdUnit.resolve(configured, format: .rewarded) == configured)
    #endif
}
