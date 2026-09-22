import Foundation
import Testing
@testable import KeepUp

@MainActor struct MembershipProductCatalogTests {
    @Test func pagesShareDetailsAndReloadDoesNotEraseOtherProducts() async throws {
        var calls = 0
        let response = ProductResponses()
        let catalog = MembershipProductCatalog<String> { ids in calls += 1; return response.values.filter { ids.contains($0.key) } }
        try await catalog.load(["year", "life"])
        try await catalog.load(["life"])
        #expect(calls == 1 && catalog.isPrepared(["year", "life"]))
        response.values = [:]
        try await catalog.load(["life"], cache: false)
        #expect(catalog.values["life"] == nil && catalog.values["year"] != nil)
    }

    @Test func concurrentRequestsJoinAndRetryAfterFailure() async throws {
        var calls = 0
        var suspended: CheckedContinuation<[String: String], Error>?
        let catalog = MembershipProductCatalog<String> { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { suspended = $0 }
        }
        let first = Task { try await catalog.load(["a"]) }
        while suspended == nil { await Task.yield() }
        let second = Task { try await catalog.load(["a"]) }
        await Task.yield()
        suspended?.resume(returning: ["a": "details"])
        _ = try await first.value
        _ = try await second.value
        #expect(calls == 1 && catalog.loadingIDs.isEmpty)
        suspended = nil
        let failed = Task { try await catalog.load(["a"], cache: false) }
        while suspended == nil { await Task.yield() }
        suspended?.resume(throwing: URLError(.notConnectedToInternet))
        do { _ = try await failed.value; Issue.record("Expected failure") } catch {}
        #expect(catalog.values["a"] == "details" && catalog.loadingIDs.isEmpty)
        suspended = nil
        let retry = Task { try await catalog.load(["a"], cache: false) }
        while suspended == nil { await Task.yield() }
        suspended?.resume(returning: ["a": "new details"])
        _ = try await retry.value
        #expect(calls == 3 && catalog.values["a"] == "new details")
    }
    @Test func partiallyOverlappingRequestsNeverFetchAnIDTwice() async throws {
        var calls: [[String]] = []
        var waiting: [([String], CheckedContinuation<[String: String], Error>)] = []
        var completed = 0
        let catalog = MembershipProductCatalog<String> { ids in
            calls.append(ids)
            return try await withCheckedThrowingContinuation { waiting.append((ids, $0)) }
        }
        let first = Task { try await catalog.load(["x"]); completed += 1 }
        while waiting.isEmpty { await Task.yield() }
        let second = Task { try await catalog.load(["x", "y"]); completed += 1 }
        let third = Task { try await catalog.load(["x", "y", "z"]); completed += 1 }
        for _ in 0..<20 { await Task.yield() }
        for _ in 0..<1000 where completed < 3 {
            if !waiting.isEmpty {
                let (ids, continuation) = waiting.removeFirst()
                continuation.resume(returning: Dictionary(uniqueKeysWithValues: ids.map { ($0, "details-" + $0) }))
            }
            await Task.yield()
        }
        #expect(completed == 3)
        try await first.value; try await second.value; try await third.value
        #expect(calls.flatMap { $0 }.sorted() == ["x", "y", "z"])
        #expect(catalog.loadingIDs.isEmpty && catalog.isPrepared(["x", "y", "z"]))
    }

}

@MainActor private final class ProductResponses {
    var values = ["year": "year details", "life": "life details"]
}
