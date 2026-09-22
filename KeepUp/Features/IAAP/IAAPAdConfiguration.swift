import Foundation

/// KeepUp deliberately supports only its independently verified AdMob resources.
/// `mainland`, `gromoreAppId`, and `isAuto` never select a network or enable a placement.
struct IAAPAdConfiguration: Equatable, Sendable {
    let rewardCount: Int
    let enabled: Bool
    let appOpenAdUnitID: String?
    let interstitialAdUnitID: String?
    let rewardedAdUnitID: String?
    let rewardInterstitialAdUnitID: String?
    let hideGiveUpWhenNoAd: Bool

    static let disabled = Self(configuration: .empty, expectedAppID: nil, expectedUnitIDs: [:])

    init(configuration: IAAPConfiguration, expectedAppID: String?, expectedUnitIDs: [String: String]) {
        let ads = configuration.ads
        let appID = Self.string(ads["admobAppId"])
        enabled = ads["enabled"] == .bool(true)
            && appID != nil && appID == expectedAppID
            && Self.matches(appID, pattern: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#)
            && Self.optionalStringIsValid(ads["gromoreAppId"])

        let page = configuration.page(for: "limited")
        if enabled, page?.hideFuncBtn != true, page?.showGiveUp != true,
           let reward = page?.reward, reward.enabled != false, reward.count > 0,
           let id = Self.pageUnitID(reward.rewardId, slot: "reward", ads: ads, expectedIDs: expectedUnitIDs) {
            rewardCount = reward.count
            rewardedAdUnitID = id
            rewardInterstitialAdUnitID = Self.pageUnitID(reward.insertId, slot: "insert", ads: ads, expectedIDs: expectedUnitIDs)
            hideGiveUpWhenNoAd = reward.hideGiveUpWhenNoAd ?? false
        } else {
            rewardCount = 0
            rewardedAdUnitID = nil
            rewardInterstitialAdUnitID = nil
            hideGiveUpWhenNoAd = false
        }
        appOpenAdUnitID = Self.unitID("splash", ads: ads, enabled: enabled, expectedIDs: expectedUnitIDs)
        interstitialAdUnitID = Self.unitID("insert", ads: ads, enabled: enabled, expectedIDs: expectedUnitIDs)
    }

    private static func pageUnitID(_ value: IAAPConfiguration.Page.AdSlotID, slot: String,
                                   ads: [String: IAAPConfiguration.JSONValue], expectedIDs: [String: String]) -> String? {
        guard value.enabled != false, case .object(let globalSlot) = ads[slot], globalSlot["enabled"] == .bool(true),
              let id = value.oversea, id == expectedIDs[slot],
              matches(id, pattern: #"^ca-app-pub-[0-9]{16}/[0-9]{10}$"#) else { return nil }
        return id
    }

    private static func unitID(_ slot: String, ads: [String: IAAPConfiguration.JSONValue], enabled: Bool,
                               expectedIDs: [String: String]) -> String? {
        guard enabled, case .object(let value) = ads[slot], value["enabled"] == .bool(true),
              optionalStringIsValid(value["mainland"]),
              let id = string(value["oversea"]), id == expectedIDs[slot],
              matches(id, pattern: #"^ca-app-pub-[0-9]{16}/[0-9]{10}$"#) else { return nil }
        return id
    }

    private static func string(_ value: IAAPConfiguration.JSONValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }
    private static func optionalStringIsValid(_ value: IAAPConfiguration.JSONValue?) -> Bool {
        value == nil || string(value) != nil
    }
    private static func matches(_ value: String?, pattern: String) -> Bool {
        value?.range(of: pattern, options: .regularExpression) != nil
    }
}
