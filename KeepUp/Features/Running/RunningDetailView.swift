import SwiftUI
import MapKit

struct RunningDetailView: View {
    let session: RunningSession
    var entry: CheckInEntry? = nil
    var card: HabitCard? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var showingMap = false
    @State private var editing = false
    @State private var shareStyle: RunningShareStyle?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    private var currentEntry: CheckInEntry? {
        guard let entry else { return nil }
        return model.snapshot.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        NavigationStack {
            RunningResultPages(session: session, content: currentEntry.map { model.snapshot.publishedContent(for: $0) },
                               page: $page, showingMap: $showingMap)
                .navigationTitle(session.kind == .cycling ? "runningDetail.cyclingTitle" : "runningDetail.runningTitle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(CalendarTheme.selected.color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("action.close")).accessibilityIdentifier("running.result.close")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if currentEntry != nil && card != nil {
                            Button { editing = true } label: { Image(systemName: KeepUpStyle.editContentSymbol) }
                                .accessibilityLabel(Text("content.edit"))
                                .accessibilityIdentifier("running.detail.editContent")
                        }
                        Button { shareStyle = RunningShareStyle(page: page) } label: {
                            Image("card_detail_ic_share").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24)
                        }.accessibilityLabel(Text("entry.share")).accessibilityIdentifier("running.detail.share")
                    }
                }
                .fullScreenCover(isPresented: $editing) {
                    if let currentEntry, let card { EntryContentEditor(entry: currentEntry, card: card) }
                }
                .sheet(item: $shareStyle) { style in RunningShareView(session: session, style: style) }
                .fullScreenCover(isPresented: $showingMap) { RunningDetailMapView(session: session) }
                .confirmationDialog("entry.deleteConfirmation", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("action.delete", role: .destructive) { Task { await deleteRecord() } }
                        .accessibilityIdentifier("running.detail.confirmDelete")
                    Button("action.cancel", role: .cancel) {}
                }
                .alert("error.title", isPresented: $deleteFailed) {
                    Button("action.ok", role: .cancel) {}
                } message: { Text("error.storage") }
        }
    }

    private func deleteRecord() async {
        guard let currentEntry, !deleting else { return }
        deleting = true
        model.actionError = nil
        await model.delete(currentEntry)
        deleting = false
        if model.actionError == nil { dismiss() }
        else { model.actionError = nil; deleteFailed = true }
    }
}

struct RunningResultPages: View {
    let session: RunningSession
    var content: EntryContent? = nil
    @Binding var page: Int
    @Binding var showingMap: Bool

    var body: some View {
        GeometryReader { geometry in
            let cityHeight = geometry.size.width * 272 / 750
            TabView(selection: $page) {
                RunningResultOverview(session: session, showingMap: $showingMap).tag(0)
                RunningSessionSummary(session: session, content: content, bottomPadding: cityHeight + 16).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(alignment: .top) {
                CardDetailThemeBackground()
                    .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.bottom)
            }
            .overlay(alignment: .bottom) {
                if page == 1 {
                    RunningDetailCityOverlay(width: geometry.size.width, height: cityHeight)
                        .offset(y: geometry.safeAreaInsets.bottom)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { index in
                        Button { page = index } label: {
                            Circle().fill(page == index ? Color(hex: 0x48484D) : Color(hex: 0xC1C1C1))
                                .frame(width: 6, height: 6)
                                .frame(width: 12, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(LocalizedStringKey(index == 0 ? (session.kind.usesGPS ? "runningDetail.routePage" : "running.result") : "runningDetail.detailsPage")))
                        .accessibilityIdentifier("running.page.\(index)")
                        .accessibilityAddTraits(page == index ? .isSelected : [])
                    }
                }.padding(.trailing, 15)
            }
        }.background(.white)
    }
}

// The result pages separate the route or indoor result from the statistics.
struct RunningSessionSummary: View {
    let session: RunningSession
    var content: EntryContent? = nil
    var bottomPadding: CGFloat = 20
    @Environment(\.locale) private var locale

