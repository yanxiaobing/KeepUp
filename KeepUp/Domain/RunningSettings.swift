import Foundation

/// A single typed preference keeps the full settings page and in-workout controls in sync.
struct RunningSettings: Codable, Equatable, Sendable, Defaults.Serializable {
    var confirmBeforeStart = true
    var defaultKind = RunningKind.outdoor
    var countdown = false
    var voice = true
    var autoPause = false
    var autoLock = false
    var keepScreenOn = false
    var satelliteMap = false
    var voiceIntervalMeters = 1_000
    var voiceStyle = RunningVoiceStyle.calm

    static let voiceIntervals = [500, 1_000, 2_000, 5_000]
    var effectiveVoiceInterval: Int { Self.voiceIntervals.contains(voiceIntervalMeters) ? voiceIntervalMeters : 1_000 }
    var defaultRunningKind: RunningKind { defaultKind == .indoor ? .indoor : .outdoor }
}

enum RunningVoiceStyle: String, Codable, CaseIterable, Sendable {
    case bright, calm
    var titleKey: String { "runningSettings.voice." + rawValue }
    var bundleName: String { self == .bright ? "audio" : "audio2" }
}

extension Defaults.Keys {
    static let runningSettings = Key<RunningSettings>("runningSettings", default: RunningSettings(), suite: AppPreferences.store)
}

enum RunningEvent: Sendable {
    case countdown(Int)
    case countdownCancelled
    case started(RunningSession)
    case updated(RunningSession)
    case paused(RunningSession, automatic: Bool)
    case resumed(RunningSession, automatic: Bool)
    case restored(RunningSession)
    case finished(RunningSession)
    case discarded
}

extension RunningSettings {
    init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        confirmBeforeStart = try values.decodeIfPresent(Bool.self, forKey: .confirmBeforeStart) ?? confirmBeforeStart
        defaultKind = try values.decodeIfPresent(RunningKind.self, forKey: .defaultKind) ?? defaultKind
        countdown = try values.decodeIfPresent(Bool.self, forKey: .countdown) ?? countdown
        voice = try values.decodeIfPresent(Bool.self, forKey: .voice) ?? voice
        autoPause = try values.decodeIfPresent(Bool.self, forKey: .autoPause) ?? autoPause
        autoLock = try values.decodeIfPresent(Bool.self, forKey: .autoLock) ?? autoLock
        keepScreenOn = try values.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? keepScreenOn
        satelliteMap = try values.decodeIfPresent(Bool.self, forKey: .satelliteMap) ?? satelliteMap
        voiceIntervalMeters = try values.decodeIfPresent(Int.self, forKey: .voiceIntervalMeters) ?? voiceIntervalMeters
        voiceStyle = try values.decodeIfPresent(RunningVoiceStyle.self, forKey: .voiceStyle) ?? voiceStyle
    }
}
