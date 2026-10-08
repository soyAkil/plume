import Foundation

/// How long a spoken summary is, relative to the selection's size (`SummaryPrompt.sentenceBudget`).
public enum SummaryLength: String, CaseIterable, Sendable {
    case short, automatic, detailed
}

/// The language a summary is written in. Word-for-word reading always follows the text.
public enum SummaryLanguage: String, CaseIterable, Sendable {
    case sameAsText, interface, fr, en
}

/// How long the read-aloud models stay in memory after a read: the summary model holds ~3 GB.
public enum KeepLoaded: String, CaseIterable, Sendable {
    case fiveMinutes = "5min"
    case thirtyMinutes = "30min"
    case always

    /// Seconds before unloading, or `nil` to keep the models loaded.
    public var delay: TimeInterval? {
        switch self {
        case .fiveMinutes: return 300
        case .thirtyMinutes: return 1800
        case .always: return nil
        }
    }

    /// Used while the user has not chosen: Macs with room keep the model longer, so quick
    /// gists during a work session don't pay the 1.5–3 s load every time.
    public static func defaultFor(memoryBytes: UInt64) -> KeepLoaded {
        memoryBytes >= 16 << 30 ? .thirtyMinutes : .fiveMinutes
    }
}

/// Playback speed: a pitch-preserving time-stretch, in quarter steps.
public enum ReadAloudSpeed {
    public static let range: ClosedRange<Double> = 0.75...2.0
    public static let step = 0.25
    public static let defaultValue = 1.5

    public static func clamped(_ value: Double) -> Double {
        let stepped = (value / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
