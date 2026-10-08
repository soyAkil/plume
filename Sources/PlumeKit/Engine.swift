import CoreML
import FluidAudio
import Foundation

/// Available transcription models: the whole Parakeet TDT family FluidAudio can
/// run, plus a custom folder. Adding a case here is enough to expose it in
/// the settings.
public enum EngineModel: String, CaseIterable, Codable, Sendable {
    /// Parakeet Ultra: 2026 retraining of Parakeet TDT v3, 25 European languages,
    /// the most accurate in French among the embeddable real-time models.
    case parakeetUltra = "parakeet-ultra"
    /// Original Parakeet TDT v3 (NVIDIA), 25 languages.
    case parakeetV3 = "parakeet-v3"
    /// Parakeet Redux: v3 compressed to 2 bits, three times smaller, slightly less accurate in English.
    case parakeetRedux = "parakeet-redux"
    /// Parakeet TDT v2: English only, the historical reference.
    case parakeetV2 = "parakeet-v2"
    /// Phonon-2: retraining of v3 for English, very compact.
    case phonon2 = "phonon-2"
    /// Parakeet TDT-CTC 110M: small and very fast, English.
    case parakeetTdtCtc110m = "parakeet-tdt-ctc-110m"
    /// Parakeet Japanese.
    case parakeetJa = "parakeet-ja"
    /// A folder chosen by the user, in Parakeet format (four `.mlmodelc` and
    /// `parakeet_vocab.json`): a retrained, self-converted or community model.
    case custom = "custom"

    public var label: String {
        switch self {
        case .parakeetUltra: return tr("Parakeet Ultra (recommended)")
        case .parakeetV3: return tr("Parakeet TDT v3")
        case .parakeetRedux: return tr("Parakeet Redux (compact)")
        case .parakeetV2: return tr("Parakeet TDT v2 (English)")
        case .phonon2: return tr("Phonon-2 (English, compact)")
        case .parakeetTdtCtc110m: return tr("Parakeet TDT-CTC 110M (English, fast)")
        case .parakeetJa: return tr("Parakeet Japanese")
        case .custom: return tr("Custom folder…")
        }
    }

    /// Languages, size, accuracy: enough to make an informed choice.
    public var detail: String {
        switch self {
        case .parakeetUltra:
            return tr("25 European languages · 600 MB · the most accurate (FLEURS fr ≈ 4.3% error), ~150× real time.")
        case .parakeetV3:
            return tr("25 European languages · 600 MB · NVIDIA's original model, slightly less accurate than Ultra at the same speed.")
        case .parakeetRedux:
            return tr("25 European languages · 220 MB · 2-bit encoder: three times smaller, slightly less accurate in English, better than v3 elsewhere. First compile takes a few minutes.")
        case .parakeetV2:
            return tr("English only · 600 MB · the most accurate in English (LibriSpeech 2.1% error).")
        case .phonon2:
            return tr("English only · very compact · a retraining of v3 by Fermion Research.")
        case .parakeetTdtCtc110m:
            return tr("English only · 110M parameters · the fastest and lightest in memory.")
        case .parakeetJa:
            return tr("Japanese only · 600 MB.")
        case .custom:
            return tr("A folder containing Preprocessor, Encoder, Decoder and JointDecision (.mlmodelc) and parakeet_vocab.json, for example a Parakeet retrained and converted with FluidAudio. Never downloaded, never updated.")
        }
    }

    /// The model is provided by FluidAudio (downloaded once from Hugging Face).
    public var isBuiltIn: Bool { self != .custom }

    var version: AsrModelVersion? {
        switch self {
        case .parakeetUltra: return .ultra
        case .parakeetV3: return .v3
        case .parakeetRedux: return .redux
        case .parakeetV2: return .v2
        case .phonon2: return .phonon2
        case .parakeetTdtCtc110m: return .tdtCtc110m
        case .parakeetJa: return .tdtJa
        case .custom: return nil
        }
    }

