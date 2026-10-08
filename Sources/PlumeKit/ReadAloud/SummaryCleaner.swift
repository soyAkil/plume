// Sources/PlumeKit/ReadAloud/SummaryCleaner.swift
import Foundation

/// Filters a summary as it streams: a model's reasoning must never be spoken.
///
/// Markers can arrive split across tokens (Gemma 4's `<|channel>thought` spans two), so a
/// tail that could be the start of one is held back until the next piece.
public struct SummaryCleaner: Sendable {
    private let markers: [ReasoningMarkers]
    private var buffer = ""
    private var inside: ReasoningMarkers?

    public init(markers: [ReasoningMarkers]) {
        self.markers = markers
    }

    public mutating func feed(_ piece: String) -> String {
        buffer += piece
        return drain(final: false)
    }

    public mutating func finish() -> String {
        drain(final: true)
    }

    private mutating func drain(final: Bool) -> String {
        var out = ""
        while true {
            if let current = inside {
                if let range = buffer.range(of: current.close) {
                    buffer = String(buffer[range.upperBound...])
                    inside = nil
                    continue
                }
                // Still reasoning: drop it, but keep what could start the close marker.
                buffer = final ? "" : String(buffer.suffix(current.close.count - 1))
                return out
            }
            var earliest: (range: Range<String.Index>, marker: ReasoningMarkers, opens: Bool)?
            for marker in markers {
                for (text, opens) in [(marker.open, true), (marker.close, false)] {
                    if let range = buffer.range(of: text), earliest.map({ range.lowerBound < $0.range.lowerBound }) ?? true {
                        earliest = (range, marker, opens)
                    }
                }
            }
            if let found = earliest {
                out += buffer[..<found.range.lowerBound]
                buffer = String(buffer[found.range.upperBound...])
                if found.opens { inside = found.marker }
                continue
            }
            let keep = final ? 0 : partialMarkerLength(at: buffer)
            out += buffer.dropLast(keep)
            buffer = String(buffer.suffix(keep))
            return out
        }
    }

    /// Length of the longest tail of `text` that is the start of some marker.
    private func partialMarkerLength(at text: String) -> Int {
        var best = 0
        for marker in markers.flatMap({ [$0.open, $0.close] }) {
            for length in stride(from: min(marker.count - 1, text.count), to: best, by: -1)
            where text.hasSuffix(marker.prefix(length)) {
                best = length
                break
            }
        }
        return best
    }

    /// One sentence before it is spoken: control-token text, markdown, and a leading label
    /// ("Summary:") on the first sentence.
    public static func tidy(_ sentence: String, isFirst: Bool) -> String {
        var text = sentence
        text = text.replacingOccurrences(of: #"<\|[^<>\s]*\|?>|<[^<>\s|]*\|>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\s*(#{1,6}|[-*•+]|\d{1,2}[.)])\s+"#, with: "", options: .regularExpression)
        if isFirst {
            text = text.replacingOccurrences(
                of: #"^\s*(summary|résumé|in short|en bref|tl;dr)\s*:\s*"#, with: "",
                options: [.regularExpression, .caseInsensitive])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
