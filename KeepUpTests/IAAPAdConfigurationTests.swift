import Foundation
import Testing
@testable import KeepUp

private let testAdAppID = "ca-app-pub-1234567890123456~1234567890"
private let testAdUnits = ["splash": "ca-app-pub-1234567890123456/1234567890",
                           "insert": "ca-app-pub-1234567890123456/1234567891",
                           "reward": "ca-app-pub-1234567890123456/1234567892"]
private func enabledAdDictionary() -> [String: IAAPConfiguration.JSONValue] {
    var ads: [String: IAAPConfiguration.JSONValue] = ["enabled": .bool(true), "admobAppId": .string(testAdAppID)]
    for (slot, id) in testAdUnits { ads[slot] = .object(["enabled": .bool(true), "oversea": .string(id), "mainland": .string("unused")]) }
    return ads
}
private func rewardPage(type: String = "limited", count: Int = 1, hide: Bool? = nil, giveUp: Bool? = nil,
                        rewardID: String? = testAdUnits["reward"], insertID: String? = testAdUnits["insert"],
                        hideWhenNoAd: Bool? = nil) -> IAAPConfiguration.Page {
    .init(type: type, closeAlpha: nil, priceAlpha: nil, showGiveUp: giveUp,
          iap: .init(pids: [], timeInterval: nil, hidePageControl: nil), hideFuncBtn: hide,
          reward: .init(rewardId: .init(oversea: rewardID), insertId: .init(oversea: insertID),
                        count: count, hideGiveUpWhenNoAd: hideWhenNoAd))
}
private func parsedAds(_ ads: [String: IAAPConfiguration.JSONValue] = enabledAdDictionary(),
                       pages: [IAAPConfiguration.Page] = [], appID: String? = testAdAppID,
                       unitIDs: [String: String] = testAdUnits) -> IAAPAdConfiguration {
    .init(configuration: .init(system: [:], ads: ads, skus: [], iaaps: pages), expectedAppID: appID, expectedUnitIDs: unitIDs)
}

@Test func iaapAdsRequiresExplicitGlobalAndPlacementEnablement() {
    var ads = enabledAdDictionary()
    ads.removeValue(forKey: "enabled")
    #expect(parsedAds(ads, pages: [rewardPage()]) == .disabled)
    ads["enabled"] = .bool(true)
    ads["splash"] = .object(["oversea": .string(testAdUnits["splash"]!), "isAuto": .bool(true)])
    ads["insert"] = .object(["enabled": .bool(false), "oversea": .string(testAdUnits["insert"]!)])
    let value = parsedAds(ads, pages: [rewardPage()])
    #expect(value.appOpenAdUnitID == nil)
    #expect(value.interstitialAdUnitID == nil)
    #expect(value.rewardInterstitialAdUnitID == nil)
    #expect(value.rewardedAdUnitID == testAdUnits["reward"])
    ads["reward"] = .object(["enabled": .bool(false)])
    #expect(parsedAds(ads, pages: [rewardPage()]).rewardedAdUnitID == nil)
}

@Test func iaapAdsMatchesOnlyInjectedIndependentAdMobResources() {
    let pages = [rewardPage(hideWhenNoAd: true)]
    let value = parsedAds(pages: pages)
    #expect(value.enabled)
    #expect(value.appOpenAdUnitID == testAdUnits["splash"])
    #expect(value.interstitialAdUnitID == testAdUnits["insert"])
    #expect(value.rewardedAdUnitID == testAdUnits["reward"])
    #expect(value.rewardInterstitialAdUnitID == testAdUnits["insert"])
    #expect(value.hideGiveUpWhenNoAd)
    #expect(parsedAds(pages: pages, appID: nil) == .disabled)
    #expect(parsedAds(pages: pages, appID: "ca-app-pub-1234567890123456~0000000000") == .disabled)
    #expect(parsedAds(pages: pages, unitIDs: [:]).rewardedAdUnitID == nil)
    let wrongReward = parsedAds(pages: [rewardPage(rewardID: testAdUnits["splash"])])
    #expect(wrongReward.rewardedAdUnitID == nil && wrongReward.rewardInterstitialAdUnitID == nil)
    let wrongInsert = parsedAds(pages: [rewardPage(insertID: testAdUnits["reward"])])
    #expect(wrongInsert.rewardedAdUnitID != nil && wrongInsert.rewardInterstitialAdUnitID == nil)
}

