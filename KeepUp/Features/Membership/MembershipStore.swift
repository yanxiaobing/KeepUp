import Foundation
import Observation
import StoreKit

struct MembershipConfiguration: Codable, Sendable {
    struct Offer: Codable, Identifiable, Sendable {
        let id: String
        let kind: String
        let months: Int
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

@MainActor @Observable
final class MembershipStore {
    let configuration = MembershipConfiguration.bundled()
    private(set) var products: [String: Product] = [:]
    private(set) var isPremium = false
    private(set) var busy = false
    var message: String?

    func load() async {
        #if DEBUG
        // UI appearance tests never contact the App Store or initiate transactions.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        #endif
        do {
            let loaded = try await Product.products(for: configuration.offers.map(\.id))
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            await refreshEntitlements()
        } catch { message = "membership.loadError" }
    }

    func purchase(_ offer: MembershipConfiguration.Offer) async {
        guard !busy else { return }
        guard let product = products[offer.id] else { message = "membership.unavailable"; return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { message = "membership.verifyError"; return }
                await transaction.finish()
                await refreshEntitlements()
            case .pending: message = "membership.pending"
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = "membership.purchaseError" }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPremium { message = "membership.noPurchases" }
        } catch { message = "membership.restoreError" }
    }

    func refreshEntitlements() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        #endif
        var premium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               configuration.offers.contains(where: { $0.id == transaction.productID }),
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > .now }) ?? true { premium = true }
        }
        isPremium = premium
    }
}
