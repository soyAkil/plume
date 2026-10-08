import Foundation

/// A captured audio channel: its mono 16 kHz samples and its offset from the start of the session.
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

    /// The samples preceded by `offset` seconds of silence: a file read at offset 0 stays on
    /// the session timeline.
    public var paddedSamples: [Float] {
        [Float](repeating: 0, count: Int(offset * Double(SpeechEngine.sampleRate))) + samples
    }

    /// The channels a meeting keeps as files: silent ones skipped, with their file label.
    /// Silence is judged on the samples, not the padded array: the lead is silent anyway, and
    /// building it just to test would cost memory. Nothing is padded here: each caller pads one
    /// channel at a time, so one padded array is in memory at once.
    public static func tracksToKeep(_ channels: [ChannelAudio]) -> [(label: String, audio: ChannelAudio)] {
        channels.filter { !AudioLevel.isSilent($0.samples) }.map { ($0.channel == .mic ? "mic" : "sys", $0) }
    }
}

public struct ConversationResult: Sendable {
    public var segments: [Segment]
    public var speakers: [String]
    /// Dialogue as plain text: `Speaker [mm:ss]: text`.
    public var text: String
    public var rawText: String
}

public enum PipelineStage: Sendable {
    case cleaningEcho
    case transcribing
    case separatingSpeakers
}

/// What is done to a dictation's text once transcribed, in order: hesitation
/// cleanup, voice commands, vocabulary, then the app's own style.
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
    /// Raw model output.
    public var raw: String
    /// The dictation asked to press Return at the end.
    public var pressReturn: Bool

    public init(text: String, raw: String, pressReturn: Bool = false) {
        self.text = text
        self.raw = raw
        self.pressReturn = pressReturn
    }
}

/// End-of-recording processing, shared by the app, the import and the command line.
public enum Pipeline {
    /// Dictation: transcription of all the audio, then text formatting.
    public static func dictation(
        samples: [Float], engine: SpeechEngine, options: DictationOptions
    ) async throws -> DictationResult {
        guard !AudioLevel.isSilent(samples) else { return DictationResult(text: "", raw: "") }
        let output = try await engine.transcribe(samples)
        return format(output.text, options: options)
    }

    /// Formatting of a dictation's raw text, without audio: the same for the app, recovery,
    /// the import and the `plume format` diagnostic.
    /// - Parameter final: false for a chunk typed as the dictation goes (style leaves the final period alone).
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

    /// Meeting or import: transcription of each channel, diarization, chronological thread.
    /// - Parameter ownerOnMic: true when the microphone is the owner's (meeting on the Mac);
    ///   a single-voice microphone is then labelled "Me".
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
            // Without headphones, the microphone hears the computer's audio again: remove it first,
            // otherwise the remote speakers appear twice and blur the voices.
            let mic = channels[micIndex]
            let reference = aligned(system, to: mic)
            // With headphones, nothing flows back into the microphone: no need to process it.
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

            // Expected number of voices on this channel, if the user specified it: in a two-channel
            // meeting, the owner is alone on their microphone and the others are on the other channel.
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

            // Who is "Me"? A single voice on the owner's microphone, otherwise the voiceprint.
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
            // With no turn detected at all, the whole channel goes to a single speaker.
            // With several people, one person keeps the floor despite their silences; alone, their
            // long pauses open a new paragraph.
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

        // Safety net after echo cancellation: what repeats the system audio word for word.
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

    /// Redoes a transcript's diarization from its kept audio,
    /// optionally forcing the number of people in the conversation.
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
    /// Measures how closely the microphone "follows" the system audio (0: not at all, 1:
    /// perfectly). The sound envelopes of the two channels are compared, where the computer
    /// is playing, tolerating the speaker → microphone travel delay.
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

    /// The `source` channel brought onto the timeline of `target`: same origin, same length.
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

/// Storage of the owner's voiceprint.
public enum VoiceprintStore {
    public static var url: URL {
        let folder = PlumeSettings.supportDirectory
        return Migration.resolve(
            old: folder.appendingPathComponent("empreinte-vocale.json"), new: folder.appendingPathComponent("voiceprint.json"))
    }

    public static func load() -> Voiceprint? {
        read(from: url)
    }

    public static func save(_ voiceprint: Voiceprint) {
        try? write(voiceprint, to: url)
    }

    /// A voiceprint file, `nil` if it is missing or unreadable.
    public static func read(from url: URL) -> Voiceprint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Voiceprint.self, from: data)
    }

    public static func write(_ voiceprint: Voiceprint, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(voiceprint).write(to: url, options: .atomic)
    }

    /// Learns the owner's voice from a dictation: by construction, they are the one speaking.
    /// Ignored if the dictation is short or if several voices are detected in it.
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