    var body: some View {
        let metrics = RunningMetrics(session: session)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RunningDetailHeader(session: session, metrics: metrics, usesThemeColors: true)
                RunningSplitsSection(session: session, metrics: metrics).padding(.horizontal, 15)
                RunningChartsSection(session: session, metrics: metrics).padding(.horizontal, 15)
                if let content, !content.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        Text("runningDetail.memory").font(.system(size: 22))
                        if !content.text.isEmpty {
                            Text(verbatim: content.text).font(.system(size: 16)).textSelection(.enabled)
                                .accessibilityIdentifier("running.detail.text")
                        }
                        if let data = content.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .accessibilityLabel(Text("content.photo")).accessibilityIdentifier("running.detail.photo")
                        }
                    }.padding(15)
                }
            }.padding(.top, 16).padding(.bottom, bottomPadding)
        }.scrollIndicators(.hidden)
            .foregroundStyle(Color(hex: 0x222222))
            .environment(\.timeZone, TimeZone(identifier: session.timeZoneID) ?? .current)
            .accessibilityIdentifier("running.result")
    }
}

private struct RunningDetailCityOverlay: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.06), location: 0.25),
                .init(color: .white.opacity(0.3), location: 0.55),
                .init(color: .white.opacity(0.7), location: 0.8),
                .init(color: .white, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            Image(CalendarTheme.selected.transparentCityImage)
                .resizable().scaledToFit()
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RunningDetailHeader: View {
    let session: RunningSession
    let metrics: RunningMetrics
    var usesThemeColors = false
    @Environment(\.locale) private var locale
    private var primaryTextColor: Color {
        usesThemeColors ? CalendarTheme.selected.detailTextColor : Color(hex: 0x222222)
    }
    private var secondaryTextColor: Color {
        usesThemeColors ? CalendarTheme.selected.detailTextColor.opacity(0.65) : Color(hex: 0x98989E)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(RunningDisplay.distance(metrics.distanceMeters, locale: locale))
                        .font(.custom("DINCondensedC", size: 50)).foregroundStyle(primaryTextColor)
                        .accessibilityIdentifier("running.result.distance")
                    Text("running.kilometers").font(.system(size: 16)).foregroundStyle(secondaryTextColor)
                }.padding(.leading, 15)
                Spacer(minLength: 8)
                Text(LocalizedStringKey(session.kind.titleKey)).font(.system(size: 15))
                    .padding(.horizontal, 16).frame(height: 40).foregroundStyle(.white)
                    .background(RunningDetailStyle.color(session.kind), in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20))
                    .accessibilityIdentifier("running.result.kind")
            }.padding(.top, 15)
            Text(RunningDetailStyle.date(session, locale: locale)).font(.system(size: 14))
                .foregroundStyle(secondaryTextColor).padding(.horizontal, 15)
            HStack(alignment: .top) {
                metric(RunningDisplay.duration(metrics.elapsedSeconds), "running.duration", alignment: .leading)
                metric(RunningDetailStyle.pace(session, metrics: metrics, locale: locale), session.kind == .cycling ? "runningDetail.speed" : "runningDetail.pace", alignment: .center)
                metric(metrics.roundedEnergyKilocalories.map { $0.formatted(.number.locale(locale)) } ?? "—", "runningDetail.kcal", alignment: .trailing, identifier: "running.result.energy")
            }.padding(.horizontal, 15).padding(.top, 16).padding(.bottom, 20)
            Divider().padding(.horizontal, 15)
        }
    }
    private func metric(_ value: String, _ title: LocalizedStringKey, alignment: HorizontalAlignment, identifier: String = "") -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(value).font(.custom("DINCondensedC", size: 22)).foregroundStyle(primaryTextColor)
                .lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier(identifier)
            Text(title).font(.system(size: 14)).foregroundStyle(secondaryTextColor)
        }.frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center)
    }
}

