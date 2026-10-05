import Foundation

/// Un canal audio capté : ses échantillons mono 16 kHz et son décalage par rapport au début de session.
public struct ChannelAudio: Sendable {
    public var channel: AudioChannel
    public var samples: [Float]
    public var offset: Double

    public init(channel: AudioChannel, samples: [Float], offset: Double = 0) {
        self.channel = channel
        self.samples = samples
        self.offset = offset
    }

    public var duration: Double { offset + Double(samples.count) / Double(SpeechEngine.sampleRate) }
}

public struct ConversationResult: Sendable {
    public var segments: [Segment]
    public var speakers: [String]
    /// Dialogue en texte brut : `Interlocuteur [mm:ss] : texte`.
    public var text: String
    public var rawText: String
}

public enum PipelineStage: Sendable {
    case cleaningEcho
    case transcribing
    case separatingSpeakers
}

/// Ce qu'on fait du texte d'une dictée une fois transcrit, dans l'ordre : nettoyage des
/// hésitations, commandes vocales, vocabulaire, puis style propre à l'application.
public struct DictationOptions: Sendable {
    public var cleanup: Bool
    public var voiceCommands: Bool
    public var style: DictationStyle

    public init(cleanup: Bool = true, voiceCommands: Bool = true, style: DictationStyle = .standard) {
        self.cleanup = cleanup
        self.voiceCommands = voiceCommands
        self.style = style
    }

    public init(settings: PlumeSettings, style: DictationStyle = .standard) {
        self.init(cleanup: settings.cleanup, voiceCommands: settings.voiceCommands, style: style)
    }
}

public struct DictationResult: Sendable, Equatable {
    public var text: String
    /// Sortie brute du modèle.
    public var raw: String
    /// La dictée demandait d'appuyer sur Entrée à la fin.
    public var pressReturn: Bool

    public init(text: String, raw: String, pressReturn: Bool = false) {
        self.text = text
        self.raw = raw
        self.pressReturn = pressReturn
    }
}

/// Traitements de fin d'enregistrement, communs à l'app, à l'import et à la ligne de commande.
public enum Pipeline {
    /// Dictée : transcription de tout l'audio, puis mise en forme du texte.
    public static func dictation(
        samples: [Float], engine: SpeechEngine, options: DictationOptions
    ) async throws -> DictationResult {
        guard !AudioLevel.isSilent(samples) else { return DictationResult(text: "", raw: "") }
        let output = try await engine.transcribe(samples)
        return format(output.text, options: options)
    }

    /// Mise en forme du texte brut d'une dictée, sans audio : la même pour l'app, la reprise,
    /// l'import et le diagnostic `plume format`.
    /// - Parameter final: faux pour un morceau écrit au fil de la dictée (le style n'y touche pas au point final).
    public static func format(
        _ raw: String, options: DictationOptions, replacements: [Replacement]? = nil, final: Bool = true
    ) -> DictationResult {
        var text = options.cleanup ? TextCleanup.clean(raw) : raw
        var pressReturn = false
        if options.voiceCommands {
            let commands = VoiceCommands.apply(to: text)
            text = commands.text
            pressReturn = commands.pressReturn
        }
        text = ReplacementStore.apply(replacements ?? ReplacementStore.load(), to: text)
        text = TextStyle.apply(options.style, to: text, final: final)
        return DictationResult(text: text, raw: raw, pressReturn: pressReturn)
    }

