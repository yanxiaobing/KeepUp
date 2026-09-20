import Foundation

enum RunningVoicePart: Equatable, Sendable {
    case recording(bundle: String, name: String, fallback: String)
    case speech(text: String, language: String)
}

@MainActor protocol RunningVoiceTransport: AnyObject {
    /// Replace the complete previous announcement, including anything still queued.
    func play(_ parts: [RunningVoicePart], language: String)
    func stop()
}

/// Events are issued after state changes; .finished is issued only after successful persistence.
@MainActor final class RunningVoiceCoach {
    private let transport: any RunningVoiceTransport
    private var settings: RunningSettings?
    private var localeID: String?
    private var sessionID: String?
    private var highWaterDistance: Double = 0
    private var lastTransition: String?
    private var lastCountdown: Int?
    private var isPreviewing = false

    init(transport: any RunningVoiceTransport = SystemRunningVoiceTransport()) { self.transport = transport }

    func update(settings: RunningSettings, locale: Locale) {
        if let previous = self.settings,
           previous.voice != settings.voice || previous.voiceStyle != settings.voiceStyle || localeID != locale.identifier {
            transport.stop()
            isPreviewing = false
        }
        self.settings = settings
        localeID = locale.identifier
    }

    func handle(_ event: RunningEvent, settings: RunningSettings, locale: Locale) {
        update(settings: settings, locale: locale)
        switch event {
        case .discarded:
            transport.stop()
            isPreviewing = false
            sessionID = nil
            highWaterDistance = 0
            lastTransition = nil
            lastCountdown = nil
        case .countdownCancelled:
            transport.stop()
            isPreviewing = false
            lastCountdown = nil
        case .countdown(let number):
            guard (1...3).contains(number), lastCountdown != number else { return }
            lastCountdown = number
            guard settings.voice else { return }
            let name = [1: "countdownone", 2: "countdowntwo", 3: "countdownthree"][number]!
            announce(recordings: [(name, String(number))], fallback: String(number), settings: settings, locale: locale)
        case .restored(let session):
            transport.stop()
            isPreviewing = false
            sessionID = session.id
            highWaterDistance = safeDistance(session.distanceMeters)
            lastTransition = "restored:\(session.id):\(session.revision)"
            lastCountdown = nil
        case .started(let session):
            if sessionID != session.id {
                sessionID = session.id
                highWaterDistance = safeDistance(session.distanceMeters)
                lastTransition = nil
            }
            lastCountdown = nil
            transition("started", session: session, settings: settings, locale: locale,
                       recordings: session.kind == .cycling ? [("ride_comeon", localized("runningVoice.cyclingStarted", locale))] : [("startrun", localized("runningVoice.started", locale))],
                       key: session.kind == .cycling ? "runningVoice.cyclingStarted" : "runningVoice.started")
        case .paused(let session, let automatic):
            let key = automatic ? "runningVoice.autoPaused" : "runningVoice.paused"
            transition(automatic ? "autoPaused" : "paused", session: session, settings: settings, locale: locale,
                       recordings: [(session.kind == .cycling ? "ride_stop" : automatic ? "runningstop" : "stop", localized(key, locale))], key: key)
        case .resumed(let session, _):
            transition("resumed", session: session, settings: settings, locale: locale,
                       recordings: [(session.kind == .cycling ? "ride_continue" : "continue", localized("runningVoice.resumed", locale))], key: "runningVoice.resumed")
        case .finished(let session):
            transition("finished", session: session, settings: settings, locale: locale,
                       recordings: [(session.kind == .cycling ? "ride_yeah" : "complete", localized("runningVoice.finished", locale))], key: "runningVoice.finished")
        case .updated(let session):
            let distance = safeDistance(session.distanceMeters)
            guard sessionID == session.id else {
                sessionID = session.id
                highWaterDistance = distance
                lastTransition = nil
                return
            }
            let previous = highWaterDistance
            highWaterDistance = max(highWaterDistance, distance)
            // Always advance while muted. Frequency changes compare against actual progress,
            // so turning voice on or choosing a shorter interval never replays passed milestones.
            let interval = Double(settings.effectiveVoiceInterval)
            let milestone = floor(distance / interval) * interval
            guard session.phase == .running, settings.voice, milestone > previous else { return }
            report(session, milestone: milestone, settings: settings, locale: locale)
        }
    }

    /// Explicit audition remains available when automatic workout announcements are disabled.
    func preview(settings: RunningSettings, locale: Locale) {
        update(settings: settings, locale: locale)
        let text = localized("runningVoice.preview", locale)
        if isChinese(locale) {
            transport.play([.recording(bundle: settings.voiceStyle.bundleName, name: "startrun", fallback: text)], language: "zh-CN")
        } else { transport.play([.speech(text: text, language: "en-US")], language: "en-US") }
        isPreviewing = true
    }

    func stopPreview() {
        guard isPreviewing else { return }
        transport.stop()
        isPreviewing = false
    }

    private func transition(_ name: String, session: RunningSession, settings: RunningSettings, locale: Locale,
                            recordings: [(String, String)], key: String) {
        if sessionID != session.id {
            sessionID = session.id
            highWaterDistance = safeDistance(session.distanceMeters)
        } else { highWaterDistance = max(highWaterDistance, safeDistance(session.distanceMeters)) }
        let identifier = "\(name):\(session.id):\(session.revision)"
        guard lastTransition != identifier else { return }
        lastTransition = identifier
        guard settings.voice else { return }
        announce(recordings: recordings, fallback: localized(key, locale), settings: settings, locale: locale)
    }