struct RunningResultOverview: View {
    let session: RunningSession
    @Binding var showingMap: Bool
    var snapshotImage: UIImage? = nil
    var exporting = false
    @Environment(\.locale) private var locale
    var body: some View {
        let metrics = RunningMetrics(session: session)
        GeometryReader { geometry in
            let cityHeight = geometry.size.width * 272 / 750
            let mapHeight = max(220, geometry.size.height - cityHeight - 159 + geometry.safeAreaInsets.bottom)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(RunningDisplay.distance(metrics.distanceMeters, locale: locale)).font(.custom("DINCondensedC", size: 45))
                        .accessibilityIdentifier("running.overview.distance")
                    Text("Km").font(.system(size: 18, weight: .bold))
                }.foregroundStyle(Color(hex: 0x222222).opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 25).padding(.top, 22)
                HStack(spacing: 0) {
                    stripMetric("run_result_speed", RunningDetailStyle.pace(session, metrics: metrics, locale: locale),
                                session.kind == .cycling ? "runningDetail.speed" : "runningDetail.pace")
                    stripMetric("run_result_time", RunningDisplay.duration(metrics.elapsedSeconds), "running.duration")
                    stripMetric("run_result_calories", metrics.roundedEnergyKilocalories.map(String.init) ?? "—", "runningDetail.kcal")
                }.foregroundStyle(.white).frame(height: 58)
                    .background(Color(white: 44/255).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 15).padding(.top, 10)
                Group {
                    if session.kind.usesGPS {
                        Group {
                            if let snapshotImage {
                                Image(uiImage: snapshotImage).resizable().scaledToFill().clipped()
                            } else if exporting {
                                Color(hex: 0xF6F6F6)
                            } else {
                                RunningRouteMap(segments: session.segments, resultAverageSpeed: metrics.averageSpeedKilometersPerHour.map { $0 / 3.6 })
                            }
                        }.allowsHitTesting(false)
                            .overlay {
                                if session.segments.allSatisfy({ $0.isEmpty }) {
                                    Text("running.noRoute").font(.system(size: 14)).padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .overlay {
                                Button { showingMap = true } label: { Color.clear.contentShape(Rectangle()) }
                                    .accessibilityLabel(Text("runningDetail.openMap")).accessibilityIdentifier("running.map.open")
                            }
                    } else {
                        RunningIndoorResultGraph(session: session, metrics: metrics, chartHeight: min(255, max(150, mapHeight - 75))).padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: 0xF6F6F6))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: mapHeight)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(session.kind.titleKey)).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(RunningDetailStyle.color(session.kind), in: Capsule())
                        Text(RunningDetailStyle.date(session, locale: locale)).padding(.trailing, 5)
                    }.font(.system(size: 9)).foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule())
                        .padding(.trailing, 9).padding(.bottom, session.kind.usesGPS ? 42 : 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal, 15).padding(.top, 12)
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                if exporting { CardDetailThemeBackground() }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("running.overview")
    }
    private func stripMetric(_ image: String, _ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(image).resizable().scaledToFit().frame(width: 16, height: 18)
                Text(value).font(.custom("DINCondensedC", size: 19)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity)
    }
}

private struct RunningIndoorResultGraph: View {
    let session: RunningSession
    let metrics: RunningMetrics
    let chartHeight: CGFloat
    @Environment(\.locale) private var locale
    private var distanceByTime: [Date: Double] {
        Dictionary(session.indoorSegments.flatMap { $0 }.map { ($0.timestamp, $0.distanceMeters / 1_000) }, uniquingKeysWith: { _, last in last })
    }
    var body: some View {
        let distances = distanceByTime
        let colors = [Color(hex: 0xFF8366), Color(hex: 0xFFDE00), Color(hex: 0x6ADFAD)]
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let height = geometry.size.height
                let width = geometry.size.width
                let maximum = max(0.01, metrics.maximumSpeedKilometersPerHour ?? 0)
                let distance = max(0.001, metrics.distanceMeters / 1_000)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        for tick in 0...4 {
                            let x = width * Double(tick) / 4
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        }
                    }.stroke(Color(hex: 0xBAB9B9).opacity(0.4), lineWidth: 1)
                    ForEach(Array(Dictionary(grouping: RunningChartSampling.points(metrics.speedSeries), by: \.segmentIndex).keys.sorted()), id: \.self) { segment in
                        let points = RunningChartSampling.points(metrics.speedSeries).filter { $0.segmentIndex == segment }.map {
                            CGPoint(x: min(width, max(0, (distances[$0.timestamp] ?? 0) / distance * width)),
                                    y: height - min(maximum, max(0, $0.value)) / maximum * (height - 25))
                        }
                        RunningResultCurve(points: points, baseline: height, filled: true)
                            .fill(LinearGradient(colors: colors.map { $0.opacity(0.12) }, startPoint: .top, endPoint: .bottom))
                        RunningResultCurve(points: points, baseline: height, filled: false)
                            .stroke(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("runningDetail.maximumSpeed").font(.system(size: 11))
                        Text(RunningDetailStyle.number(metrics.maximumSpeedKilometersPerHour.map { $0 / 3.6 }, locale: locale, digits: 2) + " m/s")
                            .font(.custom("DINCondensedC", size: 12))
                    }.foregroundStyle(Color(hex: 0x222222).opacity(0.4)).padding(.leading, 3)
                    if metrics.speedSeries.isEmpty {
                        Text("runningDetail.noSamples").font(.system(size: 14)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }.frame(height: chartHeight)
            HStack {
                ForEach(0...4, id: \.self) { tick in
                    if tick > 0 { Spacer(minLength: 0) }
                    Text(RunningDetailStyle.number(metrics.distanceMeters / 1_000 * Double(tick) / 4, locale: locale, digits: 2) + "km")
                }
            }.font(.custom("DINCondensedC", size: 12)).foregroundStyle(Color(hex: 0x222222).opacity(0.4))
        }.accessibilityElement(children: .combine).accessibilityIdentifier("running.chart.speed")
    }
}

