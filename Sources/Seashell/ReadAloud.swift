import AVFoundation
import SeashellCore

/// Read Aloud: text spoken on this Mac in the voice Spoken Content chose for
/// its language (see SpeechVoices). One reading at a time: a new one, or Stop
/// Reading, ends the last. While it reads, the shells breathe.
@MainActor
final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ReadAloud()

    private let synthesizer = AVSpeechSynthesizer()
    /// Readings asked for so far: one whose words are still being found
    /// (a scan, say) is dropped if another, or Stop Reading, came meanwhile.
    private var run = 0
    /// The utterance being spoken, to tell its end from an older one's.
    private var speaking: ObjectIdentifier?

    /// From the moment it's asked for (words still being found) until it ends.
    private(set) var isReading = false {
        didSet { SealView.isBreathing = isReading }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// A reading starts: whatever was being read stops. Pass the result to
    /// `read(_:run:)` once the words are found, or `cancel(run:)` if there are none.
    func begin() -> Int {
        stopSpeaking()
        run += 1
        isReading = true
        return run
    }

    func read(_ text: String) {
        read(text, run: begin())
    }

    func read(_ text: String, run: Int) {
        guard run == self.run, isReading else { return }
        let utterance = AVSpeechUtterance(string: text)
        let language = SpeechVoices.language(of: text)
        let voice = Self.voice(for: language)
        utterance.voice = voice
        speaking = ObjectIdentifier(utterance)
        Log.info("Read Aloud: \(text.count) characters (\(language ?? "language unknown")) in \(voice?.name ?? "the default voice")")
        synthesizer.speak(utterance)
    }

    /// Nothing to read after all.
    func cancel(run: Int) {
        guard run == self.run, speaking == nil else { return }
        isReading = false
    }

    func stop() {
        guard isReading else { return }
        run += 1
        stopSpeaking()
        isReading = false
        Log.info("Read Aloud: stopped")
    }

    private func stopSpeaking() {
        speaking = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Spoken Content's choice for `language`, when apps may use it, else the
    /// best voice this Mac has for it; nil for the default voice.
    private static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        let domain = "com.apple.Accessibility" as CFString
        let preferences = SpeechVoices.Preferences(
            selections: CFPreferencesCopyAppValue("SpokenContentDefaultVoiceSelectionsByLanguage" as CFString, domain),
            disambiguations: CFPreferencesCopyAppValue("SpokenContentMacroLanguageDisambiguations" as CFString, domain))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
        let available = voices.map { SpeechVoices.Voice(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue) }
        guard let chosen = SpeechVoices.choose(for: language, preferences: preferences, available: available,
                                               userLanguage: AVSpeechSynthesisVoice.currentLanguageCode()) else { return nil }
        return voices.first { $0.identifier == chosen.identifier }
    }

    // MARK: AVSpeechSynthesizerDelegate (called off the main thread)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    private func ended(_ id: ObjectIdentifier) {
        guard id == speaking else { return }
        speaking = nil
        isReading = false
        Log.info("Read Aloud: finished")
    }
}
