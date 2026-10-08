import Foundation

/// What a summary service receives: model-neutral messages, never a chat format.
public struct SummaryRequest: Sendable, Equatable {
    public let system: String
    public let user: String
    public let maxSentences: Int
    /// "fr" or "en".
    public let language: String
    public let truncated: Bool
    /// Words of the selection actually sent (all of them unless `truncated`).
    public let keptWords: Int
}

public enum SummaryPrompt {
    /// Room for the template's own tokens around the system text and the selection.
    static let templateAllowance = 64

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Sentences by selection size; Short and Detailed shift the scale by one notch.
    public static func sentenceBudget(words: Int, length: SummaryLength) -> Int {
        let row: [Int] = words < 300 ? [1, 2, 3] : words <= 1_500 ? [2, 4, 6] : [3, 6, 8]
        switch length {
        case .short: return row[0]
        case .automatic: return row[1]
        case .detailed: return row[2]
        }
    }

    /// Summaries are written in French or English only; anything else, or a guess the
    /// recognizer is not sure of, falls back to the interface language.
    public static func language(for text: String, setting: SummaryLanguage, interface: Language) -> String {
        switch setting {
        case .fr: return "fr"
        case .en: return "en"
        case .interface: return interface.rawValue
        case .sameAsText:
            let code = SpokenText.detectedLanguage(of: text)
            return code == "fr" || code == "en" ? code! : interface.rawValue
        }
    }

    /// The instructions validated in the bench (spike/selection-summary). They are model
    /// inputs: changing them means re-running the quality eval.
    public static func instructions(language: String, sentences: Int) -> String {
        if language == "fr" {
            let count = sentences == 1 ? "en une phrase" : "en \(sentences) phrases au plus"
            return "Tu résumes un texte pour qu'il soit lu à voix haute par une synthèse vocale. "
                + "Écris en français, \(count), en prose simple : pas de titre, pas de liste, "
                + "pas de markdown, pas d'émoji. Va droit à l'essentiel, sans introduction du type "
                + "« Ce texte parle de ». Écris les sigles et les nombres comme on les prononce si c'est ambigu. "
                + "Réponds uniquement avec le résumé."
        }
        let count = sentences == 1 ? "in one sentence" : "in at most \(sentences) sentences"
        return "You summarise a text so a text-to-speech voice can read it aloud. "
            + "Write in English, \(count), in plain prose: no title, no list, "
            + "no markdown, no emoji. Get straight to the point, with no preamble like "
            + "\"This text is about\". Spell out acronyms and numbers as spoken when ambiguous. "
            + "Reply with the summary only."
    }

    /// Builds the request; a selection over the service's input budget is cut at the last
    /// sentence end that fits.
    public static func make(
        selection: String, length: SummaryLength, language setting: SummaryLanguage, interface: Language,
        inputBudget: Int, countTokens: (String) async throws -> Int
    ) async throws -> SummaryRequest {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = sentenceBudget(words: wordCount(text), length: length)
        let language = self.language(for: text, setting: setting, interface: interface)
        let system = instructions(language: language, sentences: sentences)
        let room = inputBudget - (try await countTokens(system)) - templateAllowance
        guard room > 0 else { throw ReadAloudError.inputTooLong }
        if try await countTokens(text) <= room {
            return SummaryRequest(
                system: system, user: text, maxSentences: sentences, language: language,
                truncated: false, keptWords: wordCount(text))
        }
        // Largest prefix of whole sentences that fits: a binary search, ~log2(n) tokenizations.
        let pieces = SentenceSplitter.split(text)
        var low = 0
        var high = pieces.count
        while low < high {
            let middle = (low + high + 1) / 2
            if try await countTokens(pieces[..<middle].joined(separator: " ")) <= room { low = middle } else { high = middle - 1 }
        }
        let kept = pieces[..<max(low, 1)].joined(separator: " ")
        return SummaryRequest(
            system: system, user: kept, maxSentences: sentences, language: language,
            truncated: true, keptWords: wordCount(kept))
    }
}
