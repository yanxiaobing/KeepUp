import Foundation
import Testing
@testable import KeepUp

private func iaapFixture(ids: [String] = ["com.bestlife.keepup.premium.lifetime"], shown: [String]? = nil) throws -> Data {
    let value = IAAPConfiguration(system: ["futureFlag": .bool(true)], ads: [:],
        skus: ids.map { .init(pid: $0, type: .lifetime, titleType: "timer") },
        iaaps: [.init(type: "vip", closeAlpha: 0.5, priceAlpha: 0.5, showGiveUp: true,
                     iap: .init(pids: shown ?? ids, timeInterval: 5, hidePageControl: false))])
    return try JSONEncoder().encode(value)
}

@Test func iaapRejectsMalformedCatalogAndPreservesOpaqueFields() throws {
    let valid = try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture()).validated()
    #expect(valid.system["futureFlag"] == .bool(true))
    #expect(valid.displayedSKUs(for: "vip").count == 1)
    #expect(throws: IAAPConfigurationError.self) {
        try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture(ids: ["other.app.product"])).validated()
    }
    #expect(throws: IAAPConfigurationError.self) {
        try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture(shown: ["unknown"])).validated()
    }
}

@Test @MainActor func iaapCachePreservesHiddenHistoricalEntitlementsAcrossRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = directory.appendingPathComponent("config.json")
    let url = URL(string: "https://example.invalid/keepup-test.json")!
    let old = "com.bestlife.keepup.premium.lifetime"
    let new = "com.bestlife.keepup.premium.future"
    let bundled = try iaapFixture(ids: [old])
    let remote = try iaapFixture(ids: [new])
    let store = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: bundled, fetch: { request in
        (remote, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await store.refresh()
    #expect(store.source == .remote)
    #expect(store.configuration.displayedSKUs(for: "vip").map(\.pid) == [new])
    #expect(store.entitlementProductIDs == Set([old, new]))
    let reopened = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: bundled)
    #expect(reopened.source == .cache)
    #expect(reopened.entitlementProductIDs == Set([old, new]))

    let switched = IAAPConfigurationStore(remoteURL: URL(string: "https://example.invalid/other"), cacheURL: cache, bundledData: bundled)
    #expect(switched.source == .bundled)
    #expect(switched.configuration.skus.map(\.pid) == [old])
    #expect(switched.entitlementProductIDs == Set([old, new]))

    let before = try Data(contentsOf: cache)
    let invalid = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: bundled, fetch: { request in
        (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await invalid.refresh()
    #expect(invalid.source == .cache)
    #expect(invalid.lastError != nil)
    #expect(try Data(contentsOf: cache) == before)
}

@Test @MainActor func iaapMissingURLAndHTTPNeverFetchAndCorruptCacheFallsBack() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: cache) }
    try Data("broken".utf8).write(to: cache)
    let data = try iaapFixture()
    let missing = IAAPConfigurationStore(cacheURL: cache, bundledData: data, fetch: { _ in
        Issue.record("Missing URL must not fetch")
        throw URLError(.badURL)
    })
    await missing.refresh()
    #expect(missing.source == .bundled)
    #expect(missing.configuration.skus.count == 1)
    let insecure = IAAPConfigurationStore(remoteURL: URL(string: "http://example.invalid/test"), cacheURL: nil, bundledData: data, fetch: { _ in
        Issue.record("HTTP URL must not fetch")
        throw URLError(.badURL)
    })
    await insecure.refresh()
    #expect(insecure.lastError != nil)
}

