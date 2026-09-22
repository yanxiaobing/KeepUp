import Foundation

extension IAAPConfiguration {
    func membershipConfiguration(for entry: String = "vip") -> MembershipConfiguration {
        let page = page(for: entry)
        let legacyMonths = Dictionary(uniqueKeysWithValues: MembershipConfiguration.bundled().offers.map { ($0.id, $0.months) })
        return MembershipConfiguration(
            offers: displayedSKUs(for: entry).filter(\.grantsMembership).map {
                .init(id: $0.pid, kind: $0.type == .lifetime ? "lifetime" : "subscription", months: legacyMonths[$0.pid] ?? 0, titleType: $0.titleType, description: $0.desc)
            },
            carouselInterval: page?.iap.timeInterval ?? 5,
            closeAlpha: page?.closeAlpha ?? 0.5,
            priceAlpha: page?.priceAlpha ?? 0.5
        )
    }
}
