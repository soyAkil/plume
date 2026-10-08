import Foundation
import Testing
@testable import PlumeKit

/// A scripted summary service: one "token" per word, pieces streamed as given.
actor FakeSummaryService: SummaryService {
    private(set) var loaded: Bool
    let pieces: [String]
    let budget: Int
    /// Keeps the stream open after the pieces, like a model still writing: only then does
    /// stopping early reach the service.
    let holdOpen: Bool
    nonisolated let stopped = CancelFlag()

    init(pieces: [String], loaded: Bool = false, budget: Int = 10_000, holdOpen: Bool = false) {
        self.pieces = pieces
        self.loaded = loaded
        self.budget = budget
        self.holdOpen = holdOpen
    }

    var isLoaded: Bool { loaded }
    func load() { loaded = true }
    var inputBudget: Int { budget }
    func countTokens(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func unload() { loaded = false }

    nonisolated func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error> {
        let pieces = self.pieces
        let stopped = self.stopped
        let holdOpen = self.holdOpen
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { reason in if case .cancelled = reason { stopped.set() } }
            continuation.yield(.readingInput(fraction: 0.5))
            continuation.yield(.readingInput(fraction: 1))
            for piece in pieces { continuation.yield(.text(piece)) }
            if !holdOpen { continuation.finish() }
        }
    }
}

@Suite("Read-aloud pipeline")
struct ReadAloudPipelineTests {
    let options = SummaryOptions(length: .automatic, language: .sameAsText)
    let markers = SummaryEngineCatalog.qwen35_4b.markers

    func collect(_ stream: AsyncThrowingStream<ReadAloudEvent, Error>) async throws -> [ReadAloudEvent] {
        var events: [ReadAloudEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func readsWordForWordWithAShortFirstSentence() throws {
        let text = "Ceci est une première phrase assez longue pour dépasser soixante-dix caractères, vraiment. Et une autre phrase ici."
        let result = try ReadAloudPipeline.readAloud(text, interface: .english)
        #expect(result.language == "fr")
        #expect(result.sentences[0].count <= 70)
        #expect(result.sentences.last == "Et une autre phrase ici.")
    }

    /// Review focus: nothing readable means "select some text", not silence.
    @Test func refusesASelectionWithoutWords() async throws {
        for selection in ["   ", "…!!", "🙂", "\n\n"] {
            #expect(throws: ReadAloudError.nothingToRead, "\(selection)") { try ReadAloudPipeline.readAloud(selection, interface: .english) }
            let service = FakeSummaryService(pieces: ["Never used."])
            await #expect(throws: ReadAloudError.nothingToRead, "\(selection)") {
                _ = try await collect(ReadAloudPipeline.summary(selection, service: service, markers: markers, options: options, interface: .english))
            }
        }
    }

    @Test func summarizesInOrderAndDropsTheReasoning() async throws {
        let service = FakeSummaryService(pieces: ["<thi", "nk>pondering</think>", "**Summary:** The release ", "moves. It is", " fixed."])
        let events = try await collect(ReadAloudPipeline.summary(
            "The billing release moves to October twenty-first because two bugs block the export.",
            service: service, markers: markers, options: options, interface: .english))
        #expect(events == [
            .loading, .language("en"), .readingInput(0.5), .readingInput(1), .summarizing,
            .sentence("The release moves."), .sentence("It is fixed."),
        ])
    }

    @Test func doesNotReloadALoadedModel() async throws {
        let service = FakeSummaryService(pieces: ["Done."], loaded: true)
        let events = try await collect(ReadAloudPipeline.summary("Some text to summarize here.", service: service, markers: markers, options: options, interface: .english))
        #expect(!events.contains(.loading))
    }

    @Test func stopsTheModelPastTheSentenceBudget() async throws {
        let rambling = (1...20).map { "Sentence \($0) here. " }
        let service = FakeSummaryService(pieces: rambling, holdOpen: true)
        let events = try await collect(ReadAloudPipeline.summary("A short text to summarize.", service: service, markers: markers, options: options, interface: .english))
        let sentences = events.filter { if case .sentence = $0 { return true } else { return false } }
        #expect(sentences.count == 2 + 2)  // budget for < 300 words in automatic is 2, plus 2
        #expect(service.stopped.isSet)
    }

    @Test func anEmptySummaryIsAnError() async throws {
        let service = FakeSummaryService(pieces: ["<think>only thoughts</think>", "  "])
        await #expect(throws: ReadAloudError.emptySummary) {
            _ = try await collect(ReadAloudPipeline.summary("Text to summarize.", service: service, markers: markers, options: options, interface: .english))
        }
    }

    @Test func announcesATruncatedSelection() async throws {
        let long = Array(repeating: "One sentence of six words.", count: 400).joined(separator: " ")
        let service = FakeSummaryService(pieces: ["Short."], budget: 500)
        let events = try await collect(ReadAloudPipeline.summary(long, service: service, markers: markers, options: options, interface: .english))
        #expect(events.contains { if case .truncated(let words) = $0 { return words < 500 } else { return false } })
    }
}