@Test @MainActor func iaapNetworkAndHTTPFailuresRetainBundledConfiguration() async throws {
    let data = try iaapFixture()
    let url = URL(string: "https://example.invalid/test")!
    for status in [404, 500] {
        let store = IAAPConfigurationStore(remoteURL: url, cacheURL: nil, bundledData: data, fetch: { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        await store.refresh()
        #expect(store.source == .bundled)
        #expect(store.lastError != nil)
    }
    let offline = IAAPConfigurationStore(remoteURL: url, cacheURL: nil, bundledData: data, fetch: { _ in throw URLError(.notConnectedToInternet) })
    await offline.refresh()
    #expect(offline.source == .bundled)
    #expect(offline.lastError != nil)
}

@Test @MainActor func iaapRejectsDuplicatesTypeChangesAndCancelledDownloads() async throws {
    let id = "com.bestlife.keepup.premium.lifetime"
    #expect(throws: IAAPConfigurationError.self) {
        try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture(ids: [id, id])).validated()
    }
    let bundled = try iaapFixture()
    let changedType = Data(String(decoding: bundled, as: UTF8.self).replacingOccurrences(of: "\"type\":\"lifetime\"", with: "\"type\":\"subscribe\"").utf8)
    let url = URL(string: "https://example.invalid/test")!
    let changed = IAAPConfigurationStore(remoteURL: url, cacheURL: nil, bundledData: bundled, fetch: { request in
        (changedType, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await changed.refresh()
    #expect(changed.source == .bundled)
    #expect(changed.lastError == String(describing: IAAPConfigurationError.conflictingProductType))
    let cancelled = IAAPConfigurationStore(remoteURL: url, cacheURL: nil, bundledData: bundled, fetch: { _ in throw CancellationError() })
    await cancelled.refresh()
    #expect(cancelled.source == .bundled)
    #expect(!cancelled.isRefreshing)
    #expect(cancelled.lastError != nil)
}

/// Opt in only after the endpoint publishes guide/launch/limited/vip.
/// The formerly published final/limited_funcs schema is intentionally rejected.
/// Ordinary test runs remain offline and deterministic.
@Test(.enabled(if: ProcessInfo.processInfo.environment["KEEPUP_IAAP_LIVE_URL"] != nil))
@MainActor func iaapLiveEndpointDownloadsValidKeepUpCatalogAndCachesIt() async throws {
    let address = try #require(ProcessInfo.processInfo.environment["KEEPUP_IAAP_LIVE_URL"])
    let url = try #require(URL(string: address))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = directory.appendingPathComponent("live-cache.json")
    let store = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: try iaapFixture())
    await store.refresh()
    #expect(store.lastError == nil)
    #expect(store.source == .remote)
    let expected = ["lifetime", "year", "quarter", "month"].map { "com.bestlife.keepup.premium.\($0)" }
    #expect(store.configuration.skus.map(\.pid) == expected)
    for entry in ["guide", "launch", "limited", "vip"] {
        #expect(store.configuration.page(for: entry)?.type == entry)
        #expect(store.configuration.displayedSKUs(for: entry).map(\.pid) == expected)
    }
    #expect(store.entitlementProductIDs == Set(expected))
    let restored = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: try iaapFixture())
    #expect(restored.source == .cache)
    #expect(restored.configuration == store.configuration)
    #expect(restored.entitlementProductIDs == Set(expected))
}

@Test func iaapCacheBustingTimestampPreservesQueryAndReplacesAllVersions() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000.125)
    let inputs = [
        "https://example.invalid/config.json",
        "https://example.invalid/config.json?channel=ios&locale=zh-Hans",
        "https://example.invalid/config.json?v=old&channel=ios&v=older"
    ]
    for input in inputs {
        let original = try #require(URL(string: input))
        let result = try IAAPConfigurationStore.cacheBustingURL(for: original, now: now)
        let items = try #require(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "v" } == [URLQueryItem(name: "v", value: "1700000000125")])
        let originalItems = URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.filter { $0.name != "v" } == originalItems.filter { $0.name != "v" })
        let repeated = try IAAPConfigurationStore.cacheBustingURL(for: result, now: now.addingTimeInterval(1))
        let repeatedItems = try #require(URLComponents(url: repeated, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(repeatedItems.filter { $0.name == "v" } == [URLQueryItem(name: "v", value: "1700000001125")])
    }
}

@Test func iaapEntryPagesAreExactAndLegacySchemasAreRejected() throws {
    let sku = IAAPConfiguration.SKU(pid: "com.bestlife.keepup.premium.lifetime", type: .lifetime, titleType: nil)
    func page(_ type: String, pids: [String] = []) -> IAAPConfiguration.Page {
        .init(type: type, closeAlpha: nil, priceAlpha: nil, showGiveUp: nil,
              iap: .init(pids: pids, timeInterval: nil, hidePageControl: nil))
    }
    let vip = page("vip", pids: [sku.pid])
    let partial = try IAAPConfiguration(system: [:], ads: [:], skus: [sku], iaaps: [vip]).validated()
    #expect(partial.page(for: "vip") == vip)
    for missing in ["guide", "launch", "limited", "final", "limited_funcs"] {
        #expect(partial.page(for: missing) == nil)
        #expect(partial.displayedSKUs(for: missing).isEmpty)
    }
    let pages = [page("guide"), page("launch"), page("limited"), vip]
    let complete = try IAAPConfiguration(system: [:], ads: [:], skus: [sku], iaaps: pages).validated()
    for entry in pages { #expect(complete.page(for: entry.type) == entry) }
    for invalid in [[page("final")], [vip, page("final")], [vip, page("limited_funcs")], [page("launch")]] {
        #expect(throws: IAAPConfigurationError.self) {
            try IAAPConfiguration(system: [:], ads: [:], skus: [sku], iaaps: invalid).validated()
        }
    }
}

