import Foundation
import NaturalLanguage

/// Which voice reads a text aloud (Read Aloud): the one chosen for its
/// language in System Settings ▸ Accessibility ▸ Spoken Content, when other
/// apps may use it (Siri voices they may not), else the best one this Mac has
/// for that language, else the system's default.
public enum SpeechVoices {
    public struct Voice: Equatable, Sendable {
        public let identifier: String
        /// As voices name it, e.g. "en-US" or "zh-HK".
        public let language: String
        /// Higher is better: default, enhanced, premium.
        public let quality: Int

        public init(identifier: String, language: String, quality: Int) {
            self.identifier = identifier
            self.language = language
            self.quality = quality
        }
    }

    /// Spoken Content's choices, as `com.apple.Accessibility` keeps them.
    public struct Preferences: Equatable, Sendable {
        /// Language, as Spoken Content names it ("en", "yue"), → voice identifier.
        public var voices: [String: String] = [:]
        /// A language read as another: Chinese ("zh") as Cantonese ("yue"), say.
        public var readAs: [String: String] = [:]

        public init(voices: [String: String] = [:], readAs: [String: String] = [:]) {
            self.voices = voices
            self.readAs = readAs
        }

        /// From `SpokenContentDefaultVoiceSelectionsByLanguage` (language, then
        /// its selection, alternating) and `SpokenContentMacroLanguageDisambiguations`
        /// (language, then the one it's read as).
        public init(selections: Any?, disambiguations: Any?) {
            for (language, selection) in Self.pairs(selections) {
                if let language = language as? String, let id = (selection as? [String: Any])?["voiceId"] as? String {
                    voices[language] = id
                }
            }
            for (language, readAs) in Self.pairs(disambiguations) {
                if let language = language as? String, let other = readAs as? String { self.readAs[language] = other }
            }
        }

        private static func pairs(_ value: Any?) -> [(Any, Any)] {
            guard let list = value as? [Any] else { return [] }
            return stride(from: 0, to: list.count - 1, by: 2).map { (list[$0], list[$0 + 1]) }
        }
    }

    /// The language `text` is written in, e.g. "en" or "zh-Hant"; nil if it
    /// can't tell. Its first 2,000 characters are enough.
    public static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    /// The voice for text in `language` (nil: the system's default voice).
    /// `userLanguage` is the Mac's own, e.g. "en-US": its region's voices come
    /// first for that language.
    public static func choose(for language: String?, preferences: Preferences, available: [Voice],
                              userLanguage: String) -> Voice? {
        guard let language else { return nil }
        let base = String(language.prefix { $0 != "-" })
        let spoken = preferences.readAs[base] ?? base
        if let id = preferences.voices[spoken], let chosen = available.first(where: { $0.identifier == id }) {
            return chosen
        }
        // Cantonese is Hong Kong's; Chinese otherwise by its script, in the
        // order given (Taiwan's Mandarin before Hong Kong's Cantonese).
        let regions: [String] = switch (spoken, language) {
        case ("yue", _): ["zh-HK"]
        case (_, "zh-Hans"): ["zh-CN"]
        case (_, "zh-Hant"): ["zh-TW", "zh-HK"]
        default: [base]
        }
        for region in regions {
            let matching = available.filter { $0.language.hasPrefix(region) }
            let own = userLanguage.hasPrefix(base) ? matching.filter { $0.language == userLanguage } : []
            if let best = (own.isEmpty ? matching : own).sorted(by: { $0.quality > $1.quality }).first { return best }
        }
        return nil
    }
}
