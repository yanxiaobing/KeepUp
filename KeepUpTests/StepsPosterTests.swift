import Foundation
import Testing
@testable import KeepUp

private let posterDay = LocalDay(rawValue: "2020-09-08")!
private let posterZone = TimeZone(identifier: "Pacific/Kiritimati")!
private func posterRecord(steps: Int = 6_500, distance: Double? = 4_225, goal: Int? = 5_000) -> StepRecord {
    StepRecord(day: posterDay, timeZoneID: posterZone.identifier, steps: steps, distance: distance,
               measuredAt: posterDay.date(in: posterZone), goal: goal)
}

@Test func stepPosterPreservesOldDateAndRejectsOtherDays() {
    let other = LocalDay(rawValue: "2026-09-20")!
    let reading = StepReading(day: other, timeZoneID: posterZone.identifier, steps: 9_999,
                              distance: 6_000, measuredAt: other.date(in: posterZone))
    let data = StepsPresentation(day: posterDay, reading: reading, saved: posterRecord(), goal: 9_000)
    #expect(data.day == posterDay)
    #expect(data.steps == 6_500)
    #expect(data.distance == 4_225)
    #expect(data.goal == 5_000)
    #expect(data.isSaved)
    #expect(data.dateLabel(locale: Locale(identifier: "en_US")) == "September 8, 2020")
    #expect(data.dateLabel(locale: Locale(identifier: "zh_Hans_CN")) == "2020年9月8日")
    let missing = StepsPresentation(day: other, reading: nil, saved: posterRecord(), goal: nil)
    #expect(missing.steps == nil)
    #expect(!missing.isSaved)
}

@Test @MainActor func stepPosterUnknownIsNotZeroAndCannotBeShared() {
    let unknown = StepsPresentation(day: posterDay, reading: nil, saved: nil, goal: nil)
    #expect(unknown.steps == nil && unknown.distance == nil && unknown.goal == nil)
    #expect(StepsPosterRenderer.render(data: unknown, style: .details, locale: .init(identifier: "en")) == nil)
    let zero = StepsPresentation(day: posterDay, reading: nil, saved: posterRecord(steps: 0, distance: nil, goal: nil), goal: 8_000)
    #expect(zero.steps == 0)
    #expect(zero.distance == nil)
    #expect(zero.goal == nil)
    #expect(zero.isSaved)
    #expect(StepsPosterRenderer.render(data: zero, style: .card, locale: .init(identifier: "en")) != nil)
}

@Test func stepPosterDoesNotLabelUnpersistedMeasurementAsSavedOrMixDistances() {
    let saved = posterRecord()
    let reading = StepReading(day: posterDay, timeZoneID: posterZone.identifier, steps: 7_000,
                              distance: nil, measuredAt: saved.measuredAt.addingTimeInterval(60))
    let data = StepsPresentation(day: posterDay, reading: reading, saved: saved, goal: 9_000)
    #expect(data.steps == 7_000)
    #expect(data.distance == nil)
    #expect(!data.isSaved)
    #expect(data.goal == 5_000)
    let same = StepReading(day: posterDay, timeZoneID: posterZone.identifier, steps: saved.steps,
                           distance: saved.distance, measuredAt: saved.measuredAt)
    #expect(StepsPresentation(day: posterDay, reading: same, saved: saved, goal: nil).isSaved)
    let stale = StepReading(day: posterDay, timeZoneID: posterZone.identifier, steps: 100,
                            distance: 10, measuredAt: saved.measuredAt.addingTimeInterval(-60))
    let latest = StepsPresentation(day: posterDay, reading: stale, saved: saved, goal: nil)
    #expect(latest.steps == saved.steps && latest.distance == saved.distance && latest.isSaved)
}

@Test @MainActor func stepPosterRendersCompleteDetailsAndCardsInBothLanguages() throws {
    let data = StepsPresentation(day: posterDay, reading: nil, saved: posterRecord(), goal: nil)
    for language in ["en_US", "zh_Hans_CN"] {
        for style in StepsPosterStyle.allCases {
            let image = try #require(StepsPosterRenderer.render(data: data, style: style, locale: Locale(identifier: language)))
            #expect(image.size.width == 390)
            #expect(image.size.height > 650 && image.size.height < 1_100)
            #expect(image.cgImage?.width == 1_170)
            Attachment.record(Array(try #require(image.pngData())), named: "steps-\(style.rawValue)-\(language).png")
        }
    }
}

@Test @MainActor func stepPosterRendersSavedIntradayAfterSensorWindowExpires() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = posterZone
    let start = calendar.startOfDay(for: posterDay.date(in: posterZone))
    let through = start.addingTimeInterval(14 * 3600 + 1200)
    let ranges = StepIntraday.ranges(day: posterDay, through: through, timeZone: posterZone)
    let detail = StepIntraday(intervals: ranges.enumerated().map { index, range in
        StepInterval(start: range.start, end: range.end, steps: index % 12 < 4 ? 50 : 0)
    }, measuredThrough: through)
    var saved = StepRecord(day: posterDay, timeZoneID: posterZone.identifier,
                           steps: detail.intervals.reduce(0) { $0 + ($1.steps ?? 0) }, distance: 4225,
                           measuredAt: through, goal: 5000)
    saved.intraday = detail
    let data = StepsPresentation(day: posterDay, reading: nil, saved: saved, goal: nil)
    #expect(data.intraday == detail)
    #expect(data.timeZoneID == posterZone.identifier)
    for language in ["en_US", "zh_Hans_CN"] {
        let image = try #require(StepsPosterRenderer.render(data: data, style: .details, locale: Locale(identifier: language)))
        #expect(image.size.height > 650 && image.size.height < 1_100)
        Attachment.record(Array(try #require(image.pngData())), named: "steps-intraday-\(language).png")
    }
}

@Test func restoredStepDistanceComparisonKeepsUnknownSeparateFromZero() {
    let chinese = Locale(identifier: "zh-Hans")
    #expect(StepsDistanceComparison.text(meters: nil, locale: chinese) == localized("steps.noData", chinese))
    #expect(StepsDistanceComparison.text(meters: .nan, locale: chinese) == localized("steps.noData", chinese))
    #expect(StepsDistanceComparison.text(meters: 0, locale: chinese) == "手机掉水里了？")
    #expect(StepsDistanceComparison.text(meters: 4_225, locale: chinese) == "≈16艘泰坦尼克号的长度")
    #expect(StepsDistanceComparison.text(meters: 4_225, locale: Locale(identifier: "en")) == "≈16 Titanic ship lengths")
}
