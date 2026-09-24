import SwiftUI

/// Shared by on-screen details and paginated share posters; all calculations come from RunningMetrics.
struct RunningSplitsSection: View {
    let session: RunningSession
    let metrics: RunningMetrics
    var alwaysExpanded = false
    var displayedSplits: [RunningMetricSplit]? = nil
    @Environment(\.locale) private var locale
    @State private var expanded = false

    private var allSplits: [RunningMetricSplit] { displayedSplits ?? metrics.splits }
    private var visibleSplits: [RunningMetricSplit] {
        guard !alwaysExpanded, !expanded, allSplits.count > 3 else { return allSplits }
        let best = allSplits.firstIndex { $0.id == metrics.bestKilometer?.id } ?? 0
        let start = min(max(0, best - 1), allSplits.count - 3)
        return Array(allSplits.dropFirst(start).prefix(3))
    }
    private var tint: Color { RunningDetailStyle.color(session.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LocalizedStringKey(session.kind == .cycling ? "runningDetail.speed" : "runningDetail.pace"))
                    .font(.system(size: 22))
                Spacer(minLength: 4)
                Text(LocalizedStringKey(session.kind == .cycling ? "runningDetail.bestSpeed" : "runningDetail.bestPace"))
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0x98989E))
                Text(metrics.bestKilometer.map(splitValue) ?? "—")
                    .font(.custom("DINCondensedC", size: 15)).foregroundStyle(tint)
                    .accessibilityIdentifier("running.bestKilometer")
            }.padding(.top, 20)
            HStack {
                Text("running.kilometers").frame(width: 100, alignment: .leading)
                Text(LocalizedStringKey(session.kind == .cycling ? "running.speedUnit" : "runningDetail.pace"))
                Spacer()
            }.font(.system(size: 12)).foregroundStyle(Color(hex: 0x48484D)).padding(.leading, 4).padding(.top, 20).padding(.bottom, 12)
            if allSplits.isEmpty {
                Text("running.noSplits").font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 14)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(visibleSplits) { split in splitBar(split) }
                }
            }
            if !alwaysExpanded, allSplits.count > 3 {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(LocalizedStringKey(expanded ? "runningDetail.collapseSplits" : "runningDetail.expandSplits"))
                        Image(expanded ? "card_indoor_ic_up" : "card_indoor_ic_down").resizable().scaledToFit().frame(width: 12, height: 12)
                    }.font(.system(size: 12)).foregroundStyle(Color(hex: 0x48484D)).frame(height: 90)
                }.buttonStyle(.plain).accessibilityIdentifier("running.splits.toggle")
            } else { Color.clear.frame(height: 42) }
            Divider()
        }
    }

    private func splitBar(_ split: RunningMetricSplit) -> some View {
        let best = split.id == metrics.bestKilometer?.id
        let paces = metrics.splits.compactMap(\.paceSecondsPerKilometer)
        let fastest = paces.min() ?? 0
        let slowest = paces.max() ?? 0
        let pace = split.paceSecondsPerKilometer ?? slowest
        let fraction = slowest > fastest ? 1 - 0.5 * (pace - fastest) / (slowest - fastest) : 1
        let base = Color(hex: session.kind == .outdoor ? 0xFFBAAA : session.kind == .indoor ? 0xA6BAFF : 0x5866E3)
        let bestColor = Color(hex: session.kind == .outdoor ? 0xFF6440 : 0x6889FF)
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                Text(split.isComplete ? String(split.kilometer) : "<" + String(split.kilometer))
                    .font(.system(size: 14)).frame(width: 32, height: 32)
                    .background(Color(hex: session.kind == .outdoor ? 0xFF7D5F : 0x4D73FF), in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 1)
                Text(splitValue(split)).font(.custom("DINCondensedC", size: 15))
                    .padding(.leading, 72).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if best { Text("runningDetail.fastest").font(.system(size: 14)).padding(.trailing, 15) }
            }.foregroundStyle(.white)
                .frame(width: max(172, geometry.size.width * min(1, max(0.5, fraction))), height: 32)
                .background(best ? bestColor : base, in: Capsule())
        }.frame(height: 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(split.isComplete ? "running.split.\(split.kilometer)" : "running.split.tail")
            .accessibilityValue(split.isComplete ? "" : RunningDisplay.distance(split.distanceMeters, locale: locale) + " " + localized("runningDetail.partialKilometer", locale))
    }

    private func splitValue(_ split: RunningMetricSplit) -> String {
        if session.kind == .cycling { return RunningDetailStyle.number(split.speedKilometersPerHour, locale: locale, digits: 2) }
        return split.paceSecondsPerKilometer.map(RunningDisplay.paceSeconds) ?? "—"
    }
}

