import Foundation

/// A sensor measurement is independent of a completed check-in.
struct StepRecord: Codable, Equatable, Sendable {
    let day: LocalDay
    let timeZoneID: String
    let steps: Int
    let distance: Double?
    let measuredAt: Date
    let goal: Int?
    var checkInDeleted: Bool? = nil
}
