import Testing
@testable import SeashellCore

struct SpeechVoicesTests {
    let samantha = SpeechVoices.Voice(identifier: "com.apple.voice.compact.en-US.Samantha", language: "en-US", quality: 1)
    let ava = SpeechVoices.Voice(identifier: "com.apple.voice.premium.en-US.Ava", language: "en-US", quality: 3)
    let daniel = SpeechVoices.Voice(identifier: "com.apple.voice.enhanced.en-GB.Daniel", language: "en-GB", quality: 2)
    let sinji = SpeechVoices.Voice(identifier: "com.apple.voice.premium.zh-HK.Sinji", language: "zh-HK", quality: 3)
    let tingting = SpeechVoices.Voice(identifier: "com.apple.voice.compact.zh-CN.Tingting", language: "zh-CN", quality: 1)
    let meijia = SpeechVoices.Voice(identifier: "com.apple.voice.compact.zh-TW.Meijia", language: "zh-TW", quality: 1)
    let kyoko = SpeechVoices.Voice(identifier: "com.apple.voice.compact.ja-JP.Kyoko", language: "ja-JP", quality: 1)
    var all: [SpeechVoices.Voice] { [samantha, ava, daniel, sinji, tingting, meijia, kyoko] }

    /// As this Mac's Spoken Content had it on 2026-10-24.
    let preferences = SpeechVoices.Preferences(
        selections: ["yue", ["boundLanguage": "yue", "voiceId": "com.apple.voice.premium.zh-HK.Sinji"],
                     "en", ["boundLanguage": "en", "voiceId": "com.apple.siri.natural.en-US-G", "rate": "0.55"]],
        disambiguations: ["zh", "yue"])

    @Test func readsSpokenContentsSettings() {
        #expect(preferences.voices == ["yue": "com.apple.voice.premium.zh-HK.Sinji", "en": "com.apple.siri.natural.en-US-G"])
        #expect(preferences.readAs == ["zh": "yue"])
        #expect(SpeechVoices.Preferences(selections: nil, disambiguations: "nonsense") == SpeechVoices.Preferences())
    }

    @Test func chineseIsReadAsChosen() {
        // Chinese is read as Cantonese here, in the premium Hong Kong voice.
        #expect(SpeechVoices.choose(for: "zh-Hant", preferences: preferences, available: all, userLanguage: "en-US") == sinji)
        #expect(SpeechVoices.choose(for: "zh-Hans", preferences: preferences, available: all, userLanguage: "en-US") == sinji)
    }

    @Test func aSiriVoiceGivesWayToTheBestOtherInTheMacsRegion() {
        // Other apps can't use Siri voices: the best en-US one, not the British.
        #expect(SpeechVoices.choose(for: "en", preferences: preferences, available: all, userLanguage: "en-US") == ava)
        #expect(SpeechVoices.choose(for: "en", preferences: preferences, available: all, userLanguage: "en-GB") == daniel)
        #expect(SpeechVoices.choose(for: "en", preferences: preferences, available: all, userLanguage: "fr-FR") == ava, "best of any region")
    }

    @Test func withoutAChoiceChineseGoesByItsScript() {
        let none = SpeechVoices.Preferences()
        #expect(SpeechVoices.choose(for: "zh-Hans", preferences: none, available: all, userLanguage: "en-US") == tingting)
        #expect(SpeechVoices.choose(for: "zh-Hant", preferences: none, available: all, userLanguage: "en-US") == meijia)
    }

    @Test func otherLanguagesGetTheirOwnVoice() {
        #expect(SpeechVoices.choose(for: "ja", preferences: preferences, available: all, userLanguage: "en-US") == kyoko)
        #expect(SpeechVoices.choose(for: "fr", preferences: preferences, available: all, userLanguage: "en-US") == nil, "no French voice: the default")
        #expect(SpeechVoices.choose(for: nil, preferences: preferences, available: all, userLanguage: "en-US") == nil)
    }

    @Test func tellsTheLanguage() {
        #expect(SpeechVoices.language(of: "Remember to pick up the dry cleaning on the way home tonight.") == "en")
        #expect(SpeechVoices.language(of: "今日天氣好好，我哋去行山啦。") == "zh-Hant")
        #expect(SpeechVoices.language(of: "") == nil)
    }
}
