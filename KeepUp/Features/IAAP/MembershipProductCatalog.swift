import Foundation
import Observation

/// Shared product details, with each product ID owned by at most one in-flight request.
@MainActor @Observable final class MembershipProductCatalog<Value: Sendable> {
    private(set) var values: [String: Value] = [:]
    private(set) var loadingIDs: Set<String> = []
    @ObservationIgnored private let fetch: @MainActor ([String]) async throws -> [String: Value]
    @ObservationIgnored private var pending: [String: Task<Set<String>, Error>] = [:]

    init(fetch: @escaping @MainActor ([String]) async throws -> [String: Value]) { self.fetch = fetch }
    func isPrepared(_ ids: Set<String>) -> Bool { ids.isSubset(of: Set(values.keys)) }

    @discardableResult func load(_ ids: Set<String>, cache: Bool = true) async throws -> [String: Value] {
        var remaining = cache ? ids.subtracting(values.keys) : ids
        while !remaining.isEmpty {
            if cache { remaining.subtract(values.keys) }
            guard !remaining.isEmpty else { break }
            // Re-evaluate ownership after every suspension, including partial overlaps.
            if let work = remaining.compactMap({ pending[$0] }).first {
                remaining.subtract(try await work.value)
                continue
            }
            let requested = remaining
            let work = Task { [self, fetch] in
                defer {
                    for id in requested { pending[id] = nil }
                    loadingIDs.subtract(requested)
                }
                let loaded = try await fetch(requested.sorted())
                // Only the owner writes. Waiters never write old results back into the cache.
                for id in requested { values[id] = loaded[id] }
                return requested
            }
            for id in requested { pending[id] = work }
            loadingIDs.formUnion(requested)
            remaining.subtract(try await work.value)
        }
        return values.filter { ids.contains($0.key) }
    }
}
