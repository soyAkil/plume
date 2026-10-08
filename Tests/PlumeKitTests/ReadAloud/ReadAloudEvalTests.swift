// Tests/PlumeKitTests/ReadAloud/ReadAloudEvalTests.swift
import Foundation
import JavaScriptCore
import Testing
@testable import PlumeKit

@Suite("Read-aloud eval")
struct ReadAloudEvalTests {
    @Test func everyFileGetsEveryEngine() async throws {
        let a = FakeSummaryService(pieces: ["Summary A."])
        let b = FakeSummaryService(pieces: ["<|channel>thought x<channel|>"])  // b (Gemma's markers) fails: empty summary
        let results = await ReadAloudEval.run(
            files: [("mail.txt", "A first text to summarize here."), ("article.txt", "Another text to summarize.")],
            engines: [(SummaryEngineCatalog.qwen35_4b, a), (SummaryEngineCatalog.gemma4_e2b, b)],
            options: SummaryOptions(length: .automatic, language: .sameAsText), interface: .english,
            created: Date(timeIntervalSince1970: 0), progress: { _ in })
        #expect(results.engines.map(\.id) == ["qwen3.5-4b-q4km", "gemma4-e2b-q4"])
        #expect(results.items.map(\.file) == ["mail.txt", "article.txt"])
        #expect(results.items.map(\.text) == ["A first text to summarize here.", "Another text to summarize."])
        for item in results.items {
            #expect(item.results["qwen3.5-4b-q4km"]?.summary == "Summary A.")
            #expect(item.results["gemma4-e2b-q4"]?.error != nil)
        }
        #expect(results.items[0].results["qwen3.5-4b-q4km"]?.cold == true)
        #expect(results.items[1].results["qwen3.5-4b-q4km"]?.cold == false)
        let data = try JSONEncoder().encode(results)
        #expect(try JSONDecoder().decode(ReadAloudEval.Results.self, from: data) == results)
    }

    /// A model that cannot load (corrupt file, no memory) must not sink the other engine's run.
    @Test func aLoadFailureStillLetsTheOtherEngineFinish() async throws {
        let healthy = FakeSummaryService(pieces: ["Summary A."])
        let progress = Lines()
        let results = await L10n.$override.withValue(.english) {
            await ReadAloudEval.run(
                files: [("one.txt", "A first text to summarize here."), ("two.txt", "Another text to summarize.")],
                engines: [(SummaryEngineCatalog.gemma4_e2b, FailingLoadService()), (SummaryEngineCatalog.qwen35_4b, healthy)],
                options: SummaryOptions(length: .automatic, language: .sameAsText), interface: .english,
                created: Date(timeIntervalSince1970: 0), progress: { progress.append($0) })
        }
        // Said once, as it happens: otherwise the owner only learns of it on the judge page.
        let loadLine = "\(SummaryEngineCatalog.gemma4_e2b.name): \(ReadAloudError.loadFailed.localizedDescription)"
        #expect(progress.all.filter { $0 == loadLine }.count == 1)
        #expect(results.engines.map(\.id) == ["gemma4-e2b-q4", "qwen3.5-4b-q4km"])
        for item in results.items {
            #expect(item.results.count == 2)
            let failed = try #require(item.results["gemma4-e2b-q4"])
            #expect(failed.error != nil && failed.summary.isEmpty)
            #expect(item.results["qwen3.5-4b-q4km"]?.summary == "Summary A.")
            #expect(item.results["qwen3.5-4b-q4km"]?.error == nil)
        }
        // Loaded for the run, unloaded after it: the fake starts unloaded.
        #expect(await healthy.isLoaded == false)
    }

