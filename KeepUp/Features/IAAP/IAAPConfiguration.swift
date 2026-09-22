import Foundation

/// The shared IAAP envelope. Platform-specific fields are preserved without enabling them.
struct IAAPConfiguration: Codable, Equatable, Sendable {
    enum JSONValue: Codable, Equatable, Sendable {
        case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Double.self) { self = .number(v) }
            else if let v = try? c.decode(String.self) { self = .string(v) }
            else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
            else { self = .object(try c.decode([String: JSONValue].self)) }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .null: try c.encodeNil()
            case .bool(let v): try c.encode(v)
            case .number(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            case .array(let v): try c.encode(v)
            case .object(let v): try c.encode(v)
            }
        }
    }
    struct SKU: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case lifetime, subscribe, consumable }
        let pid: String
        let type: Kind
        let titleType: String?
        var desc: String? = nil
        var grantsMembership: Bool { type == .lifetime || type == .subscribe }
    }
    struct Page: Codable, Equatable, Sendable {
        struct Benefit: Codable, Equatable, Sendable {
            var type: String? = nil
            var footer: Double? = nil
            var items: [String]? = nil
            var timeInterval: Double? = nil
            var hidePageControl: Bool? = nil

            static let defaults: [Self] = [
                .init(type: "themes", footer: 30),
                .init(type: "noad", footer: 50)
            ]
        }
        struct AdSlotID: Codable, Equatable, Sendable {
            var mainland: String? = nil
            var oversea: String? = nil
            var isAuto: Bool? = nil
            var enabled: Bool? = nil
        }
        struct Reward: Codable, Equatable, Sendable {
            let rewardId: AdSlotID
            let insertId: AdSlotID
            let count: Int
            var hideGiveUpWhenNoAd: Bool? = nil
            var enabled: Bool? = nil
        }
        struct IAP: Codable, Equatable, Sendable {
            let pids: [String]
            let timeInterval: Double?
            let hidePageControl: Bool?
        }
        let type: String
        let closeAlpha: Double?
        let priceAlpha: Double?
        let showGiveUp: Bool?
        let iap: IAP
        /// Human-readable scene metadata; routing always uses type.
        var place: String? = nil
        var hideFuncBtn: Bool? = nil
        var reward: Reward? = nil
        var benefits: [Benefit]? = nil

        /// An explicit empty list hides all sections. Unknown modules remain round-trippable.
        var displayedBenefits: [Benefit] {
            (benefits ?? Benefit.defaults).filter { ["themes", "noad", "cloud"].contains($0.type ?? "") }
        }
    }
    let system: [String: JSONValue]
    let ads: [String: JSONValue]
    let skus: [SKU]
    let iaaps: [Page]

    static let empty = Self(system: [:], ads: [:], skus: [], iaaps: [])

    func page(for entry: String) -> Page? {
        iaaps.first { $0.type == entry }
    }
    func displayedSKUs(for entry: String) -> [SKU] {
        let catalog = Dictionary(uniqueKeysWithValues: skus.map { ($0.pid, $0) })
        return page(for: entry)?.iap.pids.compactMap { catalog[$0] } ?? []
    }
    func validated() throws -> Self {
        guard Set(skus.map(\.pid)).count == skus.count,
              skus.allSatisfy({ Self.isKeepUpProductID($0.pid) }),
              Set(iaaps.map(\.type)).count == iaaps.count,
              iaaps.allSatisfy({ ["guide", "launch", "limited", "vip"].contains($0.type) }),
              iaaps.contains(where: { $0.type == "vip" }) else { throw IAAPConfigurationError.invalidConfiguration }
        let ids = Set(skus.map(\.pid))
        for page in iaaps {
            guard (page.benefits ?? []).allSatisfy({ benefit in
                (benefit.footer.map { $0.isFinite && (0...2000).contains($0) } ?? true)
                    && (benefit.timeInterval.map { $0.isFinite && $0 >= 0 && $0 <= 3600 } ?? true)
            }), !page.type.isEmpty,
                  Set(page.iap.pids).count == page.iap.pids.count,
                  Set(page.iap.pids).isSubset(of: ids),
                  [page.closeAlpha, page.priceAlpha].allSatisfy({ $0.map { $0.isFinite && (0...1).contains($0) } ?? true }),
                  page.iap.timeInterval.map({ $0.isFinite && $0 >= 0 && $0 <= 3600 }) ?? true else {
                throw IAAPConfigurationError.invalidConfiguration
            }
        }
        return self
    }
    static func isKeepUpProductID(_ id: String) -> Bool {
        id.hasPrefix("com.bestlife.keepup.") && id.count > "com.bestlife.keepup.".count && !id.contains(where: \.isWhitespace)
    }
}

enum IAAPConfigurationError: Error, Equatable {
    case invalidConfiguration, invalidURL, invalidResponse, oversizedResponse, conflictingProductType
}