/// The original curve uses horizontal tangents. Each measured segment remains a separate path.
struct RunningResultCurve: Shape {
    let points: [CGPoint]
    let baseline: CGFloat
    let filled: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for (previous, point) in zip(points, points.dropFirst()) {
            let x = (previous.x + point.x) / 2
            path.addCurve(to: point, control1: CGPoint(x: x, y: previous.y), control2: CGPoint(x: x, y: point.y))
        }
        if filled {
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.addLine(to: CGPoint(x: first.x, y: baseline))
            path.closeSubpath()
        }
        return path
    }
}

struct RunningDetailMapView: View {
    let session: RunningSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var showsKilometers = false
    @State private var showsPlaces = true
    @State private var resetCamera = 0

    // Mark the measured sample that first crosses each complete kilometer. Never bridge pauses.
    private var kilometerPoints: [RunningPoint] {
        var distance = 0.0
        var points: [RunningPoint] = []
        for segment in session.segments {
            for (previous, point) in zip(segment, segment.dropFirst()) {
                distance += previous.distance(to: point)
                while distance >= Double(points.count + 1) * 1_000, points.count < session.splits.count {
                    points.append(point)
                }
            }
        }
        return points
    }
    var body: some View {
        let metrics = RunningMetrics(session: session)
        NavigationStack {
            RunningRouteMap(segments: session.segments, kilometerPoints: showsKilometers ? kilometerPoints : [],
                            showsPlaces: showsPlaces, resetCamera: resetCamera, resultAverageSpeed: metrics.averageSpeedKilometersPerHour.map { $0 / 3.6 })
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 12) {
                        if !kilometerPoints.isEmpty {
                            Button { showsKilometers.toggle() } label: { Image(systemName: showsKilometers ? "mappin.circle.fill" : "mappin.circle") }
                                .accessibilityLabel(Text("runningDetail.kilometerMarkers")).accessibilityValue(Text(showsKilometers ? "runningDetail.visible" : "runningDetail.hidden"))
                                .accessibilityIdentifier("running.map.kilometers")
                        }
                        Button { resetCamera += 1 } label: { Image(systemName: "scope") }
                            .accessibilityLabel(Text("runningDetail.fitRoute")).accessibilityIdentifier("running.map.fit")
                        Button { showsPlaces.toggle() } label: { Image(systemName: showsPlaces ? "mappin.and.ellipse" : "map") }
                            .accessibilityLabel(Text("runningDetail.places")).accessibilityValue(Text(showsPlaces ? "runningDetail.visible" : "runningDetail.hidden"))
                            .accessibilityIdentifier("running.map.places")
                    }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color(hex: 0x333333)).font(.system(size: 20))
                        .padding(15)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(RunningDisplay.distance(metrics.distanceMeters, locale: locale)).font(.custom("DINCondensedC", size: 45))
                            Text("running.kilometers").font(.system(size: 14))
                        }
                        HStack(alignment: .top, spacing: 16) {
                            mapMetric(RunningDisplay.duration(metrics.elapsedSeconds), "running.duration")
                            mapMetric(RunningDetailStyle.pace(session, metrics: metrics, locale: locale), session.kind == .cycling ? "runningDetail.speed" : "runningDetail.pace")
                            mapMetric(metrics.roundedEnergyKilocalories.map(String.init) ?? "—", "runningDetail.kcal")
                        }
                    }.padding(20).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x333333))
                }
                .navigationTitle(RunningDetailStyle.date(session, locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() }.accessibilityIdentifier("running.map.close") } }
        }
    }
    private func mapMetric(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.custom("DINCondensedC", size: 22)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunningRouteMap: View {
    @Default(.runningSettings) private var settings
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var preparationVisibleRect: MKMapRect?
    @State private var preparationHasCentered = false
    let segments: [[RunningPoint]]
    var showsUser: Bool = false
    var currentPoint: RunningPoint? = nil
    var followsUser: Bool = false
    var isPreparation: Bool = false
    var avatarData: Data? = nil
    var kilometerPoints: [RunningPoint] = []
    var showsPlaces = false
    var resetCamera = 0

    var resultAverageSpeed: Double? = nil

    private struct ColoredSegment: Identifiable {
        let id: Int
        var points: [RunningPoint]
        let hex: UInt32
    }
    private var coloredSegments: [ColoredSegment] {
        guard let average = resultAverageSpeed else { return [] }
        var result: [ColoredSegment] = []
        for segment in segments {
            var current: ColoredSegment?
            for (previous, point) in zip(segment, segment.dropFirst()) {
                let duration = point.timestamp.timeIntervalSince(previous.timestamp)
                let speed = duration > 0 ? previous.distance(to: point) / duration : 0
                let hex: UInt32 = speed <= 1.94 ? 0xA2E36E : speed > average ? 0xFF9457 : 0xFFDF48
                if current?.hex == hex { current?.points.append(point) }
                else {
                    if let current { result.append(current) }
                    current = ColoredSegment(id: result.count, points: [previous, point], hex: hex)
                }
            }
            if let current { result.append(current) }
        }
        return result
    }

    private var usesSatellite: Bool { !isPreparation && settings.satelliteMap }

    var body: some View {
        if isPreparation {
            GeometryReader { geometry in
                mapSurface
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            Color.white.opacity(0.40)
                            if showsUser, let currentPoint, let rect = preparationVisibleRect,
                               rect.size.width > 0, rect.size.height > 0 {
                                let coordinate = RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: currentPoint.latitude, longitude: currentPoint.longitude))
                                let point = MKMapPoint(coordinate)
                                let worldWidth = MKMapRect.world.size.width
                                let wrappedX = point.x + ((rect.midX - point.x) / worldWidth).rounded() * worldWidth
                                RunningUserLocationPin(avatarData: avatarData)
                                    .position(x: (wrappedX - rect.minX) / rect.size.width * geometry.size.width,
                                              y: (point.y - rect.minY) / rect.size.height * geometry.size.height - 27)
                                    .accessibilityLabel(Text("running.currentLocation"))
                            }
                        }
                        .clipped()
                        .allowsHitTesting(false)
                    }
                    .onAppear { updateCamera(viewport: geometry.size) }
                    .onChange(of: currentPoint?.timestamp) { _, _ in updateCamera(viewport: geometry.size) }
                    .onChange(of: geometry.size) { _, size in updateCamera(viewport: size) }
            }
        } else {
            mapSurface
                .onAppear { updateCamera() }
                .onChange(of: currentPoint?.timestamp) { _, _ in updateCamera() }
        }
    }

    private var mapSurface: some View {
        Map(position: $cameraPosition, interactionModes: isPreparation ? [.pan, .zoom] : .all) {
            ForEach(coloredSegments) { segment in
                MapPolyline(coordinates: segment.points.map { RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) })
                    .stroke(Color(hex: segment.hex), lineWidth: 5)
            }
            ForEach(Array((resultAverageSpeed == nil ? segments : []).enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map { RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) })
                        .stroke(Color(hex: 0xFF6440), lineWidth: 5)
                }
            }
            ForEach(Array(kilometerPoints.enumerated()), id: \.offset) { index, point in
                Annotation("\(index + 1)", coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))) {
                    Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Color(hex: 0xFF6440), in: Circle())
                }.annotationTitles(.hidden)
            }
            if !showsUser, let first = segments.first(where: { !$0.isEmpty })?.first {
                Annotation(LocalizedStringKey("running.routeStart"), coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude))) {
                    if resultAverageSpeed != nil { Image("run_result_start").resizable().scaledToFit().frame(width: 25, height: 25) }
                    else { Circle().fill(.green).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
            }
            if !showsUser, let last = segments.last(where: { !$0.isEmpty })?.last {
                Annotation(LocalizedStringKey("running.routeEnd"), coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))) {
                    if resultAverageSpeed != nil { Image("run_result_end").resizable().scaledToFit().frame(width: 25, height: 25) }
                    else { Circle().fill(Color(hex: 0xFF6440)).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
            }
            if !isPreparation, showsUser, let currentPoint {
                Annotation(coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: currentPoint.latitude, longitude: currentPoint.longitude)), anchor: .bottom) {
                    RunningUserLocationPin(avatarData: avatarData)
                        .accessibilityLabel(Text("running.currentLocation"))
                } label: {
                    EmptyView()
                }
            }
        }.mapStyle(usesSatellite ? .imagery(elevation: .flat) : .standard(
            elevation: .flat,
            emphasis: isPreparation ? .muted : .automatic,
            pointsOfInterest: isPreparation || showsPlaces ? .all : .excludingAll
        ))
            .mapControlVisibility(isPreparation ? .hidden : .automatic)
            .accessibilityValue(Text(LocalizedStringKey(usesSatellite ? "runningSettings.satellite" : "runningSettings.standard")))
            .onChange(of: resetCamera) { _, _ in cameraPosition = .automatic }
            .onMapCameraChange(frequency: .continuous) { context in
                if isPreparation { preparationVisibleRect = context.rect }
            }
    }

    private func updateCamera(viewport: CGSize = .zero) {
        guard followsUser else { return }
        guard let currentPoint else {
            cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            return
        }
        let recentDistance = segments.last?.suffix(20).map { $0.distance(to: currentPoint) }.max() ?? 0
        let zoomMeters = min(2_500, max(400, recentDistance * 2.4))
        let coordinate = RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: currentPoint.latitude, longitude: currentPoint.longitude))
        if isPreparation {
            guard viewport.width > 0, viewport.height > 0 else { return }
            let point = MKMapPoint(coordinate)
            // Derive the scale from meters, not camera callbacks, which may include
            // MapKit fitting adjustments or an intermediate animated camera position.
            let unitsPerPoint = 200 * MKMapPointsPerMeterAtLatitude(coordinate.latitude) / min(viewport.width, viewport.height)
            let width = viewport.width * unitsPerPoint
            let height = viewport.height * unitsPerPoint
            // Move the camera north so the actual location appears 80 pt below the viewport center.
            let rect = MKMapRect(x: point.x - width / 2,
                                 y: point.y - height / 2 - 80 * unitsPerPoint,
                                 width: width, height: height)
            if preparationHasCentered {
                withAnimation(.easeInOut(duration: 0.3)) {
                    cameraPosition = .rect(rect)
                }
            } else {
                preparationHasCentered = true
                cameraPosition = .rect(rect)
            }
            return
        }
        cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: zoomMeters, longitudinalMeters: zoomMeters))
    }
}

