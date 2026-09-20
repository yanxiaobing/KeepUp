#if DEBUG
import Foundation

enum EntryPosterFixtures {
    static func prepare(repository: any CheckInRepository, now: Date = .now) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = LocalDay(date: now)
        let startDate = calendar.date(byAdding: .day, value: -10, to: now)!
        let endDate = calendar.date(byAdding: .day, value: 10, to: now)!
        var profile = UserProfile()
        profile.nickname = "KeepUp"
        profile.createdAt = startDate
        try await repository.saveProfile(profile)
        let target = WeightTarget(id: "poster-weight-target", initial: 65, target: 60,
                                  start: LocalDay(date: startDate), end: LocalDay(date: endDate))
        try await repository.saveWeightTarget(target, now: startDate)
        try await repository.add(CheckInDraft(id: "poster.ui-weight", cardID: "punchcard.50", day: today,
                                             timeZoneID: TimeZone.current.identifier, quantity: 59.5, note: ""), now: now)
        for (id, quantity) in [("poster.ui-total.1", 30.0), ("poster.ui-other", 15.5)] {
            try await repository.add(CheckInDraft(id: id, cardID: "preset.exercise", day: today,
                                                 timeZoneID: TimeZone.current.identifier, quantity: quantity, note: ""), now: now)
        }
    }
}
#endif