    /// Réunion ou import : transcription de chaque canal, séparation des voix, fil chronologique.
    /// - Parameter ownerOnMic: vrai quand le micro est celui du propriétaire (réunion sur le Mac) ;
    ///   un micro à voix unique est alors étiqueté « Moi ».
    public static func conversation(
        channels: [ChannelAudio], engine: SpeechEngine, voiceprint: Voiceprint?, ownerOnMic: Bool,
        cancelEcho: Bool = true, speakerCount: Int? = nil, stage: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> ConversationResult {
        let replacements = ReplacementStore.load()
        var runs: [TranscriptBuilder.Run] = []
        var micRuns: [TranscriptBuilder.Run] = []
        var systemWords: [Word] = []
        var rawParts: [String] = []
        var me = Set<String>()
        var turnGap = TranscriptBuilder.paragraphGap
        let hasSystem = channels.contains { $0.channel == .system && !AudioLevel.isSilent($0.samples) }
        var channels = channels
        if cancelEcho, hasSystem,
            let micIndex = channels.firstIndex(where: { $0.channel == .mic }),
            let system = channels.first(where: { $0.channel == .system })
        {
            // Sans casque, le micro réentend le son de l'ordinateur : on l'en retire avant tout,
            // sinon les interlocuteurs distants apparaissent deux fois et brouillent les voix.
            let mic = channels[micIndex]
            let reference = aligned(system, to: mic)
            // Au casque, rien ne repasse dans le micro : inutile de le traiter.
            if echoLikelihood(mic: mic.samples, reference: reference) >= 0.3 {
                stage?(.cleaningEcho)
                if let cleaned = try? await engine.cancelEcho(mic: mic.samples, reference: reference) {
                    channels[micIndex].samples = cleaned
                }
            }
        }

        for audio in channels.sorted(by: { $0.channel == .mic && $1.channel != .mic }) {
            guard !AudioLevel.isSilent(audio.samples) else { continue }
            stage?(.transcribing)
            let output = try await engine.transcribe(audio.samples)
            guard !output.words.isEmpty else { continue }
            rawParts.append(output.text)

            // Nombre de voix attendu sur ce canal, si l'utilisateur l'a précisé : en réunion à
            // deux canaux, le propriétaire est seul à son micro et les autres sont sur l'autre.
            var expected: Int?
            if let speakerCount {
                if hasSystem {
                    expected = audio.channel == .system ? max(1, speakerCount - 1) : nil
                } else {
                    expected = max(1, speakerCount)
                }
            }
            stage?(.separatingSpeakers)
            let diarization =
                (try? await engine.diarize(audio.samples, speakers: expected))
                ?? DiarizationOutput(turns: [], embeddings: [:])
            let voices = Set(diarization.turns.map(\.speaker))
            let prefix = audio.channel == .mic ? "mic" : "sys"

            // Qui est « Moi » ? Une voix unique sur le micro du propriétaire, sinon l'empreinte vocale.
            if audio.channel == .mic {
                if ownerOnMic, voices.count <= 1, hasSystem || voiceprint == nil || voices.isEmpty {
                    me.insert("\(prefix):\(voices.first ?? "seul")")
                } else if let voiceprint, let match = voiceprint.match(in: diarization.embeddings) {
                    me.insert("\(prefix):\(match)")
                }
            }

            let words = output.words.map {
                Word(text: $0.text, start: $0.start + audio.offset, end: $0.end + audio.offset)
            }
            let turns = diarization.turns.map {
                SpeakerTurn(speaker: $0.speaker, start: $0.start + audio.offset, end: $0.end + audio.offset)
            }
            // Sans aucun tour détecté, tout le canal revient à un seul locuteur.
            // À plusieurs, une même personne garde la parole malgré ses silences ; seule, ses
            // longues pauses ouvrent un nouveau paragraphe.
            let several = hasSystem || voices.count > 1
            if several { turnGap = 8 }
            let channelRuns = TranscriptBuilder.runs(
                words: words, turns: turns, channel: audio.channel, gap: several ? 8 : TranscriptBuilder.paragraphGap
            ) { id in
                "\(prefix):\(id ?? "seul")"
            }
            if audio.channel == .system {
                systemWords = words
                runs.append(contentsOf: channelRuns)
            } else {
                micRuns = channelRuns
            }
        }

        // Filet de sécurité après l'annulation d'écho : ce qui répète le son système mot pour mot.
        runs.append(contentsOf: TranscriptBuilder.removingEcho(mic: micRuns, systemWords: systemWords))
        let segments = TranscriptBuilder.segments(from: TranscriptBuilder.interleave(runs, gap: turnGap), me: me).map { segment in
            var segment = segment
            segment.text = ReplacementStore.apply(replacements, to: segment.text)
            return segment
        }
        return ConversationResult(
            segments: segments, speakers: TranscriptBuilder.speakers(in: segments),
            text: TranscriptBuilder.text(for: segments), rawText: rawParts.joined(separator: "\n\n"))
    }

    /// Refait la séparation des voix d'une transcription à partir de son audio conservé,
    /// éventuellement en imposant le nombre de personnes dans la conversation.
    public static func reprocess(
        _ transcript: Transcript, speakerCount: Int?, settings: PlumeSettings = .shared, engine: SpeechEngine = .shared
    ) async throws -> Transcript {
        let store = settings.store
        try await engine.prepare(model: settings.model)
        var channels: [ChannelAudio] = []
        for url in store.audioURLs(for: transcript) where FileManager.default.fileExists(atPath: url.path) {
            let channel: AudioChannel = url.lastPathComponent.contains("_sys.") ? .system : .mic
            channels.append(ChannelAudio(channel: channel, samples: try AudioIO.loadSamples(url)))
        }
        guard !channels.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let result = try await conversation(
            channels: channels, engine: engine, voiceprint: VoiceprintStore.load(),
            ownerOnMic: transcript.mode == .meeting, speakerCount: speakerCount)
        guard !result.segments.isEmpty else { return transcript }
        var updated = transcript
        updated.segments = result.segments
        updated.speakers = result.speakers
        updated.text = result.text
        updated.rawText = result.rawText
        try store.save(updated)
        return updated
    }
}

extension Pipeline {
    /// Mesure à quel point le micro « suit » le son de l'ordinateur (0 : pas du tout, 1 :
    /// parfaitement). On compare les enveloppes sonores des deux canaux, là où l'ordinateur
    /// émet, en tolérant le retard du trajet haut-parleur → micro.
    public static func echoLikelihood(mic: [Float], reference: [Float]) -> Float {
        let frame = SpeechEngine.sampleRate / 20  // 50 ms
        let count = min(mic.count, reference.count) / frame
        guard count > 40 else { return 0 }
        func envelope(_ samples: [Float]) -> [Float] {
            (0..<count).map { index in
                log10(max(AudioLevel.rms(samples[(index * frame)..<((index + 1) * frame)]), 0.000_03))
            }
        }
        let micEnvelope = envelope(mic)
        let referenceEnvelope = envelope(reference)
        let floor = log10(Float(0.002))
        var best: Float = 0
        for lag in 0...6 {
            var x: [Float] = []
            var y: [Float] = []
            for index in 0..<(count - lag) where referenceEnvelope[index] > floor {
                x.append(referenceEnvelope[index])
                y.append(micEnvelope[index + lag])
            }
            guard x.count > 40 else { continue }
            let meanX = x.reduce(0, +) / Float(x.count)
            let meanY = y.reduce(0, +) / Float(y.count)
            var covariance: Float = 0
            var varianceX: Float = 0
            var varianceY: Float = 0
            for i in 0..<x.count {
                covariance += (x[i] - meanX) * (y[i] - meanY)
                varianceX += (x[i] - meanX) * (x[i] - meanX)
                varianceY += (y[i] - meanY) * (y[i] - meanY)
            }
            let denominator = (varianceX * varianceY).squareRoot()
            if denominator > 0 { best = max(best, covariance / denominator) }
        }
        return best
    }

