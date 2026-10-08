import FluidAudio
import Foundation
import NaturalLanguage

/// Prepares a selection to be read word for word: what a listener would expect to hear,
/// not what the page shows (no URLs spelled out, no markdown symbols, no code).
public enum SpokenText {
    public struct Prepared: Equatable, Sendable {
        public let text: String
        public let language: String
    }

    public static func prepare(_ selection: String, interface: Language) -> Prepared {
        let language = speechLanguage(of: selection, interface: interface)
        return Prepared(text: clean(selection, language: language), language: language)
    }

    /// Languages the voice speaks (Supertonic-3), without its "na" pseudo-language.
    public static let voiceLanguages: Set<String> = Set(Supertonic3Constants.availableLanguages).subtracting(["na"])

    /// The text's language, or nil when the recognizer is not sure (probability under 0.5).
    /// Short texts make it guess wildly ("OK" is Polish, "Hello" scores 0.13 for English), and a
    /// wrong guess reads or summarizes in the wrong language: no answer beats a bad one.
    public static func detectedLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
            probability >= 0.5
        else { return nil }
        return language.rawValue
    }

    /// The text's language when the voice speaks it, otherwise the interface language.
    public static func speechLanguage(of text: String, interface: Language) -> String {
        if let code = detectedLanguage(of: text), voiceLanguages.contains(code) { return code }
        return interface.rawValue
    }

    /// The number normalizer, for the languages it shares with the voice: digits are
    /// otherwise misread ("du 14 au 21" heard as "du 14 au zoo 21").
    public static func normalizerLanguage(_ code: String) -> NemoTextNormalizer.Language? {
        switch code {
        case "en": return .english
        case "fr": return .french
        case "es": return .spanish
        case "de": return .german
        case "ja": return .japanese
        case "hi": return .hindi
        default: return nil
        }
    }

    /// Characters after which a line already ends a sentence or a clause.
    static let lineEnders: Set<Character> = [".", "!", "?", "…", ":", ";", "。", "！", "？", "।", "؟", "\"", "»", "”", ")"]

    static func clean(_ text: String, language: String) -> String {
        let french = language == "fr"
        let link = french ? "lien" : "link"
        let skipped = french ? "Bloc de code ignoré." : "Code block skipped."
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: #"```[\s\S]*?(```|$)"#, with: "\n\(skipped)\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(https?://|(?<![\w@.])www\.)[^\s<>()]*[^\s<>().,;:!?'"»”]"#, with: link, options: .regularExpression)
        // Only paired emphasis goes: "2 ** 3" is not markdown, "**bold**" is. A single word
        // between double underscores ("__init__") is an identifier; "__bold text__" is emphasis.
        s = s.replacingOccurrences(of: #"(?<!\w)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\w)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?<!\w)__(?=\S)((?:(?!__)[^\n])*? (?:(?!__)[^\n])*?)(?<=\S)__(?!\w)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        var lines: [String] = []
        for raw in s.components(separatedBy: "\n") {
            var line = raw.replacingOccurrences(of: #"^\s*(#{1,6}|[-*•+]|\d{1,3}[.)])\s+"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A line without punctuation (a heading, a list item) still ends where it ends.
            if let last = line.last, !lineEnders.contains(last) { line += "." }
            lines.append(line)
        }
        return lines.joined(separator: " ").replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }
}
