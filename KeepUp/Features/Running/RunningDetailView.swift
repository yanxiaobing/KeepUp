import SwiftUI
import MapKit

struct RunningDetailView: View {
    let session: RunningSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RunningSessionSummary(session: session)
                .navigationTitle("running.result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.accessibilityIdentifier("running.result.close")
                    }
                }
        }
    }
}

struct RunningSessionSummary: View {
    let session: RunningSession
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(RunningDisplay.distance(session.distanceMeters, locale: locale))
                            .font(.system(size: 50, weight: .light)).minimumScaleFactor(0.6)
                            .accessibilityIdentifier("running.result.distance")
                        Text("running.kilometers").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("running.outdoor").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(.white).background(Color(hex: 0xFF6440), in: Capsule())
                }
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
                HStack(spacing: 12) {
                    resultMetric(RunningDisplay.duration(session.elapsed(at: .now)), label: "running.duration")
                    resultMetric(RunningDisplay.pace(distance: session.distanceMeters, seconds: session.elapsed(at: .now)), label: "running.averagePace")
                }.padding(.vertical, 22)
                RunningRouteMap(segments: session.segments, showsUser: false)
                    .frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("running.result.route")
                if session.segments.flatMap({ $0 }).isEmpty {
                    Text("running.noRoute").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 10)
                }
                Text("running.splits").font(.system(size: 22, weight: .medium)).padding(.top, 28).padding(.bottom, 18)
                HStack {
                    Text("running.kilometers")
                    Spacer()
                    Text("running.paceUnit")
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 12)
                if session.splits.isEmpty {
                    Text("running.noSplits").font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 18)
                } else {
                    ForEach(Array(session.splits.enumerated()), id: \.offset) { _, split in
                        HStack {
                            Text(split.kilometer.formatted(.number.locale(locale)))
                            Spacer()
                            Text(RunningDisplay.paceSeconds(split.elapsedSeconds)).monospacedDigit()
                        }.font(.system(size: 16)).padding(14)
                            .background(Color(hex: 0xFFD838).opacity(0.25))
                            .padding(.bottom, 6)
                    }
                }
            }.padding(22)
        }.background(.white).foregroundStyle(Color(hex: 0x222222))
            .accessibilityIdentifier("running.result")
    }

    private func resultMetric(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value).font(.system(size: 24, weight: .light)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunningRouteMap: View {
    let segments: [[RunningPoint]]
    var showsUser: Bool = false

    var body: some View {
        Map {
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
        }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}

enum RunningDisplay {
    static func distance(_ meters: Double, locale: Locale) -> String {
        (meters / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale))
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
