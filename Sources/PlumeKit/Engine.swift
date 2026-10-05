import CoreML
import FluidAudio
import Foundation

/// Modèles de transcription disponibles : toute la famille Parakeet TDT que FluidAudio sait
/// faire tourner, plus un dossier personnalisé. Ajouter un cas ici suffit à l'exposer dans
/// les réglages.
public enum EngineModel: String, CaseIterable, Codable, Sendable {
    /// Parakeet Ultra : ré-entraînement 2026 de Parakeet TDT v3, 25 langues européennes,
    /// le plus précis en français parmi les modèles temps réel embarquables.
    case parakeetUltra = "parakeet-ultra"
    /// Parakeet TDT v3 d'origine (NVIDIA), 25 langues.
    case parakeetV3 = "parakeet-v3"
    /// Parakeet Redux : v3 compressé en 2 bits, trois fois plus petit, un peu moins précis en anglais.
    case parakeetRedux = "parakeet-redux"
    /// Parakeet TDT v2 : anglais seulement, la référence historique.
    case parakeetV2 = "parakeet-v2"
    /// Phonon-2 : ré-entraînement de v3 pour l'anglais, très compact.
    case phonon2 = "phonon-2"
    /// Parakeet TDT-CTC 110M : petit et très rapide, anglais.
    case parakeetTdtCtc110m = "parakeet-tdt-ctc-110m"
    /// Parakeet japonais.
    case parakeetJa = "parakeet-ja"
    /// Un dossier choisi par l'utilisateur, au format Parakeet (quatre `.mlmodelc` et
    /// `parakeet_vocab.json`) : modèle ré-entraîné, converti soi-même, ou communautaire.
    case custom = "custom"

    public var label: String {
        switch self {
        case .parakeetUltra: return tr("Parakeet Ultra (recommandé)")
        case .parakeetV3: return tr("Parakeet TDT v3")
        case .parakeetRedux: return tr("Parakeet Redux (compact)")
        case .parakeetV2: return tr("Parakeet TDT v2 (anglais)")
        case .phonon2: return tr("Phonon-2 (anglais, compact)")
        case .parakeetTdtCtc110m: return tr("Parakeet TDT-CTC 110M (anglais, rapide)")
        case .parakeetJa: return tr("Parakeet japonais")
        case .custom: return tr("Dossier personnalisé…")
        }
    }

    /// Langues, taille, précision : de quoi choisir en connaissance de cause.
    public var detail: String {
        switch self {
        case .parakeetUltra:
            return tr("25 langues européennes dont le français · 600 Mo · le plus précis (FLEURS fr ≈ 4,3 % d'erreur), ~150× le temps réel.")
        case .parakeetV3:
            return tr("25 langues européennes · 600 Mo · le modèle NVIDIA d'origine, un peu moins précis qu'Ultra à la même vitesse.")
        case .parakeetRedux:
            return tr("25 langues européennes · 220 Mo · encodeur 2 bits : trois fois plus petit, un peu moins précis en anglais, meilleur que v3 ailleurs. Première compilation de plusieurs minutes.")
        case .parakeetV2:
            return tr("Anglais seulement · 600 Mo · le plus précis en anglais (LibriSpeech 2,1 % d'erreur).")
        case .phonon2:
            return tr("Anglais seulement · très compact · ré-entraînement de v3 par Fermion Research.")
        case .parakeetTdtCtc110m:
            return tr("Anglais seulement · 110 M de paramètres · le plus rapide et le plus léger en mémoire.")
        case .parakeetJa:
            return tr("Japonais seulement · 600 Mo.")
        case .custom:
            return tr("Un dossier contenant Preprocessor, Encoder, Decoder et JointDecision (.mlmodelc) et parakeet_vocab.json, par exemple un Parakeet ré-entraîné et converti avec FluidAudio. Jamais téléchargé, jamais mis à jour.")
        }
    }

    /// Le modèle est fourni par FluidAudio (téléchargé une fois depuis Hugging Face).
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

    /// Le modèle est déjà dans le cache (ou le dossier personnalisé est complet).
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

/// Intervalle de parole attribué à un locuteur par la diarisation.
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
    /// Empreinte vocale moyenne par locuteur (vecteur normalisé).
    public var embeddings: [String: [Float]]
}

public enum EngineError: LocalizedError {
    case notReady
    case noCustomModel
    case incompleteCustomModel(String)

    public var errorDescription: String? {
        switch self {
        case .notReady: return tr("Le modèle de transcription n'est pas encore chargé.")
        case .noCustomModel: return tr("Aucun dossier de modèle personnalisé n'est choisi (Réglages › Modèle).")
        case .incompleteCustomModel(let name): return "Le dossier du modèle ne contient pas \(name)."
        }
    }
}

// Les modèles CoreML du diariseur sont en lecture seule après chargement ; l'acteur sérialise le reste.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

public enum EngineLoadPhase: Sendable {
    case downloading(Double)
    case compiling
    case ready
}

