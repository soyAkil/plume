// Sources/PlumeKit/ReadAloud/ReadAloudEval.swift
import Foundation

/// The quality eval: every selection summarized by every engine, with timings. The owner
/// judges the summaries blind on the judge page (bench/read-aloud-eval).
public enum ReadAloudEval {
    /// What the judge page grades against ("right length", "right language"), whatever the
    /// user's own read-aloud settings are.
    public static let options = SummaryOptions(length: .automatic, language: .sameAsText)

    public struct Results: Codable, Equatable {
        public var created: Date
        public var engines: [EngineRun]
        public var items: [Item]
    }

    public struct EngineRun: Codable, Equatable {
        public var id: String
        public var name: String
        /// First load of the engine: kernels compiled, nothing in memory.
        public var coldLoadSeconds: Double
    }

    public struct Item: Codable, Equatable {
        public var file: String
        /// The source, so the judge page can show it next to the summaries.
        public var text: String
        public var words: Int
        public var results: [String: Outcome]
    }

    public struct Outcome: Codable, Equatable {
        public var summary: String
        public var sentences: Int
        public var language: String
        public var truncated: Bool
        /// The engine's first file, right after its cold load (`EngineRun.coldLoadSeconds`).
        public var cold: Bool
        public var readingInputSeconds: Double
        public var firstSentenceSeconds: Double
        public var totalSeconds: Double
        public var error: String?
    }

    public static func run(
        files: [(name: String, text: String)], engines: [(entry: SummaryEngineEntry, service: any SummaryService)],
        options: SummaryOptions, interface: Language, created: Date, progress: @escaping (String) -> Void
    ) async -> Results {
        var items = files.map { Item(file: $0.name, text: $0.text, words: SummaryPrompt.wordCount($0.text), results: [:]) }
        var runs: [EngineRun] = []
        for (entry, service) in engines {
            let loadStart = ContinuousClock.now
            let loadError: String?
            do { try await service.load(); loadError = nil } catch { loadError = error.localizedDescription }
            if let loadError { progress("\(entry.name): \(loadError)") }
            runs.append(EngineRun(id: entry.id, name: entry.name, coldLoadSeconds: seconds(since: loadStart)))
            var durations: [Double] = []
            for (index, file) in files.enumerated() {
                let left = durations.isEmpty ? "" : " (~\(Int(median(durations) * Double(files.count - index))) s left)"
                progress("\(entry.name): \(index + 1)/\(files.count) \(file.name)\(left)")
                if let loadError {
                    items[index].results[entry.id] = Outcome(
                        summary: "", sentences: 0, language: "", truncated: false, cold: index == 0,
                        readingInputSeconds: 0, firstSentenceSeconds: 0, totalSeconds: 0, error: loadError)
                } else {
                    // The first file runs right after the cold load: its timings are the cold ones.
                    var result = await outcome(file.text, entry: entry, service: service, options: options, interface: interface)
                    result.cold = index == 0
                    items[index].results[entry.id] = result
                    durations.append(result.totalSeconds)
                }
            }
            await service.unload()
        }
        return Results(created: created, engines: runs, items: items)
    }

    private static func outcome(
        _ text: String, entry: SummaryEngineEntry, service: any SummaryService, options: SummaryOptions, interface: Language
    ) async -> Outcome {
        let start = ContinuousClock.now
        var sentences: [String] = []
        var language = ""
        var truncated = false
        var readingInput = 0.0
        var firstSentence = 0.0
        do {
            for try await event in ReadAloudPipeline.summary(text, service: service, markers: entry.markers, options: options, interface: interface) {
                switch event {
                case .summarizing: readingInput = seconds(since: start)
                case .sentence(let sentence):
                    if sentences.isEmpty { firstSentence = seconds(since: start) }
                    sentences.append(sentence)
                case .language(let code): language = code
                case .truncated: truncated = true
                default: break
                }
            }
            return Outcome(summary: sentences.joined(separator: " "), sentences: sentences.count, language: language,
                           truncated: truncated, cold: false, readingInputSeconds: readingInput,
                           firstSentenceSeconds: firstSentence, totalSeconds: seconds(since: start), error: nil)
        } catch {
            return Outcome(summary: sentences.joined(separator: " "), sentences: sentences.count, language: language,
                           truncated: truncated, cold: false, readingInputSeconds: readingInput,
                           firstSentenceSeconds: firstSentence, totalSeconds: seconds(since: start),
                           error: error.localizedDescription)
        }
    }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
}