@Test func iaapRewardComesOnlyFromExactLimitedPage() {
    #expect(parsedAds().rewardedAdUnitID == nil)
    #expect(!parsedAds().hideGiveUpWhenNoAd)
    #expect(parsedAds(pages: [rewardPage(type: "vip")]).rewardedAdUnitID == nil)
    #expect(parsedAds(pages: [rewardPage(type: "vip"), rewardPage(hide: true)]).rewardedAdUnitID == nil)
    for page in [rewardPage(count: 0), rewardPage(hide: true), rewardPage(giveUp: true), rewardPage(rewardID: nil)] {
        let value = parsedAds(pages: [page])
        #expect(value.rewardedAdUnitID == nil)
        #expect(value.rewardInterstitialAdUnitID == nil)
        #expect(!value.hideGiveUpWhenNoAd)
    }
    #expect(parsedAds(pages: [rewardPage(hide: false, giveUp: false)]).rewardedAdUnitID != nil)
    #expect(parsedAds(pages: [rewardPage(count: 3)]).rewardCount == 3)
    #expect(parsedAds(pages: [rewardPage(count: 3)]).rewardedAdUnitID != nil)
}

@Test func iaapAdsRejectsMalformedTypesAndIdentifiers() {
    for badEnabled in [IAAPConfiguration.JSONValue.string("true"), .number(1), .null] {
        var ads = enabledAdDictionary()
        ads["enabled"] = badEnabled
        #expect(parsedAds(ads, pages: [rewardPage()]) == .disabled)
    }
    var ads = enabledAdDictionary()
    ads["admobAppId"] = .string("invalid")
    #expect(parsedAds(ads, pages: [rewardPage()], appID: "invalid") == .disabled)
    #expect(parsedAds(pages: [rewardPage(rewardID: "invalid")], unitIDs: ["reward": "invalid"]).rewardedAdUnitID == nil)
    ads = enabledAdDictionary()
    ads["splash"] = .object(["enabled": .bool(true), "mainland": .string(testAdUnits["splash"]!)])
    #expect(parsedAds(ads).appOpenAdUnitID == nil)
}

@Test func iaapPageRewardRoundTripsAndWrongTypesAreRejected() throws {
    var page = rewardPage(type: "limited", hide: false, giveUp: false, hideWhenNoAd: true)
    page.reward = .init(rewardId: .init(mainland: "unused", oversea: testAdUnits["reward"], isAuto: true),
                        insertId: .init(oversea: testAdUnits["insert"], isAuto: false), count: 1, hideGiveUpWhenNoAd: true)
    let config = IAAPConfiguration(system: [:], ads: enabledAdDictionary(), skus: [], iaaps: [rewardPage(type: "vip"), page])
    let data = try JSONEncoder().encode(config)
    let restored = try JSONDecoder().decode(IAAPConfiguration.self, from: data).validated()
    #expect(restored == config)
    #expect(parsedAds(restored.ads, pages: restored.iaaps).rewardedAdUnitID == testAdUnits["reward"])
    for (key, badValue) in [("count", "one"), ("hideGiveUpWhenNoAd", "true")] {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var pages = try #require(object["iaaps"] as? [[String: Any]])
        var reward = try #require(pages[0]["reward"] as? [String: Any])
        reward[key] = badValue
        pages[0]["reward"] = reward
        object["iaaps"] = pages
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(IAAPConfiguration.self, from: malformed) }
    }
}

