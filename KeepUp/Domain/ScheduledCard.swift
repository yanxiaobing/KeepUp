import Foundation

struct ScheduledCard: Identifiable, Equatable, Sendable {
    let cardID: String
    let day: LocalDay
    var note: String
    var id: String { cardID + ":" + day.rawValue }
}

struct WakeUpRecord: Codable, Equatable, Sendable {
    let time: Date
    let recordedAt: Date
    let timeZoneID: String
    var isEarly: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        return (5..<9).contains(calendar.component(.hour, from: recordedAt))
    }
}
