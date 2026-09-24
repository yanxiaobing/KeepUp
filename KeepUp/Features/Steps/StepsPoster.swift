import SwiftUI

/// Resolve only the selected civil day. A sensor reading does not imply a successful save.
struct StepsPresentation: Equatable {
    let day: LocalDay
    let steps: Int?
    let distance: Double?
    let goal: Int?
    let isSaved: Bool
    let intraday: StepIntraday?
    let timeZoneID: String
    var estimatedKilocalories: Int? { ActivityEnergy.stepCalories(steps: steps) }

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

/// The exported image uses the same original layouts as the two on-screen pages.
struct StepsPoster: View {
    let data: StepsPresentation
    let style: StepsPosterStyle
    let locale: Locale
    var isMale = false
    var encouragement: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if style == .details { StepsOriginalDetails(data: data, isMale: isMale) }
                else { StepsOriginalCard(data: data, encouragement: encouragement) }
            }.frame(height: 700)
            HStack {
                Text(verbatim: "KeepUp").font(.system(size: 21, weight: .bold))
                Spacer()
                Text(data.dateLabel(locale: locale)).font(.system(size: 12))
            }.padding(24).background(.white)
        }.environment(\.locale, locale).environment(\.colorScheme, .light)
    }
}

/// Geometry follows BCWalkStepDetailView: 190pt header, 110pt metrics, 160pt chart.
struct StepsOriginalDetails: View {
    let data: StepsPresentation
    var isMale = false
    var showsBackground = true
    @Environment(\.locale) private var locale
    private var reached: Bool { data.steps.map { $0 >= (data.goal ?? Int.max) } ?? false }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 375, max(0, geometry.size.height - 12) / 460)
            ZStack(alignment: .top) {
                if showsBackground { CardDetailThemeBackground() }
                VStack(spacing: 0) {
                    VStack(spacing: 16 * scale) {
                        ZStack {
                            Circle().stroke(CalendarTheme.selected.detailTextColor.opacity(0.2), lineWidth: 2)
                            if let steps = data.steps, let goal = data.goal, goal > 0 {
                                Circle().trim(from: 0, to: min(1, CGFloat(steps) / CGFloat(goal)))
                                    .stroke(CalendarTheme.selected.detailTextColor, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                            }
                            VStack(spacing: 6 * scale) {
                                Text(reached ? localized("steps.checkInSuccess", locale) : data.day == LocalDay(date: .now) ? localized("steps.today", locale) : data.day.rawValue)
                                    .font(.system(size: (reached ? 15 : 13) * scale, weight: reached ? .bold : .regular))
                                    .accessibilityIdentifier(reached ? "steps.goalReached" : "steps.date")
                                Text(data.steps.map { $0.formatted(.number.locale(locale)) } ?? "—")
                                    .font(.custom("DINCondensedC", size: 30 * scale)).frame(height: 24 * scale)
                                    .accessibilityIdentifier("steps.count")
                                Text(data.goal.map { String(format: localized("steps.goal %lld", locale), Int64($0)) } ?? localized("profile.noSteps", locale))
                                    .font(.system(size: 12 * scale)).padding(.top, 8 * scale)
                            }.lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 8)
                        }.frame(width: 130 * scale, height: 130 * scale)
                        Text(StepsDistanceComparison.text(meters: data.distance, locale: locale))
                            .font(.system(size: 12 * scale)).lineLimit(1).minimumScaleFactor(0.7)
                    }.padding(.top, 16 * scale).frame(maxWidth: .infinity).frame(height: 190 * scale, alignment: .top)
                        .foregroundStyle(CalendarTheme.selected.detailTextColor)
                    HStack(alignment: .top, spacing: 0) {
                        metric(data.distance.map { ($0 / 1000).formatted(.number.precision(.fractionLength(2)).locale(locale)) } ?? "—", label: "unit.kilometers", identifier: "steps.distance", scale: scale)
                        metric(data.estimatedKilocalories.map(String.init) ?? "—", label: "steps.kcal", identifier: "steps.energy", scale: scale)
                        metric(data.intraday?.estimatedActiveMinutes.map { "\($0 / 60)h \($0 % 60)m" } ?? "—", label: "steps.activeTime", identifier: "steps.activeMinutes", scale: scale)
                    }.padding(.horizontal, 15 * scale).padding(.top, 26 * scale).frame(height: 110 * scale, alignment: .top)
                    StepsOriginalChart(data: data).padding(.horizontal, 15 * scale).frame(height: 160 * scale)
                    Spacer(minLength: 0)
                }.frame(width: 375 * scale).padding(.top, 12)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func metric(_ value: String, label: String, identifier: String, scale: CGFloat) -> some View {
        VStack(spacing: 7 * scale) {
            Text(value).font(.custom("DINCondensedC", size: 33 * scale)).frame(height: 35 * scale)
                .foregroundStyle(Color(white: 0.16)).accessibilityIdentifier(identifier)
            Text(LocalizedStringKey(label)).font(.system(size: 12 * scale)).foregroundStyle(Color(white: 0.3))
        }.lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
    }
}