private struct RunningUserLocationPin: View {
    let avatarData: Data?

    var body: some View {
        ZStack(alignment: .top) {
            RunningLocationPinShape()
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            avatar
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .padding(.top, 4)
        }
        .frame(width: 44, height: 54)
        .accessibilityElement(children: .ignore)
    }

    private var avatar: Image {
        if let data = avatarData, let image = UIImage(data: data) {
            return Image(uiImage: image)
        }
        return Image("RunningLocationFallback")
    }
}

private struct RunningLocationPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = CGAffineTransform(scaleX: rect.width / 44, y: rect.height / 54)
        path.move(to: CGPoint(x: 22, y: 54))
        path.addCurve(to: CGPoint(x: 0, y: 22), control1: CGPoint(x: 18, y: 43), control2: CGPoint(x: 0, y: 38))
        path.addCurve(to: CGPoint(x: 22, y: 0), control1: CGPoint(x: 0, y: 9.85), control2: CGPoint(x: 9.85, y: 0))
        path.addCurve(to: CGPoint(x: 44, y: 22), control1: CGPoint(x: 34.15, y: 0), control2: CGPoint(x: 44, y: 9.85))
        path.addCurve(to: CGPoint(x: 22, y: 54), control1: CGPoint(x: 44, y: 38), control2: CGPoint(x: 26, y: 43))
        path.closeSubpath()
        return path.applying(scale)
    }
}

enum RunningDisplay {
    static func distance(_ meters: Double, locale: Locale) -> String {
        (meters / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
    static func speed(distance: Double, seconds: TimeInterval, locale: Locale) -> String {
        guard distance > 0, seconds > 0 else { return "—" }
        return (distance / seconds * 3.6).formatted(.number.precision(.fractionLength(1)).locale(locale))
    }
    static func cadence(steps: Int, seconds: TimeInterval, locale: Locale) -> String {
        guard seconds > 0 else { return "—" }
        return (Double(steps) / seconds * 60).formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
    }
    static func pace(distance: Double, seconds: TimeInterval) -> String {
        guard distance > 0, seconds > 0 else { return "—" }
        return paceSeconds(seconds / (distance / 1_000))
    }
    static func paceSeconds(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d′%02d″", value / 60, value % 60)
    }
}
