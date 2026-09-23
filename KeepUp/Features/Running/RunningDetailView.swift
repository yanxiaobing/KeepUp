import SwiftUI
import MapKit

struct RunningDetailView: View {
    let session: RunningSession
    var entry: CheckInEntry? = nil
    var card: HabitCard? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var sharing = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    private var currentEntry: CheckInEntry? {
        guard let entry else { return nil }
        return model.snapshot.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        NavigationStack {
            RunningSessionSummary(session: session, content: currentEntry.map { model.snapshot.publishedContent(for: $0) })
                .navigationTitle("running.result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.accessibilityIdentifier("running.result.close")
                    }
                    if currentEntry != nil, card != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("content.edit", systemImage: "square.and.pencil") { editing = true }
                                    .accessibilityIdentifier("running.detail.edit")
                                Button("action.delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                                    .accessibilityIdentifier("running.detail.delete")
                            } label: { Image(systemName: "ellipsis") }
                                .accessibilityLabel(Text("entry.actions")).accessibilityIdentifier("running.detail.actions")
                                .disabled(deleting)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { sharing = true } label: {
                            Image("card_detail_ic_share").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24)
                        }.accessibilityLabel(Text("entry.share")).accessibilityIdentifier("running.detail.share")
                    }
                }
                .fullScreenCover(isPresented: $editing) {
                    if let currentEntry, let card { EntryContentEditor(entry: currentEntry, card: card) }
                }
                .sheet(isPresented: $sharing) { RunningShareView(session: session) }
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

struct RunningSessionSummary: View {
    let session: RunningSession
    var content: EntryContent? = nil
    @Environment(\.locale) private var locale

    var body: some View {
        let metrics = RunningMetrics(session: session)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(RunningDisplay.distance(metrics.distanceMeters, locale: locale))
                            .font(.system(size: 50, weight: .light)).minimumScaleFactor(0.6)
                            .accessibilityIdentifier("running.result.distance")
                        Text("running.kilometers").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(LocalizedStringKey(session.kind.titleKey)).font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(.white).background(RunningDetailStyle.color(session.kind), in: Capsule())
                        .accessibilityIdentifier("running.result.kind")
                }
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
                HStack(spacing: 12) {
                    resultMetric(RunningDisplay.duration(metrics.elapsedSeconds), label: "running.duration")
                    if session.kind == .cycling {
                        resultMetric(RunningDetailStyle.number(metrics.averageSpeedKilometersPerHour, locale: locale, digits: 1), label: "running.averageSpeed")
                    } else {
                        resultMetric(metrics.averagePaceSecondsPerKilometer.map(RunningDisplay.paceSeconds) ?? "—", label: "running.averagePace")
                    }
                }.padding(.vertical, 22)
                HStack(spacing: 12) {
                    resultMetric(metrics.roundedEnergyKilocalories.map { $0.formatted(.number.locale(locale)) } ?? "—", label: "runningDetail.energy", identifier: "running.result.energy")
                    resultMetric(RunningDetailStyle.number(metrics.maximumSpeedKilometersPerHour, locale: locale, digits: 1), label: "runningDetail.maximumSpeedUnit", identifier: "running.result.maximumSpeed")
                }.padding(.bottom, 22)
                if session.kind.usesGPS {
                    RunningRouteMap(segments: session.segments, showsUser: false)
                        .frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("running.result.route")
                    if session.segments.allSatisfy({ $0.isEmpty }) {
                        Text("running.noRoute").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 10)
                    }
                } else {
                    HStack {
                        Text("running.steps")
                        Spacer()
                        Text(session.steps.formatted(.number.locale(locale))).monospacedDigit().accessibilityIdentifier("running.result.steps")
                    }.padding(.vertical, 18)
                    HStack {
                        Text("running.averageCadence")
                        Spacer()
                        Text(RunningDisplay.cadence(steps: session.steps, seconds: metrics.elapsedSeconds, locale: locale))
                            .monospacedDigit().accessibilityIdentifier("running.result.cadence")
                    }.padding(.bottom, 18)
                    Text("running.indoorDistanceHint").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                RunningSplitsSection(session: session, metrics: metrics)
                Divider()
                RunningChartsSection(session: session, metrics: metrics)
                if let content, !content.isEmpty {
                    Divider().padding(.vertical, 16)
                    Text("runningDetail.memory").font(.system(size: 22, weight: .medium)).padding(.bottom, 14)
                    if !content.text.isEmpty {
                        Text(verbatim: content.text).font(.system(size: 16)).textSelection(.enabled)
                            .accessibilityIdentifier("running.detail.text").padding(.bottom, 16)
                    }
                    if let data = content.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel(Text("content.photo")).accessibilityIdentifier("running.detail.photo")
                    }
                }
            }.padding(22)
        }.background(.white).foregroundStyle(Color(hex: 0x222222))
            .environment(\.timeZone, TimeZone(identifier: session.timeZoneID) ?? .current)
            .accessibilityIdentifier("running.result")
    }

    private func resultMetric(_ value: String, label: LocalizedStringKey, identifier: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value).font(.system(size: 24, weight: .light)).monospacedDigit()
                .accessibilityIdentifier(identifier ?? "")
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunningRouteMap: View {
    @Default(.runningSettings) private var settings
    let segments: [[RunningPoint]]
    var showsUser: Bool = false

    var body: some View {
        Map(initialPosition: showsUser ? .userLocation(followsHeading: false, fallback: .automatic) : .automatic) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map { RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) })
                        .stroke(Color(hex: 0xFF6440), lineWidth: 5)
                }
            }
            if let first = segments.first(where: { !$0.isEmpty })?.first {
                Annotation(LocalizedStringKey("running.routeStart"), coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude))) {
                    Circle().fill(.green).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let last = segments.last(where: { !$0.isEmpty })?.last {
                Annotation(LocalizedStringKey("running.routeEnd"), coordinate: RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))) {
                    Circle().fill(Color(hex: 0xFF6440)).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if showsUser { UserAnnotation() }
        }.mapStyle(settings.satelliteMap ? .imagery(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .accessibilityValue(Text(LocalizedStringKey(settings.satelliteMap ? "runningSettings.satellite" : "runningSettings.standard")))
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
