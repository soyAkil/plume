import FluidAudio
import Testing
@testable import PlumeKit

@Suite("Spoken text")
struct SpokenTextTests {
    static let cleaning: [(String, String, String)] = [
        // (language, input, expected)
        ("fr", "Voir https://example.com/page?id=3 pour le détail.", "Voir lien pour le détail."),
        ("en", "See www.example.org, then reply.", "See link, then reply."),
        ("en", "Write to anne@example.com today.", "Write to anne@example.com today."),
        ("en", "# Title\nSome **bold** and `code` here.", "Title. Some bold and code here."),
        ("en", "Groceries:\n- milk\n- eggs\n1. call Bob", "Groceries: milk. eggs. call Bob."),
        ("en", "Before\n```\nlet x = 1\n```\nAfter.", "Before. Code block skipped. After."),
        ("fr", "Avant\n```swift\nlet x = 1\n```\nAprès.", "Avant. Bloc de code ignoré. Après."),
        ("en", "Read [the guide](https://x.y/z) now.", "Read the guide now."),
        ("en", "snake_case_name stays", "snake_case_name stays."),
        ("en", "Write to anne@www.example.com today.", "Write to anne@www.example.com today."),
        ("en", "awww.example.com stays", "awww.example.com stays."),
        ("en", "Call __init__ now.", "Call __init__ now."),
        ("en", "2 ** 3 is eight.", "2 ** 3 is eight."),
        ("en", "2 * 3 is six.", "2 * 3 is six."),
        ("en", "Some **bold** here.", "Some bold here."),
        ("en", "Some __bold text__ here.", "Some bold text here."),
        ("en", "Call __my_helper__ now.", "Call __my_helper__ now."),
        ("en", "__init__ and __x__ stay", "__init__ and __x__ stay."),
        ("en", "A\r\nB", "A. B."),
        ("en", "(see https://x.y/z).", "(see link)."),
        ("en", "- see [guide](https://x.y/z) now", "see guide now."),
        // ordinary neighbours
        ("fr", "Voir la page pour le détail.", "Voir la page pour le détail."),
        ("en", "Some bold and code here.", "Some bold and code here."),
    ]

    @Test func cleansTheTable() {
        for (language, input, expected) in Self.cleaning {
            #expect(SpokenText.clean(input, language: language) == expected, "\(input)")
        }
    }

    @Test func speaksTheTextsLanguageWhenTheVoiceKnowsIt() {
        #expect(SpokenText.speechLanguage(of: "Bonjour, je voulais te dire que la réunion est déplacée à demain.", interface: .english) == "fr")
        #expect(SpokenText.speechLanguage(of: "Hello, I wanted to tell you that the meeting moved to tomorrow.", interface: .french) == "en")
        #expect(SpokenText.speechLanguage(of: "Hola, quería decirte que la reunión se ha movido a mañana.", interface: .english) == "es")
    }

    @Test func ignoresAGuessOnShortTexts() {
        #expect(SpokenText.speechLanguage(of: "OK", interface: .french) == "fr")
        #expect(SpokenText.speechLanguage(of: "Hello", interface: .french) == "fr")
        #expect(SpokenText.detectedLanguage(of: "OK") == nil)
        #expect(SpokenText.detectedLanguage(of: "12345") == nil)
        #expect(SpokenText.detectedLanguage(of: "Hello, I wanted to tell you that the meeting moved to tomorrow.") == "en")
    }

    /// Review focus: an undetectable text falls back to the interface language.
    @Test func fallsBackToTheInterfaceLanguage() {
        #expect(SpokenText.speechLanguage(of: "12345", interface: .french) == "fr")
        #expect(SpokenText.speechLanguage(of: "12345", interface: .english) == "en")
    }

    @Test func normalizesOnlyTheLanguagesSharedWithTheVoice() {
        for code in ["fr", "en", "es", "de", "ja", "hi"] { #expect(SpokenText.normalizerLanguage(code) != nil, "\(code)") }
        for code in ["it", "pt", "ko", "zh"] { #expect(SpokenText.normalizerLanguage(code) == nil, "\(code)") }
        #expect(!SpokenText.voiceLanguages.contains("na"))
        #expect(SpokenText.voiceLanguages.contains("fr"))
    }
}