    /// The model is already in the cache (or the custom folder is complete).
    public func isAvailableOffline(customDirectory: URL?) -> Bool {
        if let version { return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version) }
        guard let customDirectory else { return false }
        return AsrModels.modelsExist(at: customDirectory)
    }
}

public struct EngineOutput: Sendable {
    public var text: String
    public var words: [Word]
    public var duration: Double
    public var processing: Double
}

/// Time span attributed to a speaker by diarization.
public struct SpeakerTurn: Sendable, Equatable {
    public var speaker: String
    public var start: Double
    public var end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

public struct DiarizationOutput: Sendable {
    public var turns: [SpeakerTurn]
    /// Average voiceprint per speaker (normalized vector).
    public var embeddings: [String: [Float]]
}

public enum EngineError: LocalizedError {
    case notReady
    case noCustomModel
    case incompleteCustomModel(String)

    public var errorDescription: String? {
        switch self {
        case .notReady: return tr("The transcription model is not loaded yet.")
        case .noCustomModel: return tr("No custom model folder is chosen (Settings › Model).")
        case .incompleteCustomModel(let name): return tr("The model folder does not contain") + " \(name)."
        }
    }
}

// The diarizer's CoreML models are read-only after loading; the actor serializes the rest.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

public enum EngineLoadPhase: Sendable {
    case downloading(Double)
    case compiling
    case ready
}

/// Fully local speech recognition engine (CoreML, Neural Engine).
public actor SpeechEngine {
    public static let shared = SpeechEngine()
    public static let sampleRate = 16_000

    private var asr: AsrManager?
    private var loadedModel: EngineModel?
    /// Folder of the loaded custom model, to reload it if it changes.
    private var loadedDirectory: URL?
    private var loadTask: Task<Void, Error>?
    private var diarizer: OfflineDiarizerManager?
    private var fixedDiarizers: [Int: OfflineDiarizerManager] = [:]
    private var diarizerModels: OfflineDiarizerModels?
    private var diarizerTask: Task<OfflineDiarizerModels, Error>?
    private var echoCanceller: LocalVqeManager?

    public init() {}

    public var isReady: Bool { asr != nil }
    public var modelName: String {
        guard let loadedModel else { return "—" }
        if loadedModel == .custom, let loadedDirectory { return "custom:" + loadedDirectory.lastPathComponent }
        return loadedModel.rawValue
    }

    /// Loads the model (downloads it on first launch, ~600 MB). A custom model
    /// is read from its folder, the one in the settings unless stated otherwise.
    public func prepare(
        model: EngineModel, directory: URL? = nil, progress: (@Sendable (EngineLoadPhase) -> Void)? = nil
    ) async throws {
        let directory = model == .custom ? (directory ?? PlumeSettings.shared.customModelURL) : nil
        if loadedModel == model, asr != nil, loadedDirectory == directory { return }
        if let loadTask {
            try await loadTask.value
            if loadedModel == model, loadedDirectory == directory { return }
        }
        let task = Task {
            let models: AsrModels
            if let version = model.version {
                models = try await AsrModels.downloadAndLoad(
                    version: version,
                    progressHandler: { p in
                        switch p.phase {
                        case .listing: progress?(.downloading(0))
                        case .downloading: progress?(.downloading(p.fractionCompleted))
                        case .compiling: progress?(.compiling)
                        }
                    })
            } else {
                guard let directory else { throw EngineError.noCustomModel }
                progress?(.compiling)
                models = try Self.loadCustom(at: directory)
            }
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.install(manager, model: model, directory: directory)
            progress?(.ready)
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    private func install(_ manager: AsrManager, model: EngineModel, directory: URL?) {
        asr = manager
        loadedModel = model
        loadedDirectory = directory
    }

    /// The files a custom model folder must contain.
    public static let customModelFiles = ["Preprocessor.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc", "parakeet_vocab.json"]

    /// What is missing from a folder to make it a model (empty: it is complete).
    public static func missingCustomFiles(in directory: URL) -> [String] {
        customModelFiles.filter { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Loads a folder in Parakeet format. The family (v2, v3, TDT-CTC) is guessed from the vocabulary
    /// size and the presence of a separate encoder.
    static func loadCustom(at directory: URL) throws -> AsrModels {
        if let missing = missingCustomFiles(in: directory).first { throw EngineError.incompleteCustomModel(missing) }
        let vocabulary = directory.appendingPathComponent("parakeet_vocab.json")
        let count = (try? JSONSerialization.jsonObject(with: Data(contentsOf: vocabulary)) as? [String: Any])?.count ?? 0
        let fused = !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Encoder.mlmodelc").path)
        let version: AsrModelVersion = fused ? .tdtCtc110m : (count > 2_000 ? .v3 : .v2)
        return try AsrModels.loadLocal(from: directory, version: version)
    }

    /// Frees the models (several hundred MB). They reload from the disk cache
    /// in a fraction of a second, on the next `prepare`.
    public func unload() {
        guard loadTask == nil, diarizerTask == nil else { return }
        asr = nil
        loadedModel = nil
        loadedDirectory = nil
        diarizer = nil
        fixedDiarizers = [:]
        diarizerModels = nil
        echoCanceller = nil
    }

    // MARK: - Echo cancellation

    /// Removes from the microphone the system audio that the speakers played back into it (meeting
    /// without headphones). `reference` is that audio, on the same timeline and of the same length.
    ///
    /// The cleaned signal is only used where the computer was playing something: everywhere
    /// else the original microphone is kept as is, so the voice is not altered.
    public func cancelEcho(mic: [Float], reference: [Float]) async throws -> [Float] {
        guard mic.count == reference.count, !mic.isEmpty else { return mic }
        let active = Self.activityMask(reference)
        guard active.contains(true) else { return mic }
        if echoCanceller == nil {
            echoCanceller = try await LocalVqeManager()
        }
        guard let echoCanceller else { return mic }
        let cleaned = try await echoCanceller.process(mic: mic, reference: reference)
        guard cleaned.count == mic.count else { return mic }

        // Frame-to-frame crossfade between the original microphone and the cleaned one.
        let frame = Self.maskFrame
        var output = mic
        var weight: Float = 0
        let step = 1 / Float(frame / 2)
        for i in 0..<mic.count {
            let target: Float = active[min(i / frame, active.count - 1)] ? 1 : 0
            if weight < target { weight = min(target, weight + step) }
            if weight > target { weight = max(target, weight - step) }
            output[i] = mic[i] * (1 - weight) + cleaned[i] * weight
        }
        return output
    }

    static let maskFrame = sampleRate / 10

    /// In 100 ms frames: true if the reference carries sound, with a margin of half a second
    /// on each side (room reverberation, slight offset between channels).
    static func activityMask(_ reference: [Float], threshold: Float = 0.002) -> [Bool] {
        let frame = maskFrame
        let count = (reference.count + frame - 1) / frame
        var loud = [Bool](repeating: false, count: count)
        for index in 0..<count {
            let start = index * frame
            let end = min(start + frame, reference.count)
            loud[index] = AudioLevel.rms(reference[start..<end]) > threshold
        }
        var mask = loud
        let margin = 5
        for index in 0..<count where loud[index] {
            for neighbour in max(0, index - margin)...min(count - 1, index + margin) { mask[neighbour] = true }
        }
        return mask
    }

    /// Transcribes mono 16 kHz samples. Handles long audio (internal chunking).
    public func transcribe(_ samples: [Float]) async throws -> EngineOutput {
        guard let asr else { throw EngineError.notReady }
        var audio = samples
        // The model rejects less than 300 ms: pad with silence.
        let minimum = Self.sampleRate
        if audio.count < minimum {
            audio.append(contentsOf: [Float](repeating: 0, count: minimum - audio.count))
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(audio, decoderState: &state)
        let words = Self.words(from: result.tokenTimings ?? [])
        return EngineOutput(
            text: Self.removingUnknownTokens(result.text.trimmingCharacters(in: .whitespacesAndNewlines)),
            words: words,
            duration: Double(samples.count) / Double(Self.sampleRate),
            processing: result.processingTime
        )
    }

    /// Timestamped words, without unknown-token markers. An isolated punctuation mark ("?", "!",
    /// ":" in the French style) is attached to the preceding word, so it never opens a speaker turn.
    static func words(from timings: [TokenTiming]) -> [Word] {
        let base = buildWordTimings(from: timings).map { Word(text: $0.word, start: $0.startTime, end: $0.endTime) }
        var words: [Word] = []
        for word in removingUnknownTokens(base) {
            let isPunctuation = word.text.allSatisfy { attachedPunctuation.contains($0) }
            if isPunctuation, var last = words.popLast() {
                let separator = word.text.first.map { "?!:;»".contains($0) } == true ? " " : ""
                last.text += separator + word.text
                last.end = word.end
                words.append(last)
            } else {
                words.append(word)
            }
        }
        return words
    }

    /// Parakeet's marker for a sound it has no token for. Kept out of everything Plume shows or saves.
    static let unknownToken = "<unk>"

    /// Marks attached to the previous word, never a word of their own. One set, so `text` and
    /// `words` treat them alike.
    static let attachedPunctuation = ".,;:!?…»"

    /// The words without markers. Only a word holding one changes: the markers go, an emptied
    /// word is dropped, and a word left with punctuation only is glued to the previous word with
    /// no space (the model wrote none). The previous word keeps its own times: `LiveTranscriber`
    /// and diarization go by its midpoint. A dropped word's time span is lost; the others keep theirs.
    static func removingUnknownTokens(_ words: [Word]) -> [Word] {
        var result: [Word] = []
        for var word in words {
            guard word.text.contains(unknownToken) else {
                result.append(word)
                continue
            }
            word.text = word.text.replacingOccurrences(of: unknownToken, with: "")
            if word.text.isEmpty { continue }
            if word.text.allSatisfy({ attachedPunctuation.contains($0) }), var last = result.popLast() {
                last.text += word.text
                result.append(last)
            } else {
                result.append(word)
            }
        }
        return result
    }

    /// The same on a text: split on spaces, the word version, joined with single spaces. A text
    /// without a marker comes back byte for byte.
    static func removingUnknownTokens(_ text: String) -> String {
        guard text.contains(unknownToken) else { return text }
        let words = text.split(separator: " ").map { Word(text: String($0), start: 0, end: 0) }
        return removingUnknownTokens(words).map(\.text).joined(separator: " ")
    }

    // MARK: - Diarization

    /// Diarizer for a given number of voices (`nil`: automatic detection). The models
    /// are loaded only once; only the clustering configuration changes.
    private func loadDiarizer(speakers: Int? = nil) async throws -> OfflineDiarizerManager {
        if speakers == nil, let diarizer { return diarizer }
        if let speakers, let manager = fixedDiarizers[speakers] { return manager }
        if diarizerModels == nil {
            if let diarizerTask {
                diarizerModels = try await diarizerTask.value
            } else {
                let task = Task { try await OfflineDiarizerModels.load() }
                diarizerTask = task
                defer { diarizerTask = nil }
                diarizerModels = try await task.value
            }
        }
        guard let models = diarizerModels else { throw EngineError.notReady }
        var config = OfflineDiarizerConfig.default
        config.clustering.threshold = Self.clusteringThreshold
        config.clustering.numSpeakers = speakers
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        if let speakers { fixedDiarizers[speakers] = manager } else { diarizer = manager }
        return manager
    }

    /// Preloads the diarization models (downloaded on first use).
    public func prepareDiarizer() async throws {
        _ = try await loadDiarizer()
    }

    /// "Who speaks when" on mono 16 kHz samples.
    /// - Parameter speakers: forced number of voices, when the user knows it.
    public func diarize(
        _ samples: [Float], speakers: Int? = nil, mergeSimilar: Bool = true
    ) async throws -> DiarizationOutput {
        // Below two seconds diarization makes no sense.
        guard samples.count >= Self.sampleRate * 2 else {
            return DiarizationOutput(turns: [], embeddings: [:])
        }
        let manager = try await loadDiarizer(speakers: speakers)
        let result = try await manager.process(audio: samples)
        let turns = result.segments
            .map {
                SpeakerTurn(
                    speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
            }
            .sorted { $0.start < $1.start }
        let output = Self.removingPhantomVoices(
            DiarizationOutput(turns: turns, embeddings: result.speakerDatabase ?? [:]))
        // When the number of voices is forced, nothing is merged back afterwards.
        return mergeSimilar && speakers == nil ? Self.mergingSimilarVoices(output) : output
    }

    /// Voice clustering threshold (distance): the lower it is, the more the diarizer separates.
    static let clusteringThreshold: Double =
        ProcessInfo.processInfo.environment["PLUME_DIAR_THRESHOLD"].flatMap(Double.init) ?? 0.6

    /// Similarity above which two detected voices are taken to be the same person.
    static let sameVoiceSimilarity: Float =
        ProcessInfo.processInfo.environment["PLUME_SAME_VOICE"].flatMap(Float.init) ?? 0.72

    /// Removes ghost voices: a "speaker" who talks only a few seconds in a whole
    /// meeting is almost always noise or a misclassified stray burst of speech. Their words
    /// go back to the neighbouring speaker.
    static func removingPhantomVoices(_ output: DiarizationOutput) -> DiarizationOutput {
        var talk: [String: Double] = [:]
        for turn in output.turns { talk[turn.speaker, default: 0] += turn.end - turn.start }
        let total = talk.values.reduce(0, +)
        guard talk.count > 1, total > 0 else { return output }
        let phantoms = Set(talk.filter { $0.value < 6 && $0.value < total * 0.02 }.keys)
        guard !phantoms.isEmpty, phantoms.count < talk.count else { return output }
        return DiarizationOutput(
            turns: output.turns.filter { !phantoms.contains($0.speaker) },
            embeddings: output.embeddings.filter { !phantoms.contains($0.key) })
    }

    /// Automatic clustering sometimes splits one voice in two. Only near-identical
    /// voiceprints are merged back: two people with similar voices (two brothers, for
    /// example) commonly reach 0.5 similarity and must stay distinct.
    static func mergingSimilarVoices(_ output: DiarizationOutput) -> DiarizationOutput {
        let ids = output.embeddings.keys.sorted()
        guard ids.count > 1 else { return output }
        var parent = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        func root(_ id: String) -> String {
            var current = id
            while let next = parent[current], next != current { current = next }
            return current
        }
        for (index, a) in ids.enumerated() {
            for b in ids[(index + 1)...] {
                let similarity = Voiceprint.cosine(output.embeddings[a] ?? [], output.embeddings[b] ?? [])
                if similarity >= sameVoiceSimilarity {
                    parent[root(b)] = root(a)
                }
            }
        }
        guard ids.contains(where: { root($0) != $0 }) else { return output }

        // Group voiceprint: average of the merged voiceprints.
        var embeddings: [String: [Float]] = [:]
        var counts: [String: Float] = [:]
        for id in ids {
            guard let vector = output.embeddings[id] else { continue }
            let key = root(id)
            if var sum = embeddings[key], sum.count == vector.count {
                for i in 0..<sum.count { sum[i] += vector[i] }
                embeddings[key] = sum
            } else {
                embeddings[key] = vector
            }
            counts[key, default: 0] += 1
        }
        for (key, count) in counts where count > 1 {
            embeddings[key] = embeddings[key]?.map { $0 / count }
        }

        // Consecutive turns of the same speaker glued back together.
        var turns: [SpeakerTurn] = []
        for turn in output.turns {
            let speaker = parent[turn.speaker] == nil ? turn.speaker : root(turn.speaker)
            if let last = turns.last, last.speaker == speaker, turn.start - last.end < 0.5 {
                turns[turns.count - 1].end = max(last.end, turn.end)
            } else {
                turns.append(SpeakerTurn(speaker: speaker, start: turn.start, end: turn.end))
            }
        }
        return DiarizationOutput(turns: turns, embeddings: embeddings)
    }
}
