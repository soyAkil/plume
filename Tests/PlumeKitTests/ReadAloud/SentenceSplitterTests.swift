import Foundation
import Testing
@testable import PlumeKit

@Suite("Sentence splitter")
struct SentenceSplitterTests {
    /// Each row: the input, the sentences expected. The second half of the table is the
    /// ordinary sentence closest to each tricky case, which must not change.
    static let table: [(String, [String])] = [
        ("Il pleut. Il fait froid.", ["Il pleut.", "Il fait froid."]),
        ("Le taux est de 4,5 % cette année. Il baisse.", ["Le taux est de 4,5 % cette année.", "Il baisse."]),
        ("Version 3.2 sortie. Mise à jour.", ["Version 3.2 sortie.", "Mise à jour."]),
        ("M. Dupont arrive. Il est en retard.", ["M. Dupont arrive.", "Il est en retard."]),
        ("Use a tool, e.g. a hammer. Then rest.", ["Use a tool, e.g. a hammer.", "Then rest."]),
        ("J. R. R. Tolkien wrote it. Fine.", ["J. R. R. Tolkien wrote it.", "Fine."]),
        ("Attends… je réfléchis. Bon.", ["Attends… je réfléchis.", "Bon."]),
        ("Il a dit « oui. » Puis il est parti.", ["Il a dit « oui. »", "Puis il est parti."]),
        ("Quoi ?! Vraiment.", ["Quoi ?!", "Vraiment."]),
        ("Born in the U.S. today, he left.", ["Born in the U.S. today, he left."]),
        ("See Fig. 3 for details. Done.", ["See Fig. 3 for details.", "Done."]),
        ("今日は晴れです。明日は雨です。", ["今日は晴れです。", "明日は雨です。"]),
        ("यह पहला वाक्य है। यह दूसरा है।", ["यह पहला वाक्य है।", "यह दूसरा है।"]),
        ("First paragraph without end\n\nSecond one.", ["First paragraph without end", "Second one."]),
        ("Open config.json. Then restart.", ["Open config.json.", "Then restart."]),
        ("La version est 3.2. Il baisse.", ["La version est 3.2.", "Il baisse."]),
        ("I said no. He left.", ["I said no.", "He left."]),
        ("No. I won't go.", ["No.", "I won't go."]),
        ("So did I. He left.", ["So did I.", "He left."]),
        ("Voir le No. 5 ici. Fin.", ["Voir le No. 5 ici.", "Fin."]),
        ("Voir p. 12 pour la suite. Fin.", ["Voir p. 12 pour la suite.", "Fin."]),
        ("He said \"Hello.\" \"World,\" she said.", ["He said \"Hello.\"", "\"World,\" she said."]),
        // ordinary neighbours
        ("Il pleut beaucoup. Il fait très froid.", ["Il pleut beaucoup.", "Il fait très froid."]),
        ("Use a hammer. Then rest.", ["Use a hammer.", "Then rest."]),
    ]

    @Test func splitsTheTable() {
        for (input, expected) in Self.table {
            #expect(SentenceSplitter.split(input) == expected, "\(input)")
        }
    }

    /// Known limit: an initialism ending a sentence ("the U.S. It is…") does not split, since
    /// "U.S." looks like an abbreviation. Two sentences become one; nothing is lost.
    @Test func anInitialismAtASentenceEndStaysJoined() {
        withKnownIssue("an initialism ending a sentence is read as an abbreviation") {
            #expect(SentenceSplitter.split("They moved to the U.S. It is far.") == ["They moved to the U.S.", "It is far."])
        }
    }

    @Test func waitsForWhatFollowsAPeriodWhenStreaming() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Bonjour M.") == [])          // "M." may be an abbreviation: wait
        #expect(splitter.feed(" Dupont est là. Il") == ["Bonjour M. Dupont est là."])
        #expect(splitter.feed(" part.") == [])               // the end of the stream is not known yet
        #expect(splitter.finish() == ["Il part."])
    }

    @Test func cutsALongRunWithoutPunctuation() {
        let run = Array(repeating: "mot", count: 400).joined(separator: " ")   // ~1,600 characters
        let sentences = SentenceSplitter.split(run)
        #expect(sentences.count >= 5)
        #expect(sentences.allSatisfy { $0.count <= 300 })
        #expect(sentences.joined(separator: " ") == run)
    }

    @Test func cutsALongJapaneseRunWithoutSpaces() {
        let run = String(repeating: "あ", count: 400)
        let sentences = SentenceSplitter.split(run)
        #expect(sentences.map(\.count) == [300, 100])
    }

    @Test func capsOnlyTheFirstSentenceWhenAsked() {
        let text = "Ceci est une première phrase assez longue pour dépasser soixante-dix caractères, vraiment. Courte."
        let sentences = SentenceSplitter.split(text, firstMaxLength: 70)
        #expect(sentences[0].count <= 70)
        #expect(sentences.last == "Courte.")
    }

    @Test func cutsALongRunOfPeriods() {
        let sentences = SentenceSplitter.split(String(repeating: ".", count: 1000))
        #expect(sentences.count >= 4)
        #expect(sentences.allSatisfy { $0.count <= 300 })
    }

    @Test func aLimitUnderOneStillTerminates() {
        let sentences = SentenceSplitter.split("abc def", maxLength: 0)
        #expect(!sentences.isEmpty)
        #expect(sentences.allSatisfy { !$0.isEmpty })
        #expect(SentenceSplitter.split("abc def", firstMaxLength: -5).allSatisfy { !$0.isEmpty })
    }

    /// Review focus: 1 MB of text splits in linear time.
    @Test func splitsAMegabyteQuickly() {
        let text = String(repeating: "Une phrase ordinaire pour le test. ", count: 30_000)  // ~1 MB
        let start = Date()
        let sentences = SentenceSplitter.split(text)
        #expect(sentences.count == 30_000)
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}