@Test @MainActor func iaapLegacyPageCacheRetainsHistoricalEntitlementsButNotPresentation() throws {
    struct LegacyCache: Encodable {
        let sourceURL: String
        let configuration: IAAPConfiguration
        let knownSKUs: [IAAPConfiguration.SKU]
    }
    let url = URL(string: "https://example.invalid/config.json")!
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let bundledID = "com.bestlife.keepup.premium.lifetime"
    let historicalID = "com.bestlife.keepup.premium.retired"
    let bundled = try iaapFixture(ids: [bundledID])
    let historical = IAAPConfiguration.SKU(pid: historicalID, type: .subscribe, titleType: nil)
    let legacy = IAAPConfiguration(system: [:], ads: [:], skus: [historical], iaaps: [
        .init(type: "final", closeAlpha: nil, priceAlpha: nil, showGiveUp: nil,
              iap: .init(pids: [historicalID], timeInterval: nil, hidePageControl: nil))
    ])
    let encoded = try JSONEncoder().encode(LegacyCache(sourceURL: url.absoluteString, configuration: legacy, knownSKUs: [historical]))
    try encoded.write(to: cacheURL)
    let restored = IAAPConfigurationStore(remoteURL: url, cacheURL: cacheURL, bundledData: bundled)
    #expect(restored.source == .bundled)
    #expect(restored.configuration.page(for: "final") == nil)
    #expect(restored.configuration.page(for: "vip") != nil)
    #expect(restored.entitlementProductIDs == Set([bundledID, historicalID]))
    #expect(restored.configuration.displayedSKUs(for: "vip").map(\.pid) == [bundledID])
}

@Test @MainActor func iaapLegacyRemotePageCannotReplaceCurrentConfiguration() async throws {
    let bundled = try iaapFixture()
    let original = try JSONDecoder().decode(IAAPConfiguration.self, from: bundled)
    let url = URL(string: "https://example.invalid/legacy-config.json")!
    for legacyType in ["final", "limited_funcs"] {
        let oldData = Data(String(decoding: bundled, as: UTF8.self)
            .replacingOccurrences(of: "\"type\":\"vip\"", with: "\"type\":\"\(legacyType)\"").utf8)
        let store = IAAPConfigurationStore(remoteURL: url, cacheURL: nil, bundledData: bundled, fetch: { request in
            (oldData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await store.refresh()
        #expect(store.source == .bundled)
        #expect(store.lastError != nil)
        #expect(store.configuration == original)
    }
}

@Test func iaapBenefitsPreserveOrderUnknownFieldsAndExplicitEmpty() throws {
    var page = try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture()).iaaps[0]
    #expect(page.displayedBenefits.map(\.type) == ["themes", "noad"])
    page.benefits = [
        .init(type: "noad", footer: 12),
        .init(type: "cloud", footer: 15),
        .init(type: "cyber", items: ["future"], timeInterval: 6, hidePageControl: false),
        .init(type: "themes", footer: 0, timeInterval: 8, hidePageControl: true)
    ]
    let decoded = try JSONDecoder().decode(IAAPConfiguration.Page.self, from: JSONEncoder().encode(page))
    #expect(decoded == page)
    #expect(decoded.displayedBenefits.map(\.type) == ["noad", "cloud", "themes"])
    #expect(decoded.displayedBenefits.last?.timeInterval == 8)
    page.benefits = []
    #expect(page.displayedBenefits.isEmpty)
}

@Test func iaapBenefitsRejectInvalidLayoutAndTimer() throws {
    let fixture = try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture())
    for benefit in [IAAPConfiguration.Page.Benefit(type: "noad", footer: -1),
                    .init(type: "themes", timeInterval: -1)] {
        var page = fixture.iaaps[0]
        page.benefits = [benefit]
        let config = IAAPConfiguration(system: fixture.system, ads: fixture.ads, skus: fixture.skus, iaaps: [page])
        #expect(throws: IAAPConfigurationError.self) { try config.validated() }
    }
}

@Test func iaapZeroCarouselIntervalSupportsManualPaging() throws {
    let original = try JSONDecoder().decode(IAAPConfiguration.self, from: iaapFixture())
    var page = IAAPConfiguration.Page(type: "vip", closeAlpha: 0, priceAlpha: 0.5, showGiveUp: true,
        iap: .init(pids: original.skus.map(\.pid), timeInterval: 0, hidePageControl: false))
    page.benefits = [.init(type: "themes", timeInterval: 0)]
    let config = try IAAPConfiguration(system: [:], ads: [:], skus: original.skus, iaaps: [page]).validated()
    #expect(config.membershipConfiguration().carouselInterval == 0)
    #expect(config.page(for: "vip")?.displayedBenefits.first?.timeInterval == 0)
}
