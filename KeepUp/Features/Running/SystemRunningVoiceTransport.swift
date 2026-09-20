import AVFoundation
import Foundation

/// Serial audio-file / speech playback. A new announcement replaces all pending parts.
@MainActor final class SystemRunningVoiceTransport: NSObject, RunningVoiceTransport, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private var pending: [RunningVoicePart] = []
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceID: ObjectIdentifier?
    private var language = "en-US"
    private var sessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ parts: [RunningVoicePart], language: String) {
        stop()
        guard !parts.isEmpty else { return }
        self.language = language
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try audio.setActive(true)
            sessionActive = true
        } catch { return }
        pending = parts
        playNext()
    }

    func stop() {
        pending.removeAll()
        player?.delegate = nil
        player?.stop()
        player = nil
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }

    private func playNext() {
        player = nil
        utteranceID = nil
        while !pending.isEmpty {
            let part = pending.removeFirst()
            switch part {
            case .recording(let bundle, let name, let fallback):
                if let root = Bundle.main.url(forResource: bundle, withExtension: "bundle") {
                    let url = root.appendingPathComponent(name).appendingPathExtension("mp3")
                    if let audio = try? AVAudioPlayer(contentsOf: url) {
                        audio.delegate = self
                        player = audio
                        if audio.play() { return }
                        player = nil
                    }
                }
                if !fallback.isEmpty { speak(fallback, language: language); return }
            case .speech(let text, let language):
                if !text.isEmpty { speak(text, language: language); return }
            }
        }
        deactivate()
    }

    private func speak(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    private func deactivate() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map({ ObjectIdentifier($0) }) == identifier else { return }
            if flag { self.playNext() } else { self.stop() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map({ ObjectIdentifier($0) }) == identifier else { return }
            self.stop()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.playNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.stop()
        }
    }
}
