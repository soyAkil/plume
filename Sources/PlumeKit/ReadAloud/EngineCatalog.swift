import FluidAudio
import Foundation

/// A model file on Hugging Face, pinned to a revision and checked by size and SHA-256.
public struct ModelDownload: Sendable, Equatable {
    public let repo: String
    public let revision: String
    public let file: String
    public let bytes: Int64
    public let sha256: String

    /// Built on each attempt: the CDN redirects to signed URLs that expire.
    public var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")! }
}

/// Text a model wraps its reasoning in; it must never be spoken.
public struct ReasoningMarkers: Sendable, Equatable {
    public let open: String
    public let close: String
}

/// How a request becomes the model's prompt. llama.cpp's C formatter only knows common
/// template families: Qwen3.5 is one (ChatML), Gemma 4 is not, hence `.explicit`.
public enum PromptFormat: Sendable, Equatable {
    /// The template embedded in the GGUF, then a fixed text after the assistant header.
    case embedded(assistantPrefix: String)
    /// A format with `{system}` and `{user}` placeholders.
    case explicit(template: String)
}

public struct LlamaModelSpec: Sendable, Equatable {
    public let download: ModelDownload
    public let promptFormat: PromptFormat
    public let contextTokens: Int
    /// Other sampling values come from the GGUF's metadata (`Sampling.resolve`).
    public let temperature: Float
    public let reasoningMarkers: [ReasoningMarkers]
}

public enum EngineTier: String, Sendable {
    case accurate, fast
}

public struct EngineLicense: Sendable, Equatable {
    public let name: String
    public let url: URL
}

/// What the user picks in Settings: a model and the service that runs it.
public struct SummaryEngineEntry: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    /// English; shown through `tr()` by the interface.
    public let blurb: String
    public let tier: EngineTier
    public let license: EngineLicense
    public let kind: Kind

    public enum Kind: Sendable, Equatable {
        case llama(LlamaModelSpec)
    }

    public var markers: [ReasoningMarkers] {
        switch kind {
        case .llama(let spec): return spec.reasoningMarkers
        }
    }
}