struct RunningChartsSection: View {
    let session: RunningSession
    let metrics: RunningMetrics
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.kind.usesGPS {
                metricChart(title: "runningDetail.altitude", points: metrics.altitudeSeries,
                            summaryTitle: "runningDetail.ascent", summaryValue: metrics.ascentMeters,
                            unit: "runningDetail.meters", color: Color(hex: 0xFFB94C), identifier: "running.chart.altitude")
            }
            if session.kind != .cycling {
                metricChart(title: "runningDetail.cadence", points: metrics.cadenceSeries,
                            summaryTitle: "runningDetail.maximumCadence", summaryValue: metrics.maximumCadenceStepsPerMinute,
                            unit: "runningDetail.stepsPerMinute", color: Color(hex: 0x66A5FF), identifier: "running.chart.cadence")
            }
        }
    }

    private func metricChart(title: LocalizedStringKey, points: [RunningMetricPoint], summaryTitle: LocalizedStringKey,
                             summaryValue: Double?, unit: String, color: Color, identifier: String) -> some View {
        let plottedPoints = RunningChartSampling.points(points)
        let isAltitude = identifier == "running.chart.altitude"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 22))
                Spacer()
                HStack(spacing: 4) {
                    Text(summaryTitle).foregroundStyle(Color(hex: 0x98989E))
                    Text(RunningDetailStyle.number(summaryValue, locale: locale, digits: 0))
                        .foregroundStyle(isAltitude ? Color(hex: 0xFF6440) : RunningDetailStyle.color(session.kind))
                        .accessibilityIdentifier(identifier + ".maximum")
                    if !isAltitude {
                        Rectangle().fill(Color(hex: 0xDCDCDC)).frame(width: 1, height: 13).padding(.horizontal, 5)
                        Text("running.cadence").foregroundStyle(Color(hex: 0x98989E))
                        Text(points.isEmpty ? "—" : RunningDisplay.cadence(steps: session.steps, seconds: metrics.elapsedSeconds, locale: locale))
                            .foregroundStyle(RunningDetailStyle.color(session.kind))
                            .accessibilityIdentifier("running.result.cadence")
                    }
                }.font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(height: 31).padding(.top, 20).padding(.bottom, 20)
            if points.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("runningDetail.noSamples").font(.system(size: 16)).foregroundStyle(Color(hex: 0xC4C6CB))
                    if identifier == "running.chart.cadence" {
                        Image("no_step_frequency_data").resizable().scaledToFit().frame(maxHeight: 95).accessibilityHidden(true)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, minHeight: 196)
                    .accessibilityIdentifier(identifier + ".missing")
            } else {
                RunningDetailPlot(points: plottedPoints, altitude: isAltitude, color: color, locale: locale)
                    .frame(height: 196)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier(identifier)
            }
            Spacer(minLength: 0)
            Divider()
        }.frame(height: 300)
    }
}

private struct RunningDetailPlot: View {
    let points: [RunningMetricPoint]
    let altitude: Bool
    let color: Color
    let locale: Locale
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 29)
            let minimum = altitude ? (points.map(\.value).min() ?? 0) : 0
            let measuredMax = points.map(\.value).max() ?? 0
            let maximum = altitude ? max(minimum + 1, measuredMax) : max(50, ceil(measuredMax / 50) * 50)
            let duration = max(1, ceil((points.map(\.timeOffsetSeconds).max() ?? 0) / 60))
            let ticks = altitude ? [minimum, measuredMax] : stride(from: 0.0, through: maximum, by: maximum / 4).map { $0 }
            let y: (Double) -> Double = { value in
                altitude ? 126 - (value - minimum) / (maximum - minimum) * 89 : 156 - value / maximum * 134
            }
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 29, y: 22))
                    path.addLine(to: CGPoint(x: 29, y: 156))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: 156))
                    for value in ticks {
                        path.move(to: CGPoint(x: 29, y: y(value)))
                        path.addLine(to: CGPoint(x: 34, y: y(value)))
                    }
                    for tick in 1...5 {
                        let x = 29 + width * Double(tick) / 5
                        path.move(to: CGPoint(x: x, y: 156))
                        path.addLine(to: CGPoint(x: x, y: 151))
                    }
                }.stroke(Color(hex: 0xDCDCDC), lineWidth: 1)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, value in
                    Text(RunningDetailStyle.number(value, locale: locale)).frame(width: 25, alignment: .trailing)
                        .position(x: 12.5, y: y(value))
                }
                ForEach(0...5, id: \.self) { tick in
                    Text(RunningDetailStyle.number(duration * Double(tick) / 5, locale: locale))
                        .position(x: 29 + width * Double(tick) / 5, y: 169)
                }
                ForEach(Array(Set(points.map(\.segmentIndex))).sorted(), id: \.self) { segment in
                    let coordinates = points.filter { $0.segmentIndex == segment }.map {
                        CGPoint(x: 29 + width * $0.timeOffsetSeconds / 60 / duration, y: y($0.value))
                    }
                    RunningResultCurve(points: coordinates, baseline: 156, filled: true)
                        .fill(LinearGradient(colors: [color.opacity(0.35), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    RunningResultCurve(points: coordinates, baseline: 156, filled: false)
                        .stroke(color, lineWidth: 2)
                }
                Text(LocalizedStringKey(altitude ? "runningDetail.altitudeAxis" : "runningDetail.cadenceAxis"))
                Text("runningDetail.timeAxis").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }.font(.system(size: 14)).foregroundStyle(Color(hex: 0x222222).opacity(0.5))
        }
    }
}

enum RunningDetailStyle {
    static func date(_ session: RunningSession, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: session.timeZoneID) ?? .current
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: session.finishedAt ?? session.startedAt)
    }
    static func pace(_ session: RunningSession, metrics: RunningMetrics, locale: Locale) -> String {
        if session.kind == .cycling {
            return number(metrics.averageSpeedKilometersPerHour, locale: locale, digits: 2) + " km/h"
        }
        return metrics.averagePaceSecondsPerKilometer.map(RunningDisplay.paceSeconds) ?? "—"
    }

    static func color(_ kind: RunningKind) -> Color {
        Color(hex: kind == .cycling ? 0x5866E3 : kind == .indoor ? 0x6889FF : 0xFF6440)
    }
    static func number(_ value: Double?, locale: Locale, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }
}
