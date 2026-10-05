import Foundation

/// Transcrit un fichier audio existant et le range dans la bibliothèque
/// (glisser-déposer, menu, ligne de commande).
public enum Importer {
    public static let audioExtensions: Set<String> = [
        "m4a", "wav", "mp3", "caf", "aac", "aiff", "aif", "flac", "mp4", "mov", "qta", "opus", "ogg",
    ]

    public static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// - Parameters:
    ///   - mode: `.dictation` produit un texte nettoyé d'une seule voix ; les autres modes
    ///     séparent les interlocuteurs.
    ///   - save: écrit le transcript (et l'audio, si les réglages le demandent) dans la bibliothèque.
    public static func importAudio(
        at url: URL, mode: RecordingMode, device: String, date: Date = Date(), save: Bool = true,
        settings: PlumeSettings = .shared, engine: SpeechEngine = .shared
    ) async throws -> Transcript {
        try await engine.prepare(model: settings.model)
        let samples = try AudioIO.loadSamples(url)
        let duration = Double(samples.count) / Double(SpeechEngine.sampleRate)
        let store = settings.store
        let id = store.makeID(for: date)

        var transcript: Transcript
        if mode == .dictation {
            let result = try await Pipeline.dictation(
                samples: samples, engine: engine, options: DictationOptions(settings: settings))
            transcript = Transcript(
                id: id, createdAt: date, mode: .dictation, device: device, duration: duration,
                engine: await engine.modelName, text: result.text, rawText: result.raw)
        } else {
            let result = try await Pipeline.conversation(
                channels: [ChannelAudio(channel: .mic, samples: samples)], engine: engine,
                voiceprint: VoiceprintStore.load(), ownerOnMic: false)
            transcript = Transcript(
                id: id, createdAt: date, mode: mode, device: device, duration: duration,
                engine: await engine.modelName, text: result.text, rawText: result.rawText,
                segments: result.segments, speakers: result.speakers)
        }

        guard save else { return transcript }
        if settings.keepAudio {
            let dir = try store.ensureDirectory(forID: id)
            let name = "\(id)_mic.m4a"
            if (try? AudioIO.writeM4A(samples, to: dir.appendingPathComponent(name))) != nil {
                transcript.audioFiles = [name]
            }
        }
        try store.save(transcript)
        return transcript
    }
}