public enum SummaryEngineCatalog {
    public static let qwen35_4b = SummaryEngineEntry(
        id: "qwen3.5-4b-q4km", name: "Qwen3.5 4B", blurb: "More accurate", tier: .accurate,
        license: EngineLicense(name: "Apache 2.0", url: URL(string: "https://huggingface.co/Qwen/Qwen3.5-4B")!),
        kind: .llama(LlamaModelSpec(
            download: ModelDownload(
                repo: "unsloth/Qwen3.5-4B-GGUF", revision: "e87f176479d0855a907a41277aca2f8ee7a09523",
                file: "Qwen3.5-4B-Q4_K_M.gguf", bytes: 2_740_937_888,
                sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"),
            // The empty think block turns reasoning off, as the model's own template does
            // when `enable_thinking` is false.
            promptFormat: .embedded(assistantPrefix: "<think>\n\n</think>\n\n"),
            contextTokens: 16_384, temperature: 0.3,
            reasoningMarkers: [ReasoningMarkers(open: "<think>", close: "</think>")])))

    public static let gemma4_e2b = SummaryEngineEntry(
        id: "gemma4-e2b-q4", name: "Gemma 4 E2B", blurb: "Faster", tier: .fast,
        license: EngineLicense(name: "Apache 2.0", url: URL(string: "https://huggingface.co/google/gemma-4-E2B-it")!),
        kind: .llama(LlamaModelSpec(
            download: ModelDownload(
                repo: "ggml-org/gemma-4-E2B-it-GGUF", revision: "b4243c156154b6dca9324415f8c7ccc098b4aed1",
                file: "gemma-4-E2B-it-Q4_0.gguf", bytes: 2_841_481_184,
                sha256: "8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52"),
            // From the official template (google/gemma-4-E2B-it chat_template.jinja), thinking off.
            // The tokenizer adds BOS: the template must not contain it.
            promptFormat: .explicit(template: "<|turn>system\n{system}<turn|>\n<|turn>user\n{user}<turn|>\n<|turn>model\n"),
            contextTokens: 16_384, temperature: 0.3,
            reasoningMarkers: [ReasoningMarkers(open: "<|channel>thought", close: "<channel|>")])))

    /// The candidates; the quality eval decides which ones ship.
    public static let all: [SummaryEngineEntry] = [qwen35_4b, gemma4_e2b]

    public static func entry(id: String, in catalog: [SummaryEngineEntry] = all) -> SummaryEngineEntry? {
        catalog.first { $0.id == id }
    }

    /// The more accurate model on a Pro, Max or Ultra chip or an M5 and later, with at least
    /// 16 GB; the faster one otherwise. Based on projections from llama.cpp's public Apple
    /// Silicon benchmark, not on a speed test.
    public static func recommended(chip: String, memoryBytes: UInt64, in catalog: [SummaryEngineEntry] = all) -> SummaryEngineEntry? {
        guard let first = catalog.first else { return nil }
        guard catalog.count > 1 else { return first }
        let accurate = isPowerful(chip: chip) && memoryBytes >= 16 << 30
        return catalog.first { $0.tier == (accurate ? .accurate : .fast) } ?? first
    }

    static func isPowerful(chip: String) -> Bool {
        if chip.contains(" Pro") || chip.contains(" Max") || chip.contains(" Ultra") { return true }
        guard let range = chip.range(of: #"M\d+"#, options: .regularExpression),
              let generation = Int(chip[range].dropFirst())
        else { return false }
        return generation >= 5
    }

    /// "Apple M5", "Apple M2 Pro"…
    public static var thisMacChip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

public struct VoiceEntry: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let style: Supertonic3Voice
}

public enum VoiceCatalog {
    public static let f1 = VoiceEntry(id: "supertonic3-f1", name: "F1", style: .f1)
    public static let m2 = VoiceEntry(id: "supertonic3-m2", name: "M2", style: .m2)
    public static let all = [f1, m2]

    /// An unknown id (a voice removed later) falls back to the default voice.
    public static func entry(id: String) -> VoiceEntry {
        all.first { $0.id == id } ?? f1
    }
}

/// The Supertonic-3 files: where they live, which variant, which revision.
public enum VoiceAssets {
    public static let repoID = "FluidInference/supertonic-3-coreml"
    public static let revision = "512104b0229d08fab9f1e8e9e5280858231cc4fc"
    /// The variant the bench measured (~90× real time on an M5). FluidAudio's own name for it
    /// is internal; a test checks this string against the public part.
    public static let variant = "ane-int4"
    public static let vectorEstimator: Supertonic3VectorEstimator = .aneBucketed(.int4)
    /// FluidAudio adds this folder under the directory it is given.
    public static let folderName = "supertonic-3"
    /// Written once the whole download succeeded: FluidAudio only checks that files exist,
    /// and an interrupted bundle can leave `weight.bin.partial` behind.
    public static let completeMarker = ".complete"
    public static let approximateBytes: Int64 = 170_000_000

    public static func folder(in modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The marker and every file: FluidAudio downloads whatever is missing when it loads, so a
    /// folder that lost a file after its marker must count as absent.
    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        let folder = folder(in: modelsDirectory)
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(completeMarker).path)
            && hasAllFiles(in: modelsDirectory)
    }

    /// FluidAudio's own list for the pinned variant, and every voice's style.
    static func hasAllFiles(in modelsDirectory: URL) -> Bool {
        let folder = folder(in: modelsDirectory)
        let models = ModelNames.Supertonic3.requiredFiles(veVariant: variant).map { folder.appendingPathComponent($0) }
        let styles = VoiceCatalog.all.map { styleURL($0.style, in: modelsDirectory) }
        return (models + styles).allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func styleURL(_ voice: Supertonic3Voice, in modelsDirectory: URL) -> URL {
        folder(in: modelsDirectory).appendingPathComponent(voice.fileName)
    }

    /// Pins the voice files to a fixed commit. Called once at process start, before any
    /// FluidAudio call: FluidAudio reads this dictionary unsynchronized during every download.
    public static func pinRevision() {
        var overrides = ModelRegistry.revisionOverrides
        overrides[repoID] = revision
        ModelRegistry.revisionOverrides = overrides
    }
}
