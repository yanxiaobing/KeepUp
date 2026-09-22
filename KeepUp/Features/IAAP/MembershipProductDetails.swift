import Foundation
import StoreKit

/// Presentation facts from StoreKit, corresponding to the reference SKProduct extensions.
/// The page supplies layout; prices, periods and introductory eligibility come from Apple.
struct MembershipProductDetails: Sendable {
    let product: Product
    let introEligible: Bool

    func priceDescription(locale: Locale) -> String {
        guard let subscription = product.subscription else { return product.displayPrice }
        let regular = product.displayPrice + "/" + Self.period(subscription.subscriptionPeriod, locale: locale)
        guard introEligible, let offer = subscription.introductoryOffer else { return regular }
        let length = Self.period(offer.period, count: offer.periodCount, locale: locale)
        if offer.paymentMode == .freeTrial {
            return String(format: localized("membership.introTrial %@ %@", locale), length, regular)
        }
        if offer.paymentMode == .payUpFront {
            return String(format: localized("membership.introUpfront %@ %@ %@", locale), length, offer.displayPrice, regular)
        }
        if offer.paymentMode == .payAsYouGo {
            let introductory = offer.displayPrice + "/" + Self.period(offer.period, locale: locale)
            return String(format: localized("membership.introRecurring %@ %@ %@", locale), length, introductory, regular)
        }
        return regular
    }

    static func period(_ period: Product.SubscriptionPeriod, count: Int = 1, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar?.locale = locale
        formatter.unitsStyle = .full
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value * count
        case .week: components.weekOfMonth = period.value * count
        case .month: components.month = period.value * count
        case .year: components.year = period.value * count
        @unknown default: return ""
        }
        return formatter.string(from: components) ?? ""
    }
}
