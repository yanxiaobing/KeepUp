import Foundation
import Testing
@testable import KeepUp

@MainActor private final class RecordingVoiceTransport: RunningVoiceTransport {
    var announcements: [[RunningVoicePart]] = []
    var pending: [RunningVoicePart] = []
    var stopCount = 0
    func play(_ parts: [RunningVoicePart], language: String) {
        pending = parts
        announcements.append(parts)
    }
    func stop() { stopCount += 1; pending.removeAll() }
}

private let voiceOrigin = Date(timeIntervalSince1970: 1_800_000_000)
private func voiceSession(distance: Double = 0, seconds: Double = 0, kind: RunningKind = .outdoor) -> RunningSession {
    var session = RunningSession(id: "voice-test", startedAt: voiceOrigin, kind: kind)
    session.distanceMeters = distance
    session.updatedAt = voiceOrigin.addingTimeInterval(seconds)
    return session
}
private func spokenText(_ parts: [RunningVoicePart]) -> String {
    parts.compactMap { part in
        if case .speech(let text, _) = part { return text }
        return nil
    }.joined(separator: " ")
}

@Test @MainActor func runningVoiceUsesHighestNewMilestoneOnlyAndIgnoresDuplicateOrBackwardDistance() {
    let transport = RecordingVoiceTransport(), settings = RunningSettings(), locale = Locale(identifier: "en")
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.started(voiceSession()), settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 999, seconds: 300)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 1)
    coach.handle(.updated(voiceSession(distance: 3_200, seconds: 960)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 2)
    let text = spokenText(transport.pending)
    #expect(text.contains("3 kilometers"))
    #expect(text.contains("16 minutes"))
    #expect(text.contains("5 minutes per kilometer"))
    coach.handle(.updated(voiceSession(distance: 3_200, seconds: 961)), settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 2_900, seconds: 962)), settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 3_500, seconds: 963)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 2)
}

@Test @MainActor func runningVoiceMuteClearsPendingAndReenableDoesNotReplayProgress() {
    let transport = RecordingVoiceTransport(), locale = Locale(identifier: "en")
    var settings = RunningSettings()
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.started(voiceSession()), settings: settings, locale: locale)
    settings.voice = false
    coach.update(settings: settings, locale: locale)
    #expect(transport.pending.isEmpty)
    #expect(transport.stopCount == 1)
    coach.handle(.updated(voiceSession(distance: 2_500, seconds: 750)), settings: settings, locale: locale)
    settings.voice = true
    coach.update(settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 2_600, seconds: 780)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 1)
    coach.handle(.updated(voiceSession(distance: 3_000, seconds: 900)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 2)
}

@Test @MainActor func runningVoiceIntervalChangesAndRestorationDoNotReplayOldMilestones() {
    let transport = RecordingVoiceTransport(), locale = Locale(identifier: "en")
    var settings = RunningSettings()
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.restored(voiceSession(distance: 2_500, seconds: 750)), settings: settings, locale: locale)
    #expect(transport.announcements.isEmpty)
    settings.voiceIntervalMeters = 500
    coach.update(settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 2_600, seconds: 780)), settings: settings, locale: locale)
    #expect(transport.announcements.isEmpty)
    coach.handle(.updated(voiceSession(distance: 3_000, seconds: 900)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 1)
    settings.voiceIntervalMeters = 2_000
    coach.update(settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 3_900, seconds: 1_170)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 1)
    coach.handle(.updated(voiceSession(distance: 4_000, seconds: 1_200)), settings: settings, locale: locale)
    #expect(transport.announcements.count == 2)
}

@Test @MainActor func runningVoiceChineseHalfKilometerUsesSelectedOriginalPackAndPaceSupplement() {
    let transport = RecordingVoiceTransport(), locale = Locale(identifier: "zh-Hans")
    var settings = RunningSettings()
    settings.voiceStyle = .bright
    settings.voiceIntervalMeters = 500
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.started(voiceSession()), settings: settings, locale: locale)
    coach.handle(.updated(voiceSession(distance: 500, seconds: 150)), settings: settings, locale: locale)
    let names = transport.pending.compactMap { part -> String? in
        if case .recording(let bundle, let name, _) = part { #expect(bundle == "audio"); return name }
        return nil
    }
    #expect(Array(names.prefix(5)) == ["alert", "zero", "point", "five", "runkilometer"])
    #expect(names.contains("time") && names.contains("minute") && names.contains("second"))
    #expect(spokenText(transport.pending).contains("配速"))
    settings.voiceStyle = .calm
    coach.preview(settings: settings, locale: locale)
    #expect(transport.pending == [.recording(bundle: "audio2", name: "startrun", fallback: localized("runningVoice.preview", locale))])
}

