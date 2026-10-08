import Foundation

/// A part of the prompt. The selection is tokenized apart, without special-token parsing:
/// a selection containing `<|im_end|>` stays plain text instead of closing the turn.
public struct PromptPiece: Equatable, Sendable {
    public let text: String
    public let isSelection: Bool
}

public enum PromptRenderer {
    /// Stands in for the selection while the template is applied, then splits the result.
    static let sentinel = "\u{E000}PLUME-SELECTION\u{E000}"

    /// `applyTemplate(system, user)` formats with the model's embedded template (llama.cpp).
    /// Both texts are trimmed first, as the official templates do and llama.cpp's C
    /// formatter does not.
    public static func pieces(
        for request: SummaryRequest, format: PromptFormat, applyTemplate: (String, String) throws -> String
    ) throws -> [PromptPiece] {
        let system = request.system.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = request.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let before: String
        let after: String
        switch format {
        case .embedded(let prefix):
            let parts = (try applyTemplate(system, sentinel) + prefix).components(separatedBy: sentinel)
            guard parts.count == 2 else { throw ReadAloudError.unsupportedTemplate }
            (before, after) = (parts[0], parts[1])
        case .explicit(let template):
            // Split on `{user}` first, so a `{user}` typed in the system text stays plain text.
            let parts = template.components(separatedBy: "{user}")
            guard parts.count == 2 else { throw ReadAloudError.unsupportedTemplate }
            (before, after) = (
                parts[0].replacingOccurrences(of: "{system}", with: system),
                parts[1].replacingOccurrences(of: "{system}", with: system))
        }
        return [
            PromptPiece(text: before, isSelection: false),
            PromptPiece(text: user, isSelection: true),
            PromptPiece(text: after, isSelection: false),
        ]
    }
}

/// Collects token bytes and releases only complete UTF-8 characters: a token can end in
/// the middle of "é".
public struct UTF8Accumulator: Sendable {
    private var pending: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        let complete = Self.completePrefixLength(pending)
        guard complete > 0 else { return "" }
        let text = String(decoding: pending[..<complete], as: UTF8.self)
        pending.removeFirst(complete)
        return text
    }

    public mutating func finish() -> String {
        defer { pending = [] }
        return String(decoding: pending, as: UTF8.self)
    }

    /// Longest prefix that does not end inside a multi-byte character.
    static func completePrefixLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, bytes[index] & 0xC0 == 0x80, continuation < 3 {
            index -= 1
            continuation += 1
        }
        guard index >= 0 else { return bytes.count }
        let lead = bytes[index]
        let needed = lead < 0x80 ? 1 : lead & 0xE0 == 0xC0 ? 2 : lead & 0xF0 == 0xE0 ? 3 : lead & 0xF8 == 0xF0 ? 4 : 1
        return continuation + 1 >= needed ? bytes.count : index
    }
}

/// Sampling values: llama-server's defaults (what the bench ran), replaced by the model's
/// own recommendations from its GGUF metadata, always with the entry's temperature.
public struct Sampling: Equatable, Sendable {
    public let topK: Int32
    public let topP: Float
    public let minP: Float
    public let temperature: Float

    public static func resolve(metadata: (String) -> String?, temperature: Float) -> Sampling {
        Sampling(
            topK: metadata("general.sampling.top_k").flatMap { Int32($0) } ?? 40,
            topP: metadata("general.sampling.top_p").flatMap { Float($0) } ?? 0.95,
            minP: metadata("general.sampling.min_p").flatMap { Float($0) } ?? 0.05,
            temperature: temperature)
    }
}
