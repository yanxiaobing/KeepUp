import Foundation
import UIKit
import Testing
@testable import KeepUp

@MainActor private final class FakeRunningShareSnapshotSource: RunningShareSnapshotSource {
    var calls = 0
    var satellites: [Bool] = []
    var succeeds = false
    func snapshot(route: RunningShareRoute, size: CGSize, satellite: Bool) async -> UIImage? {
        calls += 1
        satellites.append(satellite)
        guard succeeds else { return nil }
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.lightGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private func shareFixture(kind: RunningKind = .outdoor, kilometers: Int = 2, tail: Double = 350, route: Bool = true) -> RunningSession {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var session = RunningSession(id: "share-fixture", startedAt: start, timeZone: TimeZone(secondsFromGMT: 0)!, kind: kind)
    session.distanceMeters = Double(kilometers) * 1_000 + tail
    session.splits = (0..<kilometers).map { RunningSplit(kilometer: $0 + 1, elapsedSeconds: 300) }
    session.steps = kind == .indoor ? Int(session.distanceMeters * 1.2) : 0
    if route && kind.usesGPS {
        session.segments = [[
            RunningPoint(latitude: 37.33, longitude: -122.03, horizontalAccuracy: 5, timestamp: start, speed: 3),
            RunningPoint(latitude: 37.3303, longitude: -122.03, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(10), speed: 3)
        ], [
            RunningPoint(latitude: 37.3306, longitude: -122.03, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(60), speed: 3),
            RunningPoint(latitude: 37.3309, longitude: -122.03, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(70), speed: 3)
        ]]
    }
    session.finish(at: start.addingTimeInterval(session.distanceMeters * 0.3))
    return session
}

@Test @MainActor func runningShareAllModesRenderInEnglishAndIndoorSkipsSnapshot() async throws {
    for kind in RunningKind.allCases {
        let source = FakeRunningShareSnapshotSource(); source.succeeds = true
        let session = shareFixture(kind: kind)
        let result = try await RunningShareRenderer(snapshotSource: source).render(session: session, locale: Locale(identifier: "en"), satellite: true)
        #expect(source.calls == (kind.usesGPS ? 1 : 0))
        #expect(result.mapStatus == (kind.usesGPS ? .map : .notNeeded))
        #expect(result.pages.count == 1)
        let page = try #require(result.pages.first)
        #expect(page.size.width == 390)
        #expect(page.size.height > 600)
        #expect(page.previewImage()?.cgImage?.width == 780)
        Attachment.record(Array(try Data(contentsOf: page.url)), named: "running-share-\(kind.rawValue)-en.png")
        #expect(FileManager.default.fileExists(atPath: page.url.path))
        #expect(localized(kind.titleKey, Locale(identifier: "en")) != kind.titleKey)
        #expect(result.splitIDsByPage.flatMap { $0 } == [1, 2, 3])
    }
}

@Test @MainActor func runningShareEmptyGPSDoesNotRequestNetworkOrInventRoute() async throws {
    let source = FakeRunningShareSnapshotSource()
    let result = try await RunningShareRenderer(snapshotSource: source).render(session: shareFixture(route: false), locale: Locale(identifier: "zh-Hans"))
    #expect(source.calls == 0)
    #expect(result.mapStatus == .empty)
    Attachment.record(Array(try Data(contentsOf: result.pages[0].url)), named: "running-share-empty-route-zh.png")
    #expect(result.pages.count == 1)
    #expect(result.pages[0].previewImage() != nil)
}

@Test @MainActor func runningShareMapFailureExportsSchematicAndRetryCanReplaceIt() async throws {
    let source = FakeRunningShareSnapshotSource()
    let renderer = RunningShareRenderer(snapshotSource: source)
    let session = shareFixture(kind: .cycling)
    let fallback = try await renderer.render(session: session, locale: Locale(identifier: "en"))
    #expect(fallback.mapStatus == .schematic)
    #expect(fallback.pages[0].previewImage() != nil)
    Attachment.record(Array(try Data(contentsOf: fallback.pages[0].url)), named: "running-share-schematic-en.png")
    source.succeeds = true
    let retry = try await renderer.render(session: session, locale: Locale(identifier: "en"), satellite: true)
    #expect(retry.mapStatus == .map)
    #expect(source.calls == 2)
    #expect(source.satellites == [false, true])
    #expect(fallback.splitIDsByPage == retry.splitIDsByPage)
    // Retry creates an independent artifact: an already presented share keeps its files.
    #expect(FileManager.default.fileExists(atPath: fallback.pages[0].url.path))
}

@Test @MainActor func runningShareLongWorkoutExportsEverySplitAndTailAcrossPages() async throws {
    let source = FakeRunningShareSnapshotSource()
    let session = shareFixture(kind: .indoor, kilometers: 43)
    let result = try await RunningShareRenderer(snapshotSource: source).render(session: session, locale: Locale(identifier: "en"))
    #expect(result.pages.count == 3)
    for page in result.pages {
        Attachment.record(Array(try Data(contentsOf: page.url)), named: "running-share-long-en-\(page.id + 1).png")
    }
    #expect(result.splitIDsByPage.map(\.count) == [20, 20, 4])
    #expect(result.splitIDsByPage.flatMap { $0 } == Array(1...44))
    #expect(result.pages.allSatisfy { $0.size.height > 400 && $0.size.height < 4_000 })
    #expect(result.pages.allSatisfy { $0.previewImage()?.cgImage?.width == 780 })
    #expect(source.calls == 0)
}

@Test @MainActor func runningShareMaximumDistancePaginationDoesNotDropRows() {
    let metrics = RunningMetrics(session: shareFixture(kind: .cycling, kilometers: 1_000, tail: 0, route: false))
    let pages = RunningShareRenderer.splitPages(metrics.splits)
    #expect(pages.count == 50)
    #expect(pages.allSatisfy { $0.count == 20 })
    #expect(pages.flatMap { $0 }.map(\.id) == Array(1...1_000))
}

@Test @MainActor func runningShareArtifactsCleanUpOnlyWhenReleased() async throws {
    let source = FakeRunningShareSnapshotSource()
    var artifact: RunningShareArtifact? = try await RunningShareRenderer(snapshotSource: source).render(session: shareFixture(kind: .indoor), locale: Locale(identifier: "en"))
    let url = try #require(artifact?.pages.first?.url)
    #expect(FileManager.default.fileExists(atPath: url.path))
    artifact = nil
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test @MainActor func runningShareRouteUnwrapsDateLineAndKeepsPauseSegments() {
    var session = shareFixture()
    session.segments[0][0].longitude = 179.999
    session.segments[0][1].longitude = -179.999
    session.segments[1][0].longitude = -179.998
    session.segments[1][1].longitude = -179.997
    let original = session.segments
    let route = RunningShareRoute(session: session)
    #expect(route.segments.count == 2)
    #expect(route.mapRect(for: CGSize(width: 342, height: 230)).size.width < 100_000)
    #expect(session.segments == original)
}