    private func announce(recordings: [(String, String)], fallback: String, settings: RunningSettings, locale: Locale) {
        isPreviewing = false
        let language = isChinese(locale) ? "zh-CN" : "en-US"
        let parts: [RunningVoicePart] = isChinese(locale)
            ? recordings.map { .recording(bundle: settings.voiceStyle.bundleName, name: $0.0, fallback: $0.1) }
            : [.speech(text: fallback, language: language)]
        transport.play(parts, language: language)
    }

    private func report(_ session: RunningSession, milestone: Double, settings: RunningSettings, locale: Locale) {
        let seconds = session.elapsed(at: session.updatedAt)
        guard seconds.isFinite, seconds > 0, seconds <= 604_800, milestone > 0 else { return }
        let kilometers = milestone / 1_000
        let distance = kilometers.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        let duration = durationText(seconds, locale: locale)
        let metric: String
        if session.kind == .cycling {
            let speed = (session.distanceMeters / seconds * 3.6).formatted(.number.precision(.fractionLength(1)).locale(locale))
            metric = String(format: localized("runningVoice.speed %@", locale), speed)
        } else {
            let pace = seconds / (session.distanceMeters / 1_000)
            metric = String(format: localized("runningVoice.pace %@", locale), durationText(pace, locale: locale))
        }
        let text = String(format: localized("runningVoice.report %@ %@ %@", locale), distance, duration, metric)
        isPreviewing = false
        if isChinese(locale) {
            let bundle = settings.voiceStyle.bundleName
            var parts: [RunningVoicePart] = [.recording(bundle: bundle, name: "alert", fallback: "")]
            if session.kind == .cycling { parts.append(.recording(bundle: bundle, name: "ride_reach", fallback: localized("runningVoice.cyclingReached", locale))) }
            parts += numberParts(kilometers, bundle: bundle)
            parts.append(.recording(bundle: bundle, name: "runkilometer", fallback: "公里"))
            parts.append(.recording(bundle: bundle, name: "time", fallback: "用时"))
            parts += timeParts(seconds, bundle: bundle)
            // Original packs have no pace/speed vocabulary. Complete these metrics using
            // system Chinese speech; missing legacy cycling clips use the same fallback.
            parts.append(.speech(text: metric, language: "zh-CN"))
            transport.play(parts, language: "zh-CN")
        } else { transport.play([.speech(text: text, language: "en-US")], language: "en-US") }
    }

    private func durationText(_ seconds: Double, locale: Locale) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let value = Int(seconds.rounded())
        var components: [String] = []
        if value >= 3_600 { components.append(String(format: localized("runningVoice.hours %lld", locale), Int64(value / 3_600))) }
        if value / 60 % 60 > 0 { components.append(String(format: localized("runningVoice.minutes %lld", locale), Int64(value / 60 % 60))) }
        if value % 60 > 0 || components.isEmpty { components.append(String(format: localized("runningVoice.seconds %lld", locale), Int64(value % 60))) }
        return components.joined(separator: " ")
    }

    private func numberParts(_ value: Double, bundle: String) -> [RunningVoicePart] {
        let integer = Int(value)
        let names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        func clip(_ name: String, _ fallback: String) -> RunningVoicePart { .recording(bundle: bundle, name: name, fallback: fallback) }
        func integerParts(_ number: Int) -> [RunningVoicePart] {
            if number == 0 { return [clip("zero", "零")] }
            var result: [RunningVoicePart] = [], remainder = number, omittedZero = false
            for (divisor, unit) in [(1_000, "thousand"), (100, "hundred"), (10, "ten"), (1, "")] {
                let digit = remainder / divisor
                remainder %= divisor
                if digit == 0 { if !result.isEmpty && remainder > 0 { omittedZero = true }; continue }
                if omittedZero { result.append(clip("zero", "零")); omittedZero = false }
                if !(divisor == 10 && digit == 1 && result.isEmpty) { result.append(clip(names[digit], String(digit))) }
                if !unit.isEmpty { result.append(clip(unit, [1_000: "千", 100: "百", 10: "十"][divisor]!)) }
            }
            return result
        }
        var result = integerParts(integer)
        let fraction = Int((value * 10).rounded()) % 10
        if fraction != 0 { result += [clip("point", "点"), clip(names[fraction], String(fraction))] }
        return result
    }

    private func timeParts(_ seconds: Double, bundle: String) -> [RunningVoicePart] {
        let value = Int(seconds.rounded())
        var result: [RunningVoicePart] = []
        for (count, clip, fallback) in [(value / 3_600, "hour", "小时"), (value / 60 % 60, "minute", "分钟"), (value % 60, "second", "秒")] where count > 0 {
            result += numberParts(Double(count), bundle: bundle)
            result.append(.recording(bundle: bundle, name: clip, fallback: fallback))
        }
        return result.isEmpty ? numberParts(0, bundle: bundle) + [.recording(bundle: bundle, name: "second", fallback: "秒")] : result
    }

    private func isChinese(_ locale: Locale) -> Bool { locale.identifier.hasPrefix("zh") }
    private func safeDistance(_ distance: Double) -> Double { distance.isFinite ? min(1_000_000, max(0, distance)) : 0 }
}