/// Moteur de reconnaissance vocale 100 % local (CoreML, Neural Engine).
public actor SpeechEngine {
    public static let shared = SpeechEngine()
    public static let sampleRate = 16_000

    private var asr: AsrManager?
    private var loadedModel: EngineModel?
    /// Dossier du modèle personnalisé chargé, pour le recharger s'il change.
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

    /// Charge le modèle (le télécharge au premier lancement, ~600 Mo). Un modèle personnalisé
    /// est lu dans son dossier, celui des réglages sauf indication contraire.
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

    /// Les fichiers qu'un dossier de modèle personnalisé doit contenir.
    public static let customModelFiles = ["Preprocessor.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc", "parakeet_vocab.json"]

    /// Ce qui manque dans un dossier pour en faire un modèle (vide : il est complet).
    public static func missingCustomFiles(in directory: URL) -> [String] {
        customModelFiles.filter { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Charge un dossier au format Parakeet. La famille (v2, v3, TDT-CTC) se devine à la taille
    /// du vocabulaire et à la présence d'un encodeur séparé.
    static func loadCustom(at directory: URL) throws -> AsrModels {
        if let missing = missingCustomFiles(in: directory).first { throw EngineError.incompleteCustomModel(missing) }
        let vocabulary = directory.appendingPathComponent("parakeet_vocab.json")
        let count = (try? JSONSerialization.jsonObject(with: Data(contentsOf: vocabulary)) as? [String: Any])?.count ?? 0
        let fused = !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Encoder.mlmodelc").path)
        let version: AsrModelVersion = fused ? .tdtCtc110m : (count > 2_000 ? .v3 : .v2)
        return try AsrModels.loadLocal(from: directory, version: version)
    }

    /// Libère les modèles (plusieurs centaines de Mo). Ils se rechargent depuis le cache
    /// disque, en une fraction de seconde, au prochain `prepare`.
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

    // MARK: - Annulation d'écho

    /// Retire du micro le son de l'ordinateur que les haut-parleurs y ont renvoyé (réunion
    /// sans casque). `reference` est ce son, sur la même ligne de temps et de même longueur.
    ///
    /// Le signal nettoyé n'est utilisé que là où l'ordinateur émettait quelque chose : partout
    /// ailleurs le micro d'origine est conservé tel quel, pour ne pas altérer la voix.
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

        // Fondu d'une trame à l'autre entre micro d'origine et micro nettoyé.
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

    /// Par trames de 100 ms : vrai si la référence porte du son, avec une marge d'une demi-seconde
    /// de part et d'autre (réverbération de la pièce, léger décalage entre les canaux).
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

    /// Transcrit des échantillons mono 16 kHz. Gère l'audio long (découpage interne).
    public func transcribe(_ samples: [Float]) async throws -> EngineOutput {
        guard let asr else { throw EngineError.notReady }
        var audio = samples
        // Le modèle refuse moins de 300 ms : on complète par du silence.
        let minimum = Self.sampleRate
        if audio.count < minimum {
            audio.append(contentsOf: [Float](repeating: 0, count: minimum - audio.count))
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(audio, decoderState: &state)
        let words = Self.words(from: result.tokenTimings ?? [])
        return EngineOutput(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            words: words,
            duration: Double(samples.count) / Double(Self.sampleRate),
            processing: result.processingTime
        )
    }

    /// Mots horodatés. Une ponctuation isolée (« ? », « ! », « : » à la française) est
    /// rattachée au mot qui précède, pour ne jamais ouvrir un tour de parole.
    static func words(from timings: [TokenTiming]) -> [Word] {
        var words: [Word] = []
        for timing in buildWordTimings(from: timings) {
            let isPunctuation = timing.word.allSatisfy { ".,;:!?…»".contains($0) }
            if isPunctuation, var last = words.popLast() {
                let separator = timing.word.first.map { "?!:;»".contains($0) } == true ? " " : ""
                last.text += separator + timing.word
                last.end = timing.endTime
                words.append(last)
            } else {
                words.append(Word(text: timing.word, start: timing.startTime, end: timing.endTime))
            }
        }
        return words
    }

    // MARK: - Diarisation

    /// Diariseur pour un nombre de voix donné (`nil` : détection automatique). Les modèles
    /// ne sont chargés qu'une fois ; seule la configuration du regroupement change.
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

    /// Précharge les modèles de diarisation (téléchargement au premier usage).
    public func prepareDiarizer() async throws {
        _ = try await loadDiarizer()
    }

    /// « Qui parle quand » sur des échantillons mono 16 kHz.
    /// - Parameter speakers: nombre de voix imposé, quand l'utilisateur le connaît.
    public func diarize(
        _ samples: [Float], speakers: Int? = nil, mergeSimilar: Bool = true
    ) async throws -> DiarizationOutput {
        // En dessous de deux secondes la diarisation n'a pas de sens.
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
        // Quand le nombre de voix est imposé, on ne refusionne rien derrière.
        return mergeSimilar && speakers == nil ? Self.mergingSimilarVoices(output) : output
    }

    /// Seuil de regroupement des voix (distance) : plus il est bas, plus le diariseur sépare.
    static let clusteringThreshold: Double =
        ProcessInfo.processInfo.environment["PLUME_DIAR_THRESHOLD"].flatMap(Double.init) ?? 0.6

    /// Ressemblance au-delà de laquelle deux voix détectées sont tenues pour la même personne.
    static let sameVoiceSimilarity: Float =
        ProcessInfo.processInfo.environment["PLUME_SAME_VOICE"].flatMap(Float.init) ?? 0.72

    /// Retire les voix fantômes : un « locuteur » qui ne parle que quelques secondes sur toute
    /// une réunion est presque toujours un bruit ou un éclat de voix mal classé. Ses mots
    /// reviennent alors au locuteur voisin.
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

    /// Le regroupement automatique coupe parfois une même voix en deux. On ne refusionne que
    /// des empreintes quasi identiques : deux personnes à la voix proche (deux frères, par
    /// exemple) atteignent couramment 0,5 de ressemblance et doivent rester distinctes.
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

        // Empreinte du groupe : moyenne des empreintes fusionnées.
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

        // Tours consécutifs du même locuteur recollés.
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