@Test func iaapLegacyAdsPolicyCannotEnableRewardOrChangeMembershipPage() throws {
    let page = IAAPConfiguration.Page(type: "vip", closeAlpha: 0.5, priceAlpha: 0.5, showGiveUp: true,
                                      iap: .init(pids: [], timeInterval: 5, hidePageControl: false))
    var ads = enabledAdDictionary()
    ads["policy"] = .object(["rewardCount": .number(1), "rewardFeatureIDs": .array([.string("stepGoal")]),
                              "coldStart": .bool(true), "afterReward": .bool(true)])
    let config = IAAPConfiguration(system: [:], ads: ads, skus: [], iaaps: [page])
    // Both cached and remote JSON use this decoder. Preserve unknown fields without executing them.
    let restored = try JSONDecoder().decode(IAAPConfiguration.self, from: JSONEncoder().encode(config)).validated()
    #expect(restored.ads["policy"] == ads["policy"])
    #expect(restored.page(for: "vip") == page)
    #expect(restored.page(for: "limited") == nil)
    #expect(restored.page(for: "limited")?.reward == nil)
    let mapped = parsedAds(restored.ads, pages: restored.iaaps)
    #expect(mapped.rewardedAdUnitID == nil)
    #expect(mapped.rewardInterstitialAdUnitID == nil)
    #expect(!mapped.hideGiveUpWhenNoAd)
    var withoutPolicy = ads
    withoutPolicy.removeValue(forKey: "policy")
    #expect(mapped == parsedAds(withoutPolicy, pages: [page]))
}

@Test func iaapMissingLimitedNeverUsesOtherEntryRewards() {
    let otherPages = ["guide", "launch", "vip"].map { rewardPage(type: $0, hideWhenNoAd: true) }
    let value = parsedAds(pages: otherPages)
    #expect(value.rewardedAdUnitID == nil)
    #expect(value.rewardInterstitialAdUnitID == nil)
    #expect(!value.hideGiveUpWhenNoAd)
    let limited = rewardPage(rewardID: testAdUnits["reward"], insertID: nil, hideWhenNoAd: false)
    let exact = parsedAds(pages: otherPages + [limited])
    #expect(exact.rewardedAdUnitID == testAdUnits["reward"])
    #expect(exact.rewardInterstitialAdUnitID == nil)
    #expect(!exact.hideGiveUpWhenNoAd)
}

@Test func iaapRewardEnabledFlagsPreserveIDsAndRespectGlobalSwitches() throws {
    func page(reward: Bool?, video: Bool?, insert: Bool?) -> IAAPConfiguration.Page {
        var value = rewardPage()
        value.reward = .init(rewardId: .init(oversea: testAdUnits["reward"], enabled: video),
                             insertId: .init(oversea: testAdUnits["insert"], enabled: insert),
                             count: 1, enabled: reward)
        return value
    }
    let legacy = parsedAds(pages: [page(reward: nil, video: nil, insert: nil)])
    #expect(legacy.rewardedAdUnitID != nil && legacy.rewardInterstitialAdUnitID != nil)
    for disabled in [page(reward: false, video: true, insert: true), page(reward: true, video: false, insert: true)] {
        let restored = try JSONDecoder().decode(IAAPConfiguration.Page.self, from: JSONEncoder().encode(disabled))
        #expect(restored == disabled)
        let result = parsedAds(pages: [restored])
        #expect(result.rewardedAdUnitID == nil && result.rewardInterstitialAdUnitID == nil)
        #expect(result.appOpenAdUnitID != nil && result.interstitialAdUnitID != nil)
        #expect(restored.reward?.rewardId.oversea == testAdUnits["reward"])
    }
    let videoOnly = parsedAds(pages: [page(reward: true, video: true, insert: false)])
    #expect(videoOnly.rewardedAdUnitID != nil && videoOnly.rewardInterstitialAdUnitID == nil)
    var ads = enabledAdDictionary()
    ads["enabled"] = .bool(false)
    #expect(parsedAds(ads, pages: [page(reward: true, video: true, insert: true)]).rewardedAdUnitID == nil)
}
