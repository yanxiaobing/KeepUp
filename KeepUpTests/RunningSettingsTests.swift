import Foundation
import Testing
@testable import KeepUp

@Test func runningSettingsRetainSavedChoicesWhenNewFieldsAreMissing() throws {
    let data = Data(#"{"voice":false,"countdown":true,"defaultKind":"indoor"}"#.utf8)
    let settings = try JSONDecoder().decode(RunningSettings.self, from: data)
    #expect(!settings.voice)
    #expect(settings.countdown)
    #expect(settings.defaultRunningKind == .indoor)
    #expect(settings.confirmBeforeStart)
    #expect(!settings.autoPause)
    #expect(!settings.autoLock)
    #expect(!settings.keepScreenOn)
    #expect(settings.effectiveVoiceInterval == 1_000)
    #expect(settings.voiceStyle == .calm)
}

@Test func runningSettingsPersistTogetherAndResetToOriginalDefaults() throws {
    let name = "KeepUpRunningSettings-\(UUID())"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let key = Defaults.Key<RunningSettings>("runningSettings", default: RunningSettings(), suite: suite)
    var chosen = RunningSettings()
    chosen.confirmBeforeStart = false
    chosen.defaultKind = .indoor
    chosen.countdown = true
    chosen.autoPause = true
    chosen.autoLock = true
    chosen.keepScreenOn = true
    chosen.satelliteMap = true
    chosen.voiceIntervalMeters = 500
    chosen.voiceStyle = .bright
    Defaults[key] = chosen
    let reopened = try #require(UserDefaults(suiteName: name))
    let reopenedKey = Defaults.Key<RunningSettings>("runningSettings", default: RunningSettings(), suite: reopened)
    #expect(Defaults[reopenedKey] == chosen)
    Defaults.reset(key)
    #expect(Defaults[reopenedKey] == RunningSettings())
}

@Test func runningSettingsRejectUnsupportedFrequencyAndDefaultCyclingSelection() {
    var settings = RunningSettings()
    settings.voiceIntervalMeters = 0
    settings.defaultKind = .cycling
    #expect(settings.effectiveVoiceInterval == 1_000)
    #expect(settings.defaultRunningKind == .outdoor)
}
