import SwiftUI
import Charts

/// Resolve only the selected civil day. A sensor reading does not imply a successful save.
struct StepsPresentation: Equatable {
    let day: LocalDay
    let steps: Int?
    let distance: Double?
    let goal: Int?
    let isSaved: Bool
    let intraday: StepIntraday?
    let timeZoneID: String

    init(day: LocalDay, reading: StepReading?, saved: StepRecord?, goal: Int?) {
        self.day = day
        let reading = reading.flatMap { $0.day == day && $0.isValid ? $0 : nil }
        let saved = saved.flatMap { record -> StepRecord? in
            let measurement = StepReading(day: record.day, timeZoneID: record.timeZoneID, steps: record.steps,
                                          distance: record.distance, measuredAt: record.measuredAt, intraday: record.intraday)
            return record.day == day && measurement.isValid ? record : nil
        }
        // A stale callback must not replace a more recent persisted measurement.
        let displayed = reading.flatMap { value in
            if let saved, saved.measuredAt > value.measuredAt { return nil as StepReading? }
            return value
        }
        let zoneID = displayed?.timeZoneID ?? saved?.timeZoneID ?? TimeZone.current.identifier
        timeZoneID = zoneID
        let cached = saved.flatMap { $0.timeZoneID == zoneID ? $0.intraday : nil }
        intraday = [displayed?.intraday, cached].compactMap { $0 }.max { $0.measuredThrough < $1.measuredThrough }
        steps = displayed?.steps ?? saved?.steps
        distance = displayed != nil ? displayed?.distance : saved?.distance
        self.goal = saved != nil ? saved?.goal : goal
        if let displayed {
            isSaved = saved.map { $0.steps == displayed.steps && $0.distance == displayed.distance &&
                $0.measuredAt == displayed.measuredAt && $0.timeZoneID == displayed.timeZoneID } ?? false
        } else { isSaved = saved != nil }
    }

    func dateLabel(locale: Locale) -> String {
        let zone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: day.date(in: zone))
    }
}

enum StepsPosterStyle: String, CaseIterable {
    case details, card
    var titleKey: String { self == .details ? "steps.viewDetails" : "steps.viewCard" }
}

/// Intrinsically sized content shared by the card preview and the exported image.
struct StepsPoster: View {
    let data: StepsPresentation
    let style: StepsPosterStyle
    let locale: Locale
    var isMale = false

    private let tint = Color(hex: 0x158DA5)
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                HStack {
                    Text("steps.title").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Image("feed_sport_ic_walk").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                }
                Text(data.dateLabel(locale: locale)).font(.system(size: 15)).accessibilityIdentifier("steps.poster.date")
                if style == .details {
                    ZStack {
                        Circle().stroke(.white.opacity(0.3), lineWidth: 5)
                        if let steps = data.steps, let goal = data.goal, goal > 0 {
                            Circle().trim(from: 0, to: min(1, CGFloat(steps) / CGFloat(goal)))
                                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        count
                    }.frame(width: 200, height: 200).padding(.vertical, 12)
                } else { count.padding(.vertical, 8) }
                if let steps = data.steps, let goal = data.goal, goal > 0, steps >= goal {
                    Label("steps.goalReached", systemImage: "checkmark.circle.fill").font(.system(size: 14, weight: .medium))
                }
            }.padding(28).frame(maxWidth: .infinity).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(hex: 0x4FCFBD), Color(hex: 0x3EABD3)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 18) {
                if let distance = data.distance {
                    metric("steps.distance", value: (distance / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " " + localized("unit.kilometers", locale))
                }
                if let goal = data.goal {
                    metric("steps.dailyGoal", value: goal.formatted(.number.locale(locale)) + " " + localized("unit.steps", locale))
                }
                if style == .details { StepsIntradayView(data: data) }
                if data.steps == nil { Text("steps.noData").font(.system(size: 15)).foregroundStyle(.secondary) }
                Image(isMale ? "card_details_walk_male" : "card_details_walk_female")
                    .resizable().scaledToFit().frame(height: style == .card ? 260 : 170).accessibilityHidden(true)
                Text("steps.shareEncouragement").font(.system(size: 17, weight: .medium)).foregroundStyle(tint)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(28)
            HStack {
                Text("KeepUp").font(.system(size: 21, weight: .bold))
                Spacer()
                Text(data.day.rawValue).font(.system(size: 12)).monospacedDigit()
            }.foregroundStyle(tint).padding(24).background(tint.opacity(0.05))
        }.background(.white).foregroundStyle(.black)
            .environment(\.locale, locale).environment(\.colorScheme, .light)
    }

    private var count: some View {
        VStack(spacing: 6) {
            Text(data.steps.map { $0.formatted(.number.locale(locale)) } ?? "—")
                .font(.system(size: 45, weight: .light)).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier("steps.poster.count")
            Text("unit.steps").font(.system(size: 14))
        }.padding(.horizontal, 14)
    }

    private func metric(_ key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(key)).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 18, weight: .medium)).multilineTextAlignment(.trailing)
        }
    }
}

@MainActor enum StepsPosterRenderer {
    static func render(data: StepsPresentation, style: StepsPosterStyle, locale: Locale, isMale: Bool = false) -> UIImage? {
        guard data.steps != nil else { return nil }
        let renderer = ImageRenderer(content: StepsPoster(data: data, style: style, locale: locale, isMale: isMale).frame(width: 390))
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct StepsIntradayView: View {
    let data: StepsPresentation
    @Environment(\.locale) private var locale

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: data.timeZoneID)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var dayDomain: ClosedRange<Date> {
        let zone = TimeZone(identifier: data.timeZoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: data.day.date(in: zone))
        return start...(calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("steps.hourly").font(.headline)
            if let detail = data.intraday {
                let hours = detail.hours(timeZoneID: data.timeZoneID)
                Chart(hours) { hour in
                    if let steps = hour.steps {
                        RectangleMark(xStart: .value("Hour", hour.start.addingTimeInterval(120)),
                                xEnd: .value("Hour", hour.start.addingTimeInterval(3480)),
                                yStart: .value("Steps", 0), yEnd: .value("Steps", steps))
                            .foregroundStyle(Color(hex: 0x49C8BA))
                            .accessibilityLabel(hourLabel(hour.start))
                            .accessibilityValue(String(steps) + " " + localized("unit.steps", locale))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let date = value.as(Date.self) { Text(hourLabel(date)) } }
                    }
                }
                .environment(\.timeZone, TimeZone(identifier: data.timeZoneID) ?? .current)
                .chartXScale(domain: dayDomain)
                .chartYScale(domain: 0...max(1, hours.compactMap(\.steps).max() ?? 1))
                .frame(height: 150).accessibilityIdentifier("steps.hourlyChart")
                HStack {
                    Text("steps.activeEstimate")
                    Spacer()
                    Text(detail.estimatedActiveMinutes.map { String(format: localized("steps.minutes %lld", locale), Int64($0)) } ?? "—")
                        .accessibilityIdentifier("steps.activeMinutes")
                }.font(.subheadline)
                if !detail.isComplete { Text("steps.intradayPartial").foregroundStyle(.secondary).accessibilityIdentifier("steps.intradayPartial") }
                Text("steps.activeExplanation").foregroundStyle(.secondary)
                Text(localized("steps.dataThrough", locale) + " " + hourLabel(detail.measuredThrough)).foregroundStyle(.secondary)
            } else {
                Text("steps.intradayMissing").foregroundStyle(.secondary).accessibilityIdentifier("steps.intradayMissing")
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}
