import Foundation
import Observation

@MainActor @Observable
final class IAAPConfigurationStore {
    enum Source: String { case bundled, cache, remote }
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private struct Cache: Codable {
        let sourceURL: String?
        let configuration: IAAPConfiguration
        let knownSKUs: [IAAPConfiguration.SKU]
    }
    private(set) var configuration: IAAPConfiguration
    private(set) var knownSKUs: [String: IAAPConfiguration.SKU]
    private(set) var source: Source = .bundled
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    let remoteURL: URL?
    private let cacheURL: URL?
    private let fetch: Fetch

    var entitlementProductIDs: Set<String> {
        Set(knownSKUs.values.filter(\.grantsMembership).map(\.pid))
    }

    /// Set this optional Info.plist value only after the KeepUp OSS URL is available.
    nonisolated static var configuredRemoteURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KeepUpIAAPConfigurationURL") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: value)
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KeepUp/iaap-cache-v1.json")
    }

    init(remoteURL: URL? = nil, cacheURL: URL? = IAAPConfigurationStore.defaultCacheURL,
         bundledData: Data? = nil, session: URLSession? = nil, fetch: Fetch? = nil) {
        self.remoteURL = remoteURL
        self.cacheURL = cacheURL
        if let fetch { self.fetch = fetch }
        else if let session { self.fetch = { try await session.data(for: $0) } }
        else { self.fetch = HTTPClient.liveFetch }
        let data = bundledData ?? Bundle.main.url(forResource: "iaap", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        let bundled = data.flatMap { try? JSONPayloadCodec().decode(IAAPConfiguration.self, from: $0).validated() } ?? .empty
        configuration = bundled
        knownSKUs = Dictionary(uniqueKeysWithValues: bundled.skus.map { ($0.pid, $0) })
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count <= 1_048_576,
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           Set(cache.knownSKUs.map(\.pid)).count == cache.knownSKUs.count,
           cache.knownSKUs.allSatisfy({ IAAPConfiguration.isKeepUpProductID($0.pid) }),
           Set(cache.configuration.skus.map(\.pid)).count == cache.configuration.skus.count,
           cache.configuration.skus.allSatisfy({ IAAPConfiguration.isKeepUpProductID($0.pid) }) {
            var catalog = knownSKUs
            var consistent = true
            for sku in cache.knownSKUs + cache.configuration.skus {
                if let old = catalog[sku.pid], old.type != sku.type { consistent = false }
                catalog[sku.pid] = sku
            }
            if consistent {
                // History belongs to this app, but presentation belongs to its configured endpoint.
                knownSKUs = catalog
                // Page-schema migrations must never erase a valid historical SKU catalog.
                if cache.sourceURL == remoteURL?.absoluteString,
                   let valid = try? cache.configuration.validated() {
                    configuration = valid
                    source = .cache
                }
            }
        }
    }

    /// A missing URL is intentional until the independently managed OSS endpoint is supplied.
    func refresh() async {
        guard !isRefreshing, let remoteURL else { return }
        guard Self.isHTTPS(remoteURL) else { lastError = String(describing: IAAPConfigurationError.invalidURL); return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let requestURL = try Self.cacheBustingURL(for: remoteURL)
            var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data = try await HTTPClient(fetch: fetch).data(for: request)
            let candidate = try JSONDecoder().decode(IAAPConfiguration.self, from: data).validated()
            var catalog = knownSKUs
            for sku in candidate.skus {
                if let old = catalog[sku.pid], old.type != sku.type { throw IAAPConfigurationError.conflictingProductType }
                catalog[sku.pid] = sku
            }
            // Persist the full accepted state atomically; invalid downloads never touch the cache.
            if let cacheURL {
                let cache = Cache(sourceURL: remoteURL.absoluteString, configuration: candidate, knownSKUs: catalog.values.sorted { $0.pid < $1.pid })
                let encoded = try JSONEncoder().encode(cache)
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoded.write(to: cacheURL, options: .atomic)
            }
            configuration = candidate
            knownSKUs = catalog
            source = .remote
            lastError = nil
        } catch { lastError = String(describing: error) }
    }

    /// Keep the endpoint identity stable; only the individual network request carries a timestamp.
    nonisolated static func cacheBustingURL(for url: URL, now: Date = .now) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IAAPConfigurationError.invalidURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "v" }
        items.append(URLQueryItem(name: "v", value: String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))))
        components.queryItems = items
        guard let result = components.url else { throw IAAPConfigurationError.invalidURL }
        return result
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host?.isEmpty ?? true) && url.user == nil && url.password == nil
    }
}
