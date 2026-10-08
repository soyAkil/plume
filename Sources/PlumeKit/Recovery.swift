import Foundation

/// Recovery of interrupted recordings.
///
/// During a meeting, the audio is written as it goes to `.wav` files; a
/// dictation whose transcription fails is also set aside. If the app stops before
/// producing the transcript (crash, shutdown, model unavailable), these files
/// are left alone in the library: they are found here to finish the job.
public enum Recovery {
    public struct Pending: Sendable, Equatable {
        public var id: String
        public var mode: RecordingMode
        public var mic: URL
        public var system: URL?
    }

    /// Suffix of a dictation backup file.
    public static let dictationSuffix = "_dictation.wav"
    /// Name used up to 1.0.1: a backup left by a crash before the upgrade is still recovered.
    static let legacyDictationSuffix = "_dictee.wav"
    static let micSuffix = "_mic.wav"
    static let systemSuffix = "_sys.wav"

    /// File where the audio of an untranscribed dictation is set aside.
    public static func dictationURL(id: String, store: TranscriptStore) throws -> URL {
        try store.ensureDirectory(forID: id).appendingPathComponent(id + dictationSuffix)
    }

    /// A dictation's backup file, under its current or its 1.0.1 name.
    public static func isDictationBackup(_ name: String) -> Bool {
        name.hasSuffix(dictationSuffix) || name.hasSuffix(legacyDictationSuffix)
    }

    /// Writes samples to a recovery file.
    public static func stash(_ samples: [Float], at url: URL) {
        guard let writer = try? WavWriter(url: url) else { return }
        writer.append(samples)
        writer.close()
    }

    /// Audio recordings without a transcript, outside the current session.
    public static func pending(in store: TranscriptStore, excluding active: Set<String> = []) -> [Pending] {
        let fm = FileManager.default
        guard let months = try? fm.contentsOfDirectory(atPath: store.root.path) else { return [] }
        var found: [Pending] = []
        for month in months.sorted() where month.count == 7 {
            let directory = store.root.appendingPathComponent(month, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names.sorted() {
                let mode: RecordingMode
                let id: String
                if name.hasSuffix(micSuffix) {
                    mode = .meeting
                    id = String(name.dropLast(micSuffix.count))
                } else if let suffix = [dictationSuffix, legacyDictationSuffix].first(where: name.hasSuffix) {
                    mode = .dictation
                    id = String(name.dropLast(suffix.count))
                } else {
                    continue
                }
                guard !active.contains(id), store.load(id: id) == nil else { continue }
                let system = directory.appendingPathComponent(id + systemSuffix)
                found.append(
                    Pending(
                        id: id, mode: mode, mic: directory.appendingPathComponent(name),
                        system: mode == .meeting && fm.fileExists(atPath: system.path) ? system : nil))
            }
        }
        return found
    }

    /// A recovered meeting's channels, mic first, each at the offset its WAV recorded (0 for a
    /// 1.0.1 file). Both offsets count from the session start, as live, so none is subtracted.
    static func meetingChannels(
        mic: (samples: [Float], offset: Double?), system: (samples: [Float], offset: Double?)?
    ) -> [ChannelAudio] {
        var channels = [ChannelAudio(channel: .mic, samples: mic.samples, offset: mic.offset ?? 0)]
        if let system {
            channels.append(ChannelAudio(channel: .system, samples: system.samples, offset: system.offset ?? 0))
        }
        return channels
    }

    /// Transcribes an interrupted recording and files it in the library.
    /// The recovery files are deleted once the transcript is written.
    public static func recover(
        _ pending: Pending, settings: PlumeSettings = .shared, engine: SpeechEngine = .shared
    ) async throws -> Transcript? {
        let fm = FileManager.default
        let store = settings.store
        try await engine.prepare(model: settings.model)
        let files = [pending.mic, pending.system].compactMap { $0 }
        func discard() { files.forEach { try? fm.removeItem(at: $0) } }

        let micSamples = try AudioIO.loadSamples(pending.mic)
        let date = TranscriptStore.date(fromID: pending.id) ?? Date()
        var transcript: Transcript
        var kept = [ChannelAudio(channel: .mic, samples: micSamples)]

        if pending.mode == .dictation {
            let result = try await Pipeline.dictation(
                samples: micSamples, engine: engine, options: DictationOptions(settings: settings))
            guard !result.text.isEmpty else {
                discard()
                return nil
            }
            transcript = Transcript(
                id: pending.id, createdAt: date, mode: .dictation,
                duration: Double(micSamples.count) / Double(SpeechEngine.sampleRate),
                engine: await engine.modelName, text: result.text, rawText: result.raw)
        } else {
            var system: (samples: [Float], offset: Double?)?
            if let url = pending.system, let samples = try? AudioIO.loadSamples(url) {
                system = (samples, WavWriter.recordedOffset(of: url))
            }
            let channels = meetingChannels(
                mic: (micSamples, WavWriter.recordedOffset(of: pending.mic)), system: system)
            kept = channels
            let result = try await Pipeline.conversation(
                channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true)
            guard !result.segments.isEmpty else {
                discard()
                return nil
            }
            transcript = Transcript(
                id: pending.id, createdAt: date, mode: .meeting, duration: channels.map(\.duration).max() ?? 0,
                engine: await engine.modelName, text: result.text, rawText: result.rawText,
                segments: result.segments, speakers: result.speakers)
        }

        if settings.keepAudio {
            let directory = try store.ensureDirectory(forID: pending.id)
            for (label, audio) in ChannelAudio.tracksToKeep(kept) {
                let name = "\(pending.id)_\(label).m4a"
                if (try? AudioIO.writeM4A(audio.paddedSamples, to: directory.appendingPathComponent(name))) != nil {
                    transcript.audioFiles.append(name)
                }
            }
        }
        try store.save(transcript)
        discard()
        return transcript
    }
}
