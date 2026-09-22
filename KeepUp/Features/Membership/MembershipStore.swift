import Foundation
import Observation
import StoreKit

struct MembershipConfiguration: Codable, Sendable {
    struct Offer: Codable, Identifiable, Sendable {
        let id: String
        let kind: String
        let months: Int
        var titleType: String? = nil
        var description: String? = nil
    }
    let offers: [Offer]
    let carouselInterval: Double
    let closeAlpha: Double
    let priceAlpha: Double
    static func bundled() -> Self {
        guard let url = Bundle.main.url(forResource: "membership", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return .init(offers: [], carouselInterval: 5, closeAlpha: 0.5, priceAlpha: 0.5)
        }
        return value
    }
}

/// Value snapshots keep entitlement policy testable without constructing StoreKit transactions.
struct MembershipTransaction: Sendable {
    let id: UInt64
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let verified: Bool
}

enum MembershipPurchaseResult { case success(MembershipTransaction), pending, cancelled }

@MainActor
protocol MembershipTransactions {
    func currentEntitlements() async -> [MembershipTransaction]
    func updates() -> AsyncStream<MembershipTransaction>
    func purchase(productID: String) async throws -> MembershipPurchaseResult
    func loadProducts(_ ids: [String]) async throws -> [Product]
    func canPurchase(_ id: String) -> Bool
    func synchronize() async throws
    func finish(_ id: UInt64) async
}