    /// The judge page's verdict math, run with the page's own script.
    @Test func judgeSummaryCountsPerEngine() throws {
        let script = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("bench/read-aloud-eval/judge.js"),
            encoding: .utf8)
        let context = try #require(JSContext())
        context.evaluateScript(script)
        // c: the cold first file. d: both engines errored (0 s timings). e: g wrote nothing (no first sentence).
        // Timings must ignore d, skip e's first sentence, and keep c apart from the warm medians.
        let results = #"{"engines":[{"id":"q"},{"id":"g"}],"items":[{"file":"a","words":100,"results":{"q":{"cold":false,"totalSeconds":2,"firstSentenceSeconds":1},"g":{"cold":false,"totalSeconds":1,"firstSentenceSeconds":0.5}}},{"file":"b","words":2000,"results":{"q":{"cold":false,"totalSeconds":4,"firstSentenceSeconds":3},"g":{"cold":false,"totalSeconds":2,"firstSentenceSeconds":1}}},{"file":"c","words":100,"results":{"q":{"cold":true,"totalSeconds":9,"firstSentenceSeconds":8},"g":{"cold":true,"totalSeconds":7,"firstSentenceSeconds":6}}},{"file":"d","words":100,"results":{"q":{"cold":false,"error":"x","totalSeconds":0,"firstSentenceSeconds":0},"g":{"cold":false,"error":"x","totalSeconds":0,"firstSentenceSeconds":0}}},{"file":"e","words":100,"results":{"g":{"cold":false,"sentences":0,"totalSeconds":3,"firstSentenceSeconds":0}}}]}"#
        let verdicts = #"{"a":{"order":["g","q"],"A":{"mainPoint":true,"nothingInvented":true,"rightLanguage":true,"rightLength":false},"B":{"mainPoint":true,"nothingInvented":false,"rightLanguage":true,"rightLength":true},"preference":"A"},"b":{"order":["q","g"],"A":{"mainPoint":true,"nothingInvented":true,"rightLanguage":true,"rightLength":true},"B":{"mainPoint":false,"nothingInvented":true,"rightLanguage":true,"rightLength":true},"preference":"equal"}}"#
        let summary = try #require(context.evaluateScript("JSON.stringify(PlumeJudge.summarize(\(results), \(verdicts)))")?.toString())
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        let engines = try #require(parsed["engines"] as? [String: [String: Any]])
        let q = try #require(engines["q"]?["all"] as? [String: Double])
        let g = try #require(engines["g"]?["all"] as? [String: Double])
        #expect(q["mainPoint"] == 1.0 && q["nothingInvented"] == 0.5)
        #expect(g["mainPoint"] == 0.5 && g["rightLength"] == 0.5)
        #expect(engines["g"]?["preferred"] as? Int == 1)
        #expect(engines["q"]?["preferred"] as? Int == 0)
        #expect(parsed["ties"] as? Int == 1)
        #expect(engines["q"]?["medianTotalSeconds"] as? Double == 3)
        // g: warm totals 1, 2 and 3 (the errored item is out); first sentences 0.5 and 1 (the empty one is out).
        #expect(engines["g"]?["medianTotalSeconds"] as? Double == 2)
        #expect(engines["g"]?["medianFirstSentenceSeconds"] as? Double == 0.75)
        let cold = try #require(engines["q"]?["cold"] as? [String: Double])
        #expect(cold["totalSeconds"] == 9 && cold["firstSentenceSeconds"] == 8)
        // Per length class: a is short, b is long; q is B in a and A in b.
        let qShort = try #require(engines["q"]?["short"] as? [String: Double])
        let qLong = try #require(engines["q"]?["long"] as? [String: Double])
        #expect(qShort["n"] == 1 && qShort["nothingInvented"] == 0)
        #expect(qLong["n"] == 1 && qLong["nothingInvented"] == 1)
        #expect(engines["q"]?["medium"] == nil)
        #expect(context.evaluateScript("PlumeJudge.below('rightLanguage', 0.94) && !PlumeJudge.below('rightLanguage', 0.95) && !PlumeJudge.below('rightLength', 0)")?.toBool() == true)
    }
}

/// A service whose model cannot load.
private struct FailingLoadService: SummaryService {
    var isLoaded: Bool { false }
    func load() async throws { throw ReadAloudError.loadFailed }
    var inputBudget: Int { 0 }
    func countTokens(_ text: String) async throws -> Int { 0 }
    func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: ReadAloudError.loadFailed) }
    }
    func unload() async {}
}

/// Progress lines, collected from the eval's callback.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}
