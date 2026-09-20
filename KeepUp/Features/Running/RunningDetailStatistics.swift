import SwiftUI
import Charts

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("running.splits").font(.system(size: 22, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("runningDetail.bestKilometer").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(metrics.bestKilometer.map(splitValue) ?? "—")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
                        .accessibilityIdentifier("running.bestKilometer")
                }
            }
            HStack {
                Text("running.kilometers")
                Spacer()
                Text(LocalizedStringKey(session.kind == .cycling ? "running.speedUnit" : "running.paceUnit"))
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            if allSplits.isEmpty {
                Text("running.noSplits").font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 14)
            } else {
                ForEach(visibleSplits) { split in
                    HStack(spacing: 12) {
                        if split.isComplete {
                            Text(split.kilometer.formatted(.number.locale(locale)))
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RunningDisplay.distance(split.distanceMeters, locale: locale))
                                Text("runningDetail.partialKilometer").font(.system(size: 10))
                            }
                        }
                        Spacer()
                        if split.id == metrics.bestKilometer?.id {
                            Text("runningDetail.fastest").font(.system(size: 11, weight: .medium))
                        }
                        Text(splitValue(split)).monospacedDigit()
                    }.font(.system(size: 15)).padding(.horizontal, 14).frame(minHeight: 46)
                        .foregroundStyle(split.id == metrics.bestKilometer?.id ? .white : Color(hex: 0x48484D))
                        .background(split.id == metrics.bestKilometer?.id ? tint : tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(split.isComplete ? "running.split.\(split.kilometer)" : "running.split.tail")
                }
            }
            if !alwaysExpanded, allSplits.count > 3 {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(LocalizedStringKey(expanded ? "runningDetail.collapseSplits" : "runningDetail.expandSplits"))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 13)).foregroundStyle(tint).padding(.vertical, 8)
                }.buttonStyle(.plain).accessibilityIdentifier("running.splits.toggle")
            }
        }.padding(.vertical, 24)
    }

    private func splitValue(_ split: RunningMetricSplit) -> String {
        if session.kind == .cycling { return RunningDetailStyle.number(split.speedKilometersPerHour, locale: locale, digits: 1) }
        return split.paceSecondsPerKilometer.map(RunningDisplay.paceSeconds) ?? "—"
    }
}

struct RunningChartsSection: View {
    let session: RunningSession
    let metrics: RunningMetrics
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            metricChart(title: "runningDetail.speedHistory", points: metrics.speedSeries,
                        summaryTitle: "runningDetail.maximumSpeed", summaryValue: metrics.maximumSpeedKilometersPerHour,
                        unit: "running.speedUnit", color: RunningDetailStyle.color(session.kind), identifier: "running.chart.speed")
            if session.kind == .indoor {
                metricChart(title: "runningDetail.cadenceHistory", points: metrics.cadenceSeries,
                            summaryTitle: "runningDetail.maximumCadence", summaryValue: metrics.maximumCadenceStepsPerMinute,
                            unit: "runningDetail.stepsPerMinute", color: Color(hex: 0x66A5FF), identifier: "running.chart.cadence")
            }
            if session.kind.usesGPS {
                metricChart(title: "runningDetail.altitudeHistory", points: metrics.altitudeSeries,
                            summaryTitle: "runningDetail.ascent", summaryValue: metrics.ascentMeters,
                            unit: "runningDetail.meters", color: RunningDetailStyle.color(session.kind), identifier: "running.chart.altitude")
                HStack(spacing: 16) {
                    metric("runningDetail.lowestAltitude", value: metrics.minimumAltitudeMeters)
                    metric("runningDetail.highestAltitude", value: metrics.maximumAltitudeMeters)
                }
            }
        }.padding(.vertical, 20)
    }

    private func metric(_ title: LocalizedStringKey, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(RunningDetailStyle.number(value, locale: locale, digits: 0) + " " + localized("runningDetail.meters", locale))
                .font(.system(size: 20, weight: .light)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricChart(title: LocalizedStringKey, points: [RunningMetricPoint], summaryTitle: LocalizedStringKey,
                             summaryValue: Double?, unit: String, color: Color, identifier: String) -> some View {
        let plottedPoints = RunningChartSampling.points(points)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(title).font(.system(size: 22, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(summaryTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(RunningDetailStyle.number(summaryValue, locale: locale, digits: 1) + " " + localized(unit, locale))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(color)
                        .accessibilityIdentifier(identifier + ".maximum")
                }
            }
            if points.isEmpty {
                Text("runningDetail.noSamples").font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110).multilineTextAlignment(.center)
                    .background(Color(hex: 0xF6F6F6), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier(identifier + ".missing")
            } else {
                Chart(plottedPoints) { point in
                    LineMark(x: .value(localized("runningDetail.elapsedMinutes", locale), point.timeOffsetSeconds / 60),
                             y: .value(localized(unit, locale), point.value),
                             series: .value(localized("runningDetail.segment", locale), point.segmentIndex))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
                    PointMark(x: .value(localized("runningDetail.elapsedMinutes", locale), point.timeOffsetSeconds / 60),
                              y: .value(localized(unit, locale), point.value))
                        .foregroundStyle(color).symbolSize(9)
                }.chartLegend(.hidden)
                    .chartXScale(domain: 0...max(1, (points.map(\.timeOffsetSeconds).max() ?? 0) / 60))
                    .chartXAxisLabel(localized("runningDetail.elapsedMinutes", locale))
                    .chartYAxisLabel(localized(unit, locale))
                    .frame(height: 185)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

enum RunningDetailStyle {
    static func color(_ kind: RunningKind) -> Color {
        Color(hex: kind == .cycling ? 0x5866E3 : kind == .indoor ? 0x6889FF : 0xFF6440)
    }
    static func number(_ value: Double?, locale: Locale, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }
}
