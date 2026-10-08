import Foundation
import PlumeKit
import Testing
@testable import Plume

@Suite("plume read-aloud")
struct ReadAloudCommandTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")

    func context(engine: String = "") -> ReadAloudCommand.Context {
        ReadAloudCommand.Context(
            models: ReadAloudModels(directory: folder, installVoice: { _, _ in Issue.record("must not download") }),
            catalog: SummaryEngineCatalog.all, engineInUse: engine, voiceID: "supertonic3-f1", speed: 1.5,
            options: SummaryOptions(length: .automatic, language: .sameAsText), interface: .english)
    }

    @Test func parsesOptions() {
        #expect(ReadAloudCommand.parse([]) == ReadAloudCommand.Options())
        #expect(ReadAloudCommand.parse(["--summary", "--json", "--engine", "gemma4-e2b-q4"])
            == ReadAloudCommand.Options(summary: true, json: true, engineID: "gemma4-e2b-q4"))
        #expect(ReadAloudCommand.parse(["--download", "voice"]) == ReadAloudCommand.Options(download: "voice"))
        #expect(ReadAloudCommand.parse(["--eval", "/x", "--engines", "a,b", "--out", "/y.json"])
            == ReadAloudCommand.Options(evalFolder: "/x", evalEngines: ["a", "b"], evalOut: "/y.json"))
        #expect(ReadAloudCommand.parse(["--engine"]) == nil)
        #expect(ReadAloudCommand.parse(["--bogus"]) == nil)
    }

    @Test func printsTheWordForWordTextWithoutTheVoice() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines: [String] = []
        let code = await ReadAloudCommand.run(
            ReadAloudCommand.Options(textOnly: true), context: context(),
            input: "First sentence here. Second one.", emit: { lines.append($0) }, fail: { Issue.record("\($0)") })
        #expect(code == 0)
        #expect(lines == ["First sentence here.", "Second one."])
    }

    @Test func speakingWithoutTheVoiceFailsAndDownloadsNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(ReadAloudCommand.Options(), context: context(), input: "Hello there.", emit: { _ in }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        #expect(errors == [ReadAloudError.voiceNotInstalled.localizedDescription])
        try #expect(!FileManager.default.fileExists(atPath: folder.path) || FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func summarizingWithoutAModelFails() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(ReadAloudCommand.Options(summary: true, textOnly: true), context: context(engine: "qwen3.5-4b-q4km"),
                                       input: "Hello there.", emit: { _ in }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        #expect(errors == [ReadAloudError.engineNotInstalled.localizedDescription])
    }

    @Test func anUnknownEngineIsReported() async {
        var errors: [String] = []
        let code = await ReadAloudCommand.run(ReadAloudCommand.Options(summary: true, engineID: "nope"), context: context(),
                                              input: "Hello.", emit: { _ in }, fail: { errors.append($0) })
        #expect(code == 1)
        #expect(errors == [ReadAloudError.unknownEngine.localizedDescription])
    }

    /// An eval folder with one selection, and a results file outside any repository.
    func evalSetup(selections: Bool = true) throws -> (folder: URL, options: ReadAloudCommand.Options) {
        let eval = folder.appendingPathComponent("eval")
        let selectionsFolder = eval.appendingPathComponent("selections")
        try FileManager.default.createDirectory(at: selectionsFolder, withIntermediateDirectories: true)
        if selections { try "A text.".write(to: selectionsFolder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8) }
        return (eval, ReadAloudCommand.Options(
            evalFolder: selectionsFolder.path, evalEngines: ["nope-a", "nope-b"], evalOut: eval.appendingPathComponent("results.json").path))
    }

    func evalError(_ options: ReadAloudCommand.Options) async -> [String] {
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(options, context: context(), input: "", emit: { _ in Issue.record("must not write") }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        return errors
    }

    @Test func theEvalChecksItsArgumentsBeforeAnyModelLoads() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (eval, valid) = try evalSetup()
        // Valid arguments get as far as the engine lookup (the catalog has no "nope-a"), which proves the checks passed.
        #expect(await evalError(valid) == [ReadAloudError.unknownEngine.localizedDescription])
        for engines in [["qwen3.5-4b-q4km"], ["a", "a"], ["a", "b", "c"], []] {
            var options = valid
            options.evalEngines = engines
            #expect(await evalError(options) == [ReadAloudError.evalNeedsTwoEngines.localizedDescription])
        }
        var noOut = valid
        noOut.evalOut = nil
        #expect(await evalError(noOut) == [ReadAloudError.evalOutRequired.localizedDescription])
        var empty = valid
        empty.evalFolder = eval.path
        #expect(await evalError(empty) == [ReadAloudError.evalNoSelections.localizedDescription])
        var missing = valid
        missing.evalFolder = eval.appendingPathComponent("nothing-here").path
        #expect(await evalError(missing) == [ReadAloudError.evalNoSelections.localizedDescription])
    }

    @Test func theEvalRefusesAResultsFileInsideAGitWorkTree() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (eval, valid) = try evalSetup()
        // A repository root, then a linked worktree (its .git is a file), then a folder that does not exist yet below one.
        let repository = folder.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let worktree = folder.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: elsewhere".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        for out in [repository.appendingPathComponent("results.json"), worktree.appendingPathComponent("deep/new/results.json")] {
            var options = valid
            options.evalOut = out.path
            #expect(await evalError(options) == [ReadAloudError.evalOutInsideRepository.localizedDescription])
        }
        #expect(ReadAloudEvalCommand.isInsideGitWorkTree(repository.appendingPathComponent("a/b.json")))
        #expect(!ReadAloudEvalCommand.isInsideGitWorkTree(eval.appendingPathComponent("results.json")))
    }

    /// An installed engine whose model is `service`: the command never touches llama.cpp.
    func summaryContext(_ service: ScriptedSummaryService) throws -> ReadAloudCommand.Context {
        var context = context(engine: "qwen3.5-4b-q4km")
        let entry = try #require(SummaryEngineCatalog.entry(id: "qwen3.5-4b-q4km", in: context.catalog))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: context.models.modelURL(for: entry).path, contents: Data())
        context.summaryService = { _, _ in service }
        return context
    }

    func json(_ options: ReadAloudCommand.Options, context: ReadAloudCommand.Context) async throws -> [String: Any] {
        var lines: [String] = []
        let code = await ReadAloudCommand.run(options, context: context, input: "The release moves to Friday. Tests are green.",
                                              emit: { lines.append($0) }, fail: { Issue.record("\($0)") })
        #expect(code == 0)
        return try #require(JSONSerialization.jsonObject(with: Data(lines.joined().utf8)) as? [String: Any])
    }

    /// Scripts read `--json`: both modes give the same keys, `null` where a phase does not apply.
    @Test func jsonHasTheSameKeysInBothModes() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let keys: Set<String> = ["mode", "engine", "language", "sentences", "truncated", "timings"]
        let timingKeys: Set<String> = ["loadSeconds", "readingInputSeconds", "firstSentenceSeconds", "totalSeconds"]

        let wordForWord = try await json(ReadAloudCommand.Options(json: true), context: context())
        #expect(Set(wordForWord.keys) == keys)
        #expect(wordForWord["engine"] is NSNull)
        let plain = try #require(wordForWord["timings"] as? [String: Any])
        #expect(Set(plain.keys) == timingKeys)
        for key in ["loadSeconds", "readingInputSeconds", "firstSentenceSeconds"] { #expect(plain[key] is NSNull, "\(key)") }
        #expect(plain["totalSeconds"] is Double)

        let service = ScriptedSummaryService(pieces: ["Friday it is."])
        let summary = try await json(ReadAloudCommand.Options(summary: true, json: true), context: try summaryContext(service))
        #expect(Set(summary.keys) == keys)
        #expect(summary["engine"] as? String == "qwen3.5-4b-q4km")
        #expect(summary["sentences"] as? [String] == ["Friday it is."])
        let timed = try #require(summary["timings"] as? [String: Any])
        #expect(Set(timed.keys) == timingKeys)
        for key in timingKeys { #expect(timed[key] is Double, "\(key)") }
    }

    /// Each timing is its own phase: reading starts once the input is ready, the first
    /// sentence counts from the end of the load, and only the total spans the command.
    @Test func timingsAreDurationsOfTheirOwnPhase() {
        let start = ContinuousClock.now
        func at(_ milliseconds: Int) -> ContinuousClock.Instant { start + .milliseconds(milliseconds) }
        var timings = ReadAloudCommand.Timings(start: start)
        timings.loaded(from: at(100), at: at(1600))
        timings.note(.loading, at: at(1600))
        timings.note(.language("en"), at: at(1700))
        timings.note(.readingInput(1), at: at(1950))
        timings.note(.summarizing, at: at(2000))
        timings.note(.sentence("One."), at: at(2500))
        timings.note(.sentence("Two."), at: at(2900))
        let values = timings.dictionary(at: at(3000))
        #expect(values["loadSeconds"] as? Decimal == Decimal(string: "1.5"))
        #expect(values["readingInputSeconds"] as? Decimal == Decimal(string: "0.3"))
        #expect(values["firstSentenceSeconds"] as? Decimal == Decimal(string: "0.9"))
        #expect(values["totalSeconds"] as? Decimal == Decimal(string: "3"))

        let wordForWord = ReadAloudCommand.Timings(start: start).dictionary(at: at(1234))
        #expect(wordForWord["loadSeconds"] is NSNull)
        #expect(wordForWord["totalSeconds"] as? Decimal == Decimal(string: "1.234"))
    }

    /// Loading the summary model takes seconds of GPU setup: without the voice there is no
    /// point starting it.
    @Test func summarySpeakingChecksTheVoiceBeforeLoadingTheModel() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ScriptedSummaryService(pieces: ["Never spoken."])
        let context = try summaryContext(service)
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(ReadAloudCommand.Options(summary: true), context: context,
                                       input: "Hello there.", emit: { _ in }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        #expect(errors == [ReadAloudError.voiceNotInstalled.localizedDescription])
        #expect(await service.loads == 0)
    }

    /// "Select some text first." is the app's wording: on the command line the text comes in on stdin.
    @Test func emptyInputSaysNothingCameInOnStandardInput() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ScriptedSummaryService(pieces: ["Never written."])
        let summaryContext = try summaryContext(service)
        for (options, context) in [(ReadAloudCommand.Options(textOnly: true), context()),
                                   (ReadAloudCommand.Options(summary: true, json: true), summaryContext)] {
            for input in ["", " \n", "…!"] {
                var errors: [String] = []
                let code = await L10n.$override.withValue(.english) {
                    await ReadAloudCommand.run(options, context: context, input: input, emit: { _ in }, fail: { errors.append($0) })
                }
                #expect(code == 1)
                #expect(errors == ["Nothing to read on standard input."])
            }
        }
        // Nothing to summarize: the model is not loaded for it.
        #expect(await service.loads == 0)
    }

    /// Typed with no pipe, the command would wait silently for Ctrl-D.
    @Test func aTerminalStandardInputIsNotRead() {
        let read = ReadAloudCommand.Options()
        #expect(ReadAloudCommand.input(for: read, isTerminal: true, read: { Issue.record("must not read"); return "" }) == nil)
        #expect(ReadAloudCommand.input(for: read, isTerminal: false, read: { "Piped text." }) == "Piped text.")
        // Downloads and the eval take no text: a terminal is fine.
        for options in [ReadAloudCommand.Options(download: "voice"), ReadAloudCommand.Options(evalFolder: "/x")] {
            #expect(ReadAloudCommand.input(for: options, isTerminal: true, read: { Issue.record("must not read"); return "" }) == "")
        }
    }

    /// A mistyped option prints this usage: it must show every option the parser accepts.
    @Test func theUsageListsEveryOption() {
        for flag in ["--summary", "--text", "--json", "--engine", "--download", "--eval", "--engines", "--out"] {
            let alone = ["--summary", "--text", "--json"].contains(flag)
            #expect(ReadAloudCommand.parse(alone ? [flag] : [flag, "x"]) != nil, "\(flag)")
            for language in [Language.english, .french] {
                let usage = L10n.$override.withValue(language) { ReadAloudCommand.usage }
                #expect(usage.range(of: flag + "(?![a-z])", options: .regularExpression) != nil, "\(language) \(flag)")
            }
        }
    }

    /// Each line of the main usage keeps at least two spaces between the command and what it does.
    @Test func usageLinesKeepAGapBeforeTheirDescription() {
        for language in [Language.english, .french] {
            let usage = L10n.$override.withValue(language) { CLI.usage }
            for line in usage.split(separator: "\n") where line.hasPrefix("  plume") {
                #expect(line.dropFirst(2).contains("  "), "\(language): \(line)")
            }
        }
    }

    /// The judge page grades length and language against automatic and "same as the text":
    /// the user's own settings must not reach the eval.
    @Test func theEvalIgnoresTheUsersSummarySettings() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (eval, valid) = try evalSetup()
        try "The release moves to Friday because two blocking bugs remain open.".write(
            to: URL(fileURLWithPath: valid.evalFolder!).appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        var options = valid
        options.evalEngines = ["qwen3.5-4b-q4km", "gemma4-e2b-q4"]
        var context = context()
        context.options = SummaryOptions(length: .short, language: .fr)
        let services = ["qwen3.5-4b-q4km": ScriptedSummaryService(pieces: ["Friday."]), "gemma4-e2b-q4": ScriptedSummaryService(pieces: ["Friday."])]
        for id in services.keys {
            let entry = try #require(SummaryEngineCatalog.entry(id: id, in: context.catalog))
            FileManager.default.createFile(atPath: context.models.modelURL(for: entry).path, contents: Data())
        }
        context.summaryService = { entry, _ in services[entry.id]! }
        let code = await ReadAloudCommand.run(options, context: context, input: "", emit: { _ in }, fail: { Issue.record("\($0)") })
        #expect(code == 0)
        #expect(FileManager.default.fileExists(atPath: eval.appendingPathComponent("results.json").path))
        for service in services.values {
            let requests = await service.requests
            #expect(requests.map(\.language) == ["en"])
            #expect(requests.map(\.maxSentences) == [SummaryPrompt.sentenceBudget(words: 11, length: .automatic)])
        }
    }

    @Test func theCommandWordReachesTheCommandLine() {
        #expect(CLI.commands.contains("read-aloud"))
        #expect(CLI.handles(["plume", "read-aloud"]))
    }
}

/// A summary service that writes the given pieces, and counts its loads.
actor ScriptedSummaryService: SummaryService {
    let pieces: [String]
    private(set) var loads = 0
    private(set) var requests: [SummaryRequest] = []

    init(pieces: [String]) { self.pieces = pieces }

    var isLoaded: Bool { loads > 0 }
    func load() { loads += 1 }
    var inputBudget: Int { 10_000 }
    func countTokens(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func unload() {}
    private func record(_ request: SummaryRequest) { requests.append(request) }

    nonisolated func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error> {
        let pieces = self.pieces
        return AsyncThrowingStream { continuation in
            Task {
                await self.record(request)
                continuation.yield(.readingInput(fraction: 1))
                for piece in pieces { continuation.yield(.text(piece)) }
                continuation.finish()
            }
        }
    }
}
