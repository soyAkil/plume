// Tests/PlumeKitTests/ReadAloud/SummaryCleanerTests.swift
import Testing
@testable import PlumeKit

@Suite("Summary cleaner")
struct SummaryCleanerTests {
    /// Feeds `text` one character at a time: markers arrive split across tokens.
    private func streamed(_ text: String, markers: [ReasoningMarkers]) -> String {
        var cleaner = SummaryCleaner(markers: markers)
        var out = ""
        for character in text { out += cleaner.feed(String(character)) }
        return out + cleaner.finish()
    }

    @Test func dropsEveryCatalogEntrysReasoning() {
        for entry in SummaryEngineCatalog.all {
            for marker in entry.markers {
                let text = "\(marker.open)\nLet me think about the billing module.\n\(marker.close)\nThe release moves to October."
                let out = streamed(text, markers: entry.markers)
                #expect(!out.contains("think about"), "\(entry.id)")
                #expect(out.contains("The release moves to October."), "\(entry.id)")
            }
        }
    }

    @Test func dropsAnUnfinishedReasoningBlock() {
        let markers = SummaryEngineCatalog.qwen35_4b.markers
        #expect(streamed("Answer first. <think>never closed", markers: markers) == "Answer first. ")
    }

    @Test func dropsAStrayCloseMarker() {
        let markers = SummaryEngineCatalog.qwen35_4b.markers
        #expect(streamed("</think>\n\nThe summary.", markers: markers) == "\n\nThe summary.")
    }

    @Test func keepsTextThatOnlyLooksLikeAMarkerStart() {
        let markers = SummaryEngineCatalog.qwen35_4b.markers
        #expect(streamed("a < b and c <th", markers: markers) == "a < b and c <th")
    }

    @Test func releasesAHeldTailAtTheEndAndKeepsTextAfterEachBlock() {
        let markers = SummaryEngineCatalog.qwen35_4b.markers
        var cleaner = SummaryCleaner(markers: markers)
        #expect(cleaner.feed("a <th") == "a ")
        #expect(cleaner.finish() == "<th")
        #expect(streamed("One.<think>x</think>Two.<think>y</think> Three.", markers: markers) == "One.Two. Three.")
    }

    @Test func tidiesSentences() {
        let rows: [(String, Bool, String)] = [
            ("**Résumé :** La sortie est repoussée.", true, "La sortie est repoussée."),
            ("Summary: The release moves.", true, "The release moves."),
            ("- The release moves.", false, "The release moves."),
            ("## Key points", false, "Key points"),
            ("The release moves.<|im_end|>", false, "The release moves."),
            ("The release moves.<turn|>", false, "The release moves."),
            ("Summary: is a word here.", false, "Summary: is a word here."),
            ("It is *really* fixed.", false, "It is really fixed."),
            // ordinary neighbours
            ("It is 2 * 3.", false, "It is 2 * 3."),
            ("The release moves to October.", true, "The release moves to October."),
        ]
        for (input, isFirst, expected) in rows {
            #expect(SummaryCleaner.tidy(input, isFirst: isFirst) == expected, "\(input)")
        }
    }
}