    /// Le canal `source` ramené sur la ligne de temps de `target` : même origine, même longueur.
    static func aligned(_ source: ChannelAudio, to target: ChannelAudio) -> [Float] {
        let shift = Int(((target.offset - source.offset) * Double(SpeechEngine.sampleRate)).rounded())
        var output = [Float](repeating: 0, count: target.samples.count)
        for i in 0..<output.count {
            let j = i + shift
            if j >= 0 && j < source.samples.count { output[i] = source.samples[j] }
        }
        return output
    }
}

/// Stockage de l'empreinte vocale du propriétaire.
public enum VoiceprintStore {
    public static var url: URL { PlumeSettings.supportDirectory.appendingPathComponent("empreinte-vocale.json") }

    public static func load() -> Voiceprint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Voiceprint.self, from: data)
    }

    public static func save(_ voiceprint: Voiceprint) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(voiceprint).write(to: url, options: .atomic)
    }

    /// Apprend la voix du propriétaire à partir d'une dictée : par construction, c'est lui qui parle.
    /// Ignoré si la dictée est courte ou si plusieurs voix y sont détectées.
    public static func learn(from samples: [Float], engine: SpeechEngine) async {
        guard samples.count >= SpeechEngine.sampleRate * 8 else { return }
        guard let output = try? await engine.diarize(samples), output.embeddings.count == 1,
            let embedding = output.embeddings.values.first, !embedding.isEmpty
        else { return }
        if var existing = load(), existing.embedding.count == embedding.count {
            existing.add(embedding)
            save(existing)
        } else {
            save(Voiceprint(embedding: embedding, samples: 1))
        }
    }
}