struct StepsOriginalChart: View {
    let data: StepsPresentation
    @Environment(\.locale) private var locale
    private var hours: [StepIntraday.Hour] { data.intraday?.hours(timeZoneID: data.timeZoneID) ?? [] }
    private var maximum: Int {
        let value = hours.compactMap(\.steps).max() ?? 0
        return value == 0 ? 100 : Int(Double(value) * (value < 100 ? 2.5 : 1.25)) / 10 * 10 + 10
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 345
            let top = 32 * scale
            let plotHeight = geometry.size.height - 52 * scale
            let slot = (geometry.size.width - 40 * scale) / 24
            ZStack(alignment: .topLeading) {
                Text("steps.chartTitle").font(.system(size: 10 * scale)).offset(y: 10 * scale)
                ForEach(0..<3) { index in
                    Rectangle().fill(Color(hex: 0x48484D).opacity(index == 2 ? 0.2 : 0.1))
                        .frame(height: 0.5).offset(y: top + plotHeight * CGFloat(index) / 2)
                    if index < 2 {
                        Text(String(maximum / (index + 1))).font(.system(size: 10 * scale))
                            .offset(y: top + plotHeight * CGFloat(index) / 2 + 4)
                    }
                }
                ForEach(hours) { hour in
                    if let steps = hour.steps {
                        let calendar = Calendar(identifier: .gregorian)
                        let components = calendar.dateComponents(in: TimeZone(identifier: data.timeZoneID) ?? .current, from: hour.start)
                        let index = CGFloat(components.hour ?? 0)
                        let height = min(plotHeight, max(5 * scale, plotHeight * CGFloat(steps) / CGFloat(maximum)))
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(Color(hex: steps > 0 ? 0x56DDCA : 0xC1E8E3))
                            .frame(width: 6 * scale, height: height)
                            .offset(x: 25 * scale + index * slot, y: top + plotHeight - height)
                            .accessibilityLabel(Text(verbatim: "\(Int(index)):00"))
                            .accessibilityValue(Text(verbatim: String(steps)))
                    }
                }
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    Text(verbatim: "\(hour):00").font(.system(size: 10 * scale))
                        .offset(x: 15 * scale + CGFloat(hour) * slot, y: top + plotHeight + 5 * scale)
                }
                if hours.isEmpty {
                    Text("steps.intradayMissing").font(.system(size: 14 * scale))
                        .frame(maxWidth: .infinity).offset(y: top + plotHeight / 3)
                        .accessibilityIdentifier("steps.intradayMissing")
                }
            }.foregroundStyle(Color(white: 0.3))
        }.accessibilityIdentifier("steps.hourlyChart")
    }
}

struct StepsOriginalCard: View {
    let data: StepsPresentation
    var encouragement: String? = nil
    var showsBackground = true
    @Environment(\.locale) private var locale
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 375
            let cityHeight = geometry.size.width * 272 / 750
            let artworkScale = scale > 1 ? 1.2 : scale < 1 ? 0.9 : 1.05
            ZStack(alignment: .top) {
                if showsBackground { CardDetailThemeBackground() }
                Circle().fill(CalendarTheme.selected.color.opacity(0.10))
                    .frame(width: 272 * scale, height: 272 * scale).offset(y: 98)
                VStack(spacing: 5) {
                    Text(String(format: localized("steps.walked %@", locale), data.steps.map { $0.formatted(.number.locale(locale)) } ?? "—"))
                        .font(.system(size: 24, weight: .bold)).accessibilityIdentifier("steps.poster.count")
                    Text(StepsDistanceComparison.text(meters: data.distance, locale: locale)).font(.system(size: 13))
                }.foregroundStyle(CalendarTheme.selected.detailTextColor)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 15).padding(.top, 25)
                Image("card_icon_walk_complete").resizable().scaledToFit()
                    .frame(width: 330 * artworkScale, height: 390 * artworkScale)
                    .scaleEffect(0.8)
                    .position(x: geometry.size.width / 2, y: (geometry.size.height - cityHeight) / 2 - 10).accessibilityHidden(true)
            }.overlay(alignment: .bottom) {
                Text(verbatim: encouragement ?? localized("entry.encouragement.general", locale))
                    .font(.system(size: 17 * scale, weight: .bold)).foregroundStyle(Color(white: 0.16))
                    .multilineTextAlignment(.center).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(0, geometry.size.width - 60 * scale))
                    .padding(.bottom, cityHeight + 16 * scale)
            }.clipped()
        }
    }
}

@MainActor enum StepsPosterRenderer {
    static func render(data: StepsPresentation, style: StepsPosterStyle, locale: Locale, isMale: Bool = false, encouragement: String? = nil) -> UIImage? {
        guard data.steps != nil else { return nil }
        let renderer = ImageRenderer(content: StepsPoster(data: data, style: style, locale: locale, isMale: isMale, encouragement: encouragement).frame(width: 390))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Same comparison thresholds as PunchCard; stable selection avoids changing on sensor refresh.
enum StepsDistanceComparison {
    static let kilometers = [0.007, 0.02, 0.0255, 0.12, 0.26, 0.4, 0.468, 0.58, 0.6, 1.67, 2.76, 8.844, 40.26, 105, 0.0001, 0.0004]
    static func text(meters: Double?, locale: Locale) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return localized("steps.noData", locale) }
        for (index, unit) in kilometers.enumerated() {
            let count = meters / 1000 / unit
            if (1...20).contains(count) {
                return "≈" + String(format: localized("steps.distanceComparison.\(index) %@", locale), String(format: "%.0f", count))
            }
        }
        return localized("steps.distanceFallback", locale)
    }
}
