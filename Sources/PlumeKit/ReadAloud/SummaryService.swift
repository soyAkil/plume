import Foundation

public enum SummaryEvent: Sendable, Equatable {
    /// The model is reading the selection (prompt processing), 0…1.
    case readingInput(fraction: Double)
    /// A decoded piece of the summary.
    case text(String)
}

/// Turns a model-neutral request into a stream of text. llama.cpp is the only one today;
/// Apple Intelligence, a cloud API or MLX would each be one more conforming type, with no
/// change to the prompt, the cleaner, the splitter, the voice or the controller.
public protocol SummaryService: Sendable {
    var isLoaded: Bool { get async }
    /// Loads an already downloaded model; the first load may compile GPU kernels.
    func load() async throws
    /// Tokens the service takes as input, prompt included.
    var inputBudget: Int { get async }
    /// Counts in the service's own tokens; needs `load()` first.
    func countTokens(_ text: String) async throws -> Int
    /// Cancelled when the consumer stops iterating.
    func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error>
    func unload() async
}
