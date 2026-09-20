import Foundation

enum CardUnit: String, Codable, Sendable, CaseIterable {
    case none, minutes, count, floors, steps, kilograms, kilometers, meters, items, seconds
    var titleKey: String { "unit.\(rawValue)" }
    var requiresWholeNumber: Bool { [.count, .floors, .steps, .items, .seconds, .meters].contains(self) }
}

struct HabitCard: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let titleKey: String
    let symbol: String
    let unit: CardUnit
    let sortOrder: Int
    var isCustom: Bool { id.hasPrefix("custom.") }

    static var starters: [HabitCard] { OriginalCatalog.configuration.legacyStarters }
}

struct CheckInEntry: Identifiable, Equatable, Sendable {
    let id: String
    let cardID: String
    let day: LocalDay
    let timeZoneID: String
    let createdAt: Date
    let quantity: Double?
    let unit: CardUnit
    let note: String
}

struct CheckInDraft: Sendable {
    var wakeTime: Date? = nil
    var id = UUID().uuidString
    let cardID: String
    let day: LocalDay
    let timeZoneID: String
    let quantity: Double?
    let note: String
}

struct LocalSnapshot: Sendable {
    let cards: [HabitCard]
    let entries: [CheckInEntry]
    var profile: UserProfile? = nil
    var content: [String: EntryContentRecord] = [:]
    var targets: [CardTarget] = []
    var schedules: [ScheduledCard] = []
    var weightTarget: WeightTarget? = nil
    var weights: [String: WeightRecord] = [:]
    var wakeUps: [String: WakeUpRecord] = [:]
    var steps: [String: StepRecord] = [:]
    var activeRun: RunningSession? = nil
    var archivedCardIDs: Set<String> = []
    static let empty = LocalSnapshot(cards: [], entries: [])
}

enum StoreError: Error, Equatable {
    case invalidWeightTarget, duplicateWakeUp, invalidSchedule, invalidCustomCard, invalidTarget, invalidContent, invalidProfile, notOpen, newerSchema, invalidCard, invalidQuantity, invalidDate, noteTooLong, corruptRecord

    var messageKey: String {
        switch self {
        case .invalidWeightTarget: "weight.invalidTarget"
        case .duplicateWakeUp: "wake.duplicate"
        case .invalidSchedule: "schedule.invalid"
        case .invalidCustomCard: "custom.invalidName"
        case .invalidTarget: "reminder.invalid"
        case .invalidContent: "error.content"
        case .invalidProfile: "error.profile"
        case .newerSchema: "error.newerSchema"
        case .invalidQuantity: "error.quantity"
        case .invalidDate: "error.date"
        case .noteTooLong: "error.note"
        default: "error.storage"
        }
    }
}
