import Foundation

/// Reprise des enregistrements interrompus.
///
/// Pendant une réunion, l'audio est écrit au fil de l'eau dans des fichiers `.wav` ; une
/// dictée dont la transcription échoue est elle aussi mise de côté. Si l'app s'arrête avant
/// d'avoir produit le transcript (plantage, extinction, modèle indisponible), ces fichiers
/// restent seuls dans la bibliothèque : on les retrouve ici pour terminer le travail.
public enum Recovery {
    public struct Pending: Sendable, Equatable {
        public var id: String
        public var mode: RecordingMode
        public var mic: URL
        public var system: URL?
    }

    static let dictationSuffix = "_dictee.wav"
    static let micSuffix = "_mic.wav"
    static let systemSuffix = "_sys.wav"

    /// Fichier où mettre de côté l'audio d'une dictée non transcrite.
    public static func dictationURL(id: String, store: TranscriptStore) throws -> URL {
        try store.ensureDirectory(forID: id).appendingPathComponent(id + dictationSuffix)
    }

    /// Écrit des échantillons dans un fichier de reprise.
    public static func stash(_ samples: [Float], at url: URL) {
        guard let writer = try? WavWriter(url: url) else { return }
        writer.append(samples)
        writer.close()
    }

    /// Enregistrements audio sans transcript, hors session en cours.
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
                } else if name.hasSuffix(dictationSuffix) {
                    mode = .dictation
                    id = String(name.dropLast(dictationSuffix.count))
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

    /// Transcrit un enregistrement interrompu et le range dans la bibliothèque.
    /// Les fichiers de reprise sont supprimés une fois le transcript écrit.
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
        var audio: [(String, [Float])] = [("mic", micSamples)]

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
            var channels = [ChannelAudio(channel: .mic, samples: micSamples)]
            if let system = pending.system, let samples = try? AudioIO.loadSamples(system) {
                channels.append(ChannelAudio(channel: .system, samples: samples))
                audio.append(("sys", samples))
            }
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
            for (label, samples) in audio where !AudioLevel.isSilent(samples) {
                let name = "\(pending.id)_\(label).m4a"
                if (try? AudioIO.writeM4A(samples, to: directory.appendingPathComponent(name))) != nil {
                    transcript.audioFiles.append(name)
                }
            }
        }
        try store.save(transcript)
        discard()
        return transcript
    }
}