@Test @MainActor func runningVoiceCyclingSpeaksSpeedInsteadOfRunningPace() {
    let transport = RecordingVoiceTransport(), settings = RunningSettings(), locale = Locale(identifier: "en")
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.started(voiceSession(kind: .cycling)), settings: settings, locale: locale)
    #expect(spokenText(transport.pending) == "Ride started.")
    coach.handle(.updated(voiceSession(distance: 1_000, seconds: 120, kind: .cycling)), settings: settings, locale: locale)
    #expect(spokenText(transport.pending).contains("30.0 kilometers per hour"))
    #expect(!spokenText(transport.pending).contains("pace"))
}

@Test @MainActor func runningVoiceLifecycleCountdownAndDiscardReplacePendingSpeech() {
    let transport = RecordingVoiceTransport(), settings = RunningSettings(), locale = Locale(identifier: "en")
    let coach = RunningVoiceCoach(transport: transport)
    coach.handle(.countdown(3), settings: settings, locale: locale)
    coach.handle(.countdown(3), settings: settings, locale: locale)
    #expect(transport.announcements.count == 1)
    coach.handle(.countdown(2), settings: settings, locale: locale)
    #expect(spokenText(transport.pending) == "2")
    coach.handle(.countdownCancelled, settings: settings, locale: locale)
    #expect(transport.pending.isEmpty)
    var session = voiceSession(distance: 200, seconds: 60)
    coach.handle(.started(session), settings: settings, locale: locale)
    session.pause(at: voiceOrigin.addingTimeInterval(60))
    coach.handle(.paused(session, automatic: true), settings: settings, locale: locale)
    #expect(spokenText(transport.pending).contains("automatically paused"))
    session.resume(at: voiceOrigin.addingTimeInterval(80))
    coach.handle(.resumed(session, automatic: true), settings: settings, locale: locale)
    #expect(spokenText(transport.pending) == "Workout resumed.")
    session.finish(at: voiceOrigin.addingTimeInterval(90))
    coach.handle(.finished(session), settings: settings, locale: locale)
    let count = transport.announcements.count
    coach.handle(.finished(session), settings: settings, locale: locale)
    #expect(transport.announcements.count == count)
    #expect(spokenText(transport.pending).contains("record is saved"))
    coach.handle(.discarded, settings: settings, locale: locale)
    #expect(transport.pending.isEmpty)
}

@Test @MainActor func runningVoiceClosingPreviewDoesNotStopANewWorkoutAnnouncement() {
    let transport = RecordingVoiceTransport(), settings = RunningSettings(), locale = Locale(identifier: "en")
    let coach = RunningVoiceCoach(transport: transport)
    coach.preview(settings: settings, locale: locale)
    coach.stopPreview()
    #expect(transport.pending.isEmpty)
    coach.preview(settings: settings, locale: locale)
    coach.handle(.started(voiceSession()), settings: settings, locale: locale)
    let stops = transport.stopCount
    coach.stopPreview()
    #expect(transport.stopCount == stops)
    #expect(spokenText(transport.pending) == "Run started.")
}

@Test func runningVoiceOriginalBundlesContainSharedLifecycleAndNumericRecordings() throws {
    for bundle in ["audio", "audio2"] {
        let root = try #require(Bundle.main.url(forResource: bundle, withExtension: "bundle"))
        for name in ["startrun", "stop", "continue", "complete", "countdownone", "countdowntwo", "countdownthree", "zero", "one", "two", "five", "point", "hundred", "thousand", "runkilometer", "time", "hour", "minute", "second"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).appendingPathExtension("mp3").path))
        }
    }
}
