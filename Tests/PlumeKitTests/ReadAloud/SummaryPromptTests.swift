import Foundation
import Testing
@testable import PlumeKit

@Suite("Summary prompt")
struct SummaryPromptTests {
    @Test func sentenceBudgetFollowsTheTable() {
        let rows: [(Int, SummaryLength, Int)] = [
            (120, .short, 1), (120, .automatic, 2), (120, .detailed, 3),
            (299, .automatic, 2), (300, .automatic, 4), (1_500, .automatic, 4), (1_501, .automatic, 6),
            (800, .short, 2), (800, .detailed, 6), (5_000, .short, 3), (5_000, .detailed, 8),
        ]
        for (words, length, expected) in rows {
            #expect(SummaryPrompt.sentenceBudget(words: words, length: length) == expected, "\(words) \(length)")
        }
    }

    @Test func languageFollowsTheSetting() {
        let french = "La mise en production du module de facturation est repoussée au vingt et un octobre."
        let english = "The release of the billing module has been pushed back to October twenty-first."
        let german = "Die Veröffentlichung des Abrechnungsmoduls wurde auf den einundzwanzigsten Oktober verschoben."
        #expect(SummaryPrompt.language(for: french, setting: .sameAsText, interface: .english) == "fr")
        #expect(SummaryPrompt.language(for: english, setting: .sameAsText, interface: .french) == "en")
        #expect(SummaryPrompt.language(for: german, setting: .sameAsText, interface: .french) == "fr")
        #expect(SummaryPrompt.language(for: "12345", setting: .sameAsText, interface: .english) == "en")
        // Too short for a confident guess ("OK" reads as Polish): the interface language wins.
        #expect(SummaryPrompt.language(for: "OK", setting: .sameAsText, interface: .french) == "fr")
        #expect(SummaryPrompt.language(for: french, setting: .interface, interface: .english) == "en")
        #expect(SummaryPrompt.language(for: english, setting: .fr, interface: .english) == "fr")
    }

    @Test func instructionsCarryNoModelMarkup() {
        for language in ["fr", "en"] {
            let text = SummaryPrompt.instructions(language: language, sentences: 4)
            #expect(!text.contains("<|") && !text.contains("<think>") && !text.contains("<turn"))
            #expect(text.contains("4"))
        }
        #expect(SummaryPrompt.instructions(language: "fr", sentences: 1).contains("une phrase"))
        #expect(SummaryPrompt.instructions(language: "en", sentences: 1).contains("one sentence"))
    }

    /// One "token" per word, so the budget is easy to reason about.
    private func words(_ text: String) async throws -> Int { text.split(whereSeparator: \.isWhitespace).count }

    @Test func keepsASelectionThatFits() async throws {
        let request = try await SummaryPrompt.make(
            selection: "  Une phrase. Une autre.  ", length: .automatic, language: .fr, interface: .english,
            inputBudget: 10_000, countTokens: words)
        #expect(request.user == "Une phrase. Une autre.")
        #expect(!request.truncated)
        #expect(request.maxSentences == 2)
        #expect(request.language == "fr")
    }

    /// Review focus: a huge selection is cut at a sentence end, with few tokenizations.
    @Test func truncatesAtASentenceEndWithFewTokenizations() async throws {
        let sentence = "Ceci est une phrase de huit mots ici."
        let selection = Array(repeating: sentence, count: 5_000).joined(separator: " ")  // 40,000 words
        let calls = CallCounter()
        let request = try await SummaryPrompt.make(
            selection: selection, length: .automatic, language: .fr, interface: .french, inputBudget: 1_200,
            countTokens: { text in calls.increment(); return text.split(whereSeparator: \.isWhitespace).count })
        #expect(request.truncated)
        #expect(request.user.hasSuffix("ici."))
        #expect(request.keptWords < 1_200)
        #expect(request.keptWords > 1_000)
        #expect(calls.value <= 25)
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
