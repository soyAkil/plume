import Foundation

public enum ReadAloudMode: String, Sendable {
    case readAloud, summary
}

public struct SummaryOptions: Sendable, Equatable {
    public var length: SummaryLength
    public var language: SummaryLanguage

    public init(length: SummaryLength, language: SummaryLanguage) {
        self.length = length
        self.language = language
    }
}

public enum ReadAloudEvent: Sendable, Equatable {
    /// The summary model is being loaded.
    case loading
    /// The model reads the selection, 0…1.
    case readingInput(Double)
    /// The selection is read; the first sentence is being written.
    case summarizing
    /// The selection was cut to fit the model.
    case truncated(keptWords: Int)
    /// The language the sentences are in, for the voice.
    case language(String)
    case sentence(String)
}

/// Turns a selection into sentences to speak, in either mode. Shared by the command line
/// and the app; what happens to the sentences (voice, player) is the caller's.
public enum ReadAloudPipeline {
    /// A selection of punctuation, symbols or emoji has nothing to say: it must fail loudly
    /// ("select some text") rather than start a silent read.
    public static func hasWords(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    public static func readAloud(_ selection: String, interface: Language) throws -> (language: String, sentences: [String]) {
        guard hasWords(selection) else { throw ReadAloudError.nothingToRead }
        let prepared = SpokenText.prepare(selection, interface: interface)
        let sentences = SentenceSplitter.split(prepared.text, firstMaxLength: 70).filter(hasWords)
        guard !sentences.isEmpty else { throw ReadAloudError.nothingToRead }
        return (prepared.language, sentences)
    }

    public static func summary(
        _ selection: String, service: any SummaryService, markers: [ReasoningMarkers],
        options: SummaryOptions, interface: Language
    ) -> AsyncThrowingStream<ReadAloudEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard hasWords(selection) else { throw ReadAloudError.nothingToRead }
                    if !(await service.isLoaded) {
                        continuation.yield(.loading)
                        try await service.load()
                    }
                    let request = try await SummaryPrompt.make(
                        selection: selection, length: options.length, language: options.language, interface: interface,
                        inputBudget: await service.inputBudget, countTokens: { try await service.countTokens($0) })
                    continuation.yield(.language(request.language))
                    if request.truncated { continuation.yield(.truncated(keptWords: request.keptWords)) }

                    var cleaner = SummaryCleaner(markers: markers)
                    var splitter = SentenceSplitter()
                    var spoken = 0
                    var announced = false
                    // A model that rambles is stopped a little past its budget.
                    let limit = request.maxSentences + 2
                    func emit(_ sentences: [String]) -> Bool {
                        for sentence in sentences {
                            let tidy = SummaryCleaner.tidy(sentence, isFirst: spoken == 0)
                            guard hasWords(tidy) else { continue }
                            continuation.yield(.sentence(tidy))
                            spoken += 1
                            if spoken >= limit { return false }
                        }
                        return true
                    }
                    func announce() {
                        if !announced { announced = true; continuation.yield(.summarizing) }
                    }
                    var open = true
                    reading: for try await event in service.stream(request) {
                        switch event {
                        case .readingInput(let fraction):
                            continuation.yield(.readingInput(fraction))
                            if fraction >= 1 { announce() }
                        case .text(let piece):
                            announce()
                            if !emit(splitter.feed(cleaner.feed(piece))) { open = false; break reading }
                        }
                    }
                    if open { _ = emit(splitter.feed(cleaner.finish()) + splitter.finish()) }
                    guard spoken > 0 else { throw ReadAloudError.emptySummary }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
