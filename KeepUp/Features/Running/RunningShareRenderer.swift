import SwiftUI
import UIKit
import ImageIO

final class RunningShareArtifact: Identifiable {
    let id = UUID()
    enum MapStatus: Equatable { case map, schematic, empty, notNeeded }
    struct Page: Identifiable {
        let id: Int
        let url: URL
        let size: CGSize

        /// Preserve readable text at the displayed width, including on tall pages.
        /// Only visible pages keep their decoded images in the preview.
        @MainActor func previewImage() -> UIImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(ceil(780 * max(size.width, size.height) / max(size.width, 1))),
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
    }
    let pages: [Page]
    let mapStatus: MapStatus
    let splitIDsByPage: [[Int]]
    private let directory: URL

    init(pages: [Page], mapStatus: MapStatus, splitIDsByPage: [[Int]], directory: URL) {
        self.pages = pages; self.mapStatus = mapStatus; self.splitIDsByPage = splitIDsByPage; self.directory = directory
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

enum RunningShareRenderError: Error { case imageUnavailable }

@MainActor final class RunningShareRenderer {
    static let splitsPerPage = 20
    private let snapshotSource: any RunningShareSnapshotSource

    init(snapshotSource: any RunningShareSnapshotSource = SystemRunningShareSnapshotSource()) {
        self.snapshotSource = snapshotSource
    }

    func render(session: RunningSession, locale: Locale, satellite: Bool = false) async throws -> RunningShareArtifact {
        let metrics = RunningMetrics(session: session)
        let route = RunningShareRoute(session: session)
        let status: RunningShareArtifact.MapStatus
        let mapImage: UIImage?
        if !session.kind.usesGPS {
            status = .notNeeded; mapImage = nil
        } else if route.isEmpty {
            status = .empty; mapImage = nil
        } else if let snapshot = await snapshotSource.snapshot(route: route, size: CGSize(width: 342, height: 230), satellite: satellite) {
            status = .map; mapImage = snapshot
        } else {
            try Task.checkCancellation()
            status = .schematic
            mapImage = RunningShareMapDrawing.schematic(route: route, size: CGSize(width: 342, height: 230), locale: locale)
        }
        try Task.checkCancellation()
        let pages = Self.splitPages(metrics.splits)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("running-share-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var exported: [RunningShareArtifact.Page] = []
        do {
        for (index, splits) in pages.enumerated() {
            try Task.checkCancellation()
            let page: RunningShareArtifact.Page = try autoreleasepool {
            let poster = RunningSharePoster(session: session, metrics: metrics, mapImage: mapImage,
                                            splits: splits, page: index, pageCount: pages.count)
                .environment(\.locale, locale)
                .environment(\.timeZone, TimeZone(identifier: session.timeZoneID) ?? .current)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .medium)
                .frame(width: 390)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: poster)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
            guard let image = renderer.uiImage else { throw RunningShareRenderError.imageUnavailable }
            guard let data = image.pngData() else { throw RunningShareRenderError.imageUnavailable }
            let url = directory.appendingPathComponent(String(format: "KeepUp-%03d.png", index + 1))
            try data.write(to: url, options: .atomic)
            return RunningShareArtifact.Page(id: index, url: url, size: image.size)
            }
            exported.append(page)
            await Task.yield()
        }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return RunningShareArtifact(pages: exported, mapStatus: status, splitIDsByPage: pages.map { $0.map(\.id) }, directory: directory)
    }

    static func splitPages(_ splits: [RunningMetricSplit]) -> [[RunningMetricSplit]] {
        guard !splits.isEmpty else { return [[]] }
        return stride(from: 0, to: splits.count, by: splitsPerPage).map { start in
            Array(splits[start..<min(start + splitsPerPage, splits.count)])
        }
    }
}

/// A naturally sized stack, never a screenshot of a ScrollView. Every row is laid out before rendering.
private struct RunningSharePoster: View {
    let session: RunningSession
    let metrics: RunningMetrics
    let mapImage: UIImage?
    let splits: [RunningMetricSplit]
    let page: Int
    let pageCount: Int
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("KeepUp").font(.system(size: 24, weight: .semibold))
                Spacer()
                Text(LocalizedStringKey(session.kind.titleKey)).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(RunningDetailStyle.color(session.kind))
            }
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
            if page == 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RunningDisplay.distance(metrics.distanceMeters, locale: locale))
                        .font(.system(size: 54, weight: .light)).monospacedDigit()
                    Text("running.kilometers").font(.system(size: 14)).foregroundStyle(.secondary)
                }.padding(.top, 22)
                HStack(alignment: .top, spacing: 12) {
                    metric(RunningDisplay.duration(metrics.elapsedSeconds), title: "running.duration")
                    metric(metrics.roundedEnergyKilocalories.map { $0.formatted(.number.locale(locale)) } ?? "—", title: "runningShare.energy")
                }.padding(.top, 20)
                HStack(alignment: .top, spacing: 12) {
                    if session.kind == .cycling {
                        metric(RunningDetailStyle.number(metrics.averageSpeedKilometersPerHour, locale: locale, digits: 1), title: "running.averageSpeed")
                    } else {
                        metric(metrics.averagePaceSecondsPerKilometer.map(RunningDisplay.paceSeconds) ?? "—", title: "running.averagePace")
                    }
                    if session.kind == .indoor {
                        metric(session.steps.formatted(.number.locale(locale)), title: "running.steps")
                    }
                }.padding(.top, 20).padding(.bottom, 24)
                if session.kind.usesGPS {
                    if let mapImage {
                        Image(uiImage: mapImage).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("running.noRoute").font(.system(size: 14)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 130)
                            .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    metric(RunningDisplay.cadence(steps: session.steps, seconds: metrics.elapsedSeconds, locale: locale), title: "running.averageCadence")
                    Text("running.indoorDistanceHint").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                }
                RunningChartsSection(session: session, metrics: metrics)
            }
            RunningSplitsSection(session: session, metrics: metrics, alwaysExpanded: true, displayedSplits: splits)
            Divider()
            HStack {
                Text("runningShare.footer")
                Spacer()
                if pageCount > 1 { Text("\(page + 1) / \(pageCount)").monospacedDigit() }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 18)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(hex: 0x222222)).background(.white)
    }

    private func metric(_ value: String, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: value).font(.system(size: 24, weight: .light)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