@MainActor
final class StoreKitMembershipTransactions: MembershipTransactions {
    private var catalog: [String: Product] = [:]
    private var unfinished: [UInt64: Transaction] = [:]
    private func snapshot(_ result: VerificationResult<Transaction>) -> MembershipTransaction {
        let transaction: Transaction
        let verified: Bool
        switch result {
        case .verified(let value): transaction = value; verified = true; unfinished[value.id] = value
        case .unverified(let value, _): transaction = value; verified = false
        }
        return MembershipTransaction(id: transaction.id, productID: transaction.productID,
                                     expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate,
                                     isUpgraded: transaction.isUpgraded, verified: verified)
    }
    func currentEntitlements() async -> [MembershipTransaction] {
        var values: [MembershipTransaction] = []
        for await result in Transaction.currentEntitlements { values.append(snapshot(result)) }
        return values
    }
    func updates() -> AsyncStream<MembershipTransaction> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { break }
                    continuation.yield(self.snapshot(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        guard let product = catalog[productID] else { throw StoreKitError.notAvailableInStorefront }
        switch try await product.purchase() {
        case .success(let result): return .success(snapshot(result))
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }
    func loadProducts(_ ids: [String]) async throws -> [Product] {
        let values = try await Product.products(for: ids)
        let received = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        for id in ids { catalog[id] = received[id] }
        return values
    }
    func canPurchase(_ id: String) -> Bool { catalog[id] != nil }
    func synchronize() async throws { try await AppStore.sync() }
    func finish(_ id: UInt64) async { await unfinished.removeValue(forKey: id)?.finish() }
}

@MainActor @Observable
final class MembershipStore {
    private(set) var configuration: MembershipConfiguration
    let productCatalog: MembershipProductCatalog<Product>
    var products: [String: Product] { productCatalog.values }
    private(set) var introductoryEligibility: [String: Bool] = [:]
    var loadingProductIDs: Set<String> { productCatalog.loadingIDs }
    private(set) var isPremium = false
    private(set) var busy = false
    var message: String?
    var canShowAds: Bool { !isPremium }
    private var entitlementProductIDs: Set<String>
    @ObservationIgnored private let transactions: any MembershipTransactions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var activeTransactions: [MembershipTransaction] = []

    init(configuration: MembershipConfiguration = .bundled(), transactions: (any MembershipTransactions)? = nil,
         now: @escaping () -> Date = { .now }) {
        self.configuration = configuration
        entitlementProductIDs = Set(configuration.offers.map(\.id))
        let gateway = transactions ?? StoreKitMembershipTransactions()
        self.transactions = gateway
        self.productCatalog = MembershipProductCatalog { ids in
            let products = try await gateway.loadProducts(ids)
            return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        }
        self.now = now
    }

    deinit { listener?.cancel(); expirationTask?.cancel() }

    func applyConfiguration(configuration: MembershipConfiguration, entitlementProductIDs: Set<String>) {
        self.configuration = configuration
        // Visibility is a merchandising decision, never the source of historical ownership.
        self.entitlementProductIDs.formUnion(entitlementProductIDs)
        updateEntitlementState()
    }

    func start() async {
        guard !isUITesting else { return }
        if listener == nil {
            let stream = transactions.updates()
            listener = Task { [weak self] in
                for await transaction in stream {
                    guard !Task.isCancelled else { break }
                    await self?.receive(transaction)
                }
            }
        }
        await refreshEntitlements()
    }

    func prefetchProducts(ids: Set<String>) async {
        guard !isUITesting else { return }
        // Preloading is silent; an opened page owns error feedback and explicit retry.
        _ = try? await productCatalog.load(ids)
    }

    func load(offers: [MembershipConfiguration.Offer]? = nil, cache: Bool = true) async {
        guard !isUITesting else { return }
        message = nil
        loadGeneration += 1
        let generation = loadGeneration
        let ids = (offers ?? configuration.offers).map(\.id)
        for id in ids { introductoryEligibility[id] = nil }
        await start()
        guard generation == loadGeneration, !Task.isCancelled else { return }
        do {
            _ = try await productCatalog.load(Set(ids), cache: cache)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            if !productCatalog.isPrepared(Set(ids)) { message = "membership.unavailable" }
            await refreshProductDetails(ids: ids, generation: generation)
        } catch { if generation == loadGeneration && !Task.isCancelled { message = "membership.loadError" } }
    }

    func productDetails(for id: String) -> MembershipProductDetails? {
        products[id].map { MembershipProductDetails(product: $0, introEligible: introductoryEligibility[id] == true) }
    }

    private func refreshProductDetails(ids: [String], generation: Int) async {
        for id in ids { introductoryEligibility[id] = nil }
        for id in ids {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            guard let product = products[id] else { introductoryEligibility[id] = nil; continue }
            let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
            guard generation == loadGeneration, !Task.isCancelled else { return }
            introductoryEligibility[id] = eligible
        }
    }

    func purchase(_ offer: MembershipConfiguration.Offer) async {
        guard !busy else { return }
        guard entitlementProductIDs.contains(offer.id), transactions.canPurchase(offer.id) else {
            message = "membership.unavailable"; return
        }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await transactions.purchase(productID: offer.id) {
            case .success(let transaction): await receive(transaction)
            case .pending: message = "membership.pending"
            case .cancelled: break
            }
        } catch { message = "membership.purchaseError" }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await transactions.synchronize()
            await refreshEntitlements()
            await refreshProductDetails(ids: Array(products.keys), generation: loadGeneration)
            if !isPremium { message = "membership.noPurchases" }
        } catch { message = "membership.restoreError" }
    }

    private func receive(_ transaction: MembershipTransaction) async {
        guard transaction.verified else { message = "membership.verifyError"; return }
        guard entitlementProductIDs.contains(transaction.productID) else { return }
        await refreshEntitlements()
        await transactions.finish(transaction.id)
        await refreshProductDetails(ids: Array(products.keys), generation: loadGeneration)
    }

    func refreshEntitlements() async {
        guard !isUITesting else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let values = await transactions.currentEntitlements()
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        activeTransactions = values
        updateEntitlementState()
    }

    private func updateEntitlementState() {
        expirationTask?.cancel()
        let date = now()
        let valid = activeTransactions.filter {
            $0.verified && entitlementProductIDs.contains($0.productID) && !$0.isUpgraded &&
            $0.revocationDate == nil && ($0.expirationDate.map { $0 > date } ?? true)
        }
        isPremium = !valid.isEmpty
        guard let expiry = valid.compactMap(\.expirationDate).min() else { return }
        let delay = max(0, expiry.timeIntervalSince(date))
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            // Revoke the expired local snapshot even if the StoreKit refresh is slow.
            self.expirationTask = nil
            self.updateEntitlementState()
            await self.refreshEntitlements()
        }
    }

    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }
}
