import Foundation

/// Un enregistrement annulé, gardé de côté quelque temps : un Échap de trop ne doit pas coûter
/// une réunion entière.
public struct CancelledRecording: Codable, Sendable, Identifiable, Equatable {
    /// Identifiant de la session, le même que celui qu'aurait eu sa transcription.
    public var id: String
    public var createdAt: Date
    public var cancelledAt: Date
    public var mode: RecordingMode
    public var duration: Double
    /// Application au premier plan au moment de l'enregistrement.
    public var app: String?
    /// Transcription faite en arrière-plan après l'annulation (dictées seulement), ou `nil`.
    public var text: String?
    public var rawText: String?
    /// Noms de fichiers audio, relatifs au dossier des annulés.
    public var audioFiles: [String]

    public init(
        id: String, createdAt: Date, cancelledAt: Date = Date(), mode: RecordingMode, duration: Double,
        app: String? = nil, text: String? = nil, rawText: String? = nil, audioFiles: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.cancelledAt = cancelledAt
        self.mode = mode
        self.duration = duration
        self.app = app
        self.text = text
        self.rawText = rawText
        self.audioFiles = audioFiles
    }

    /// Début du texte, pour les listes.
    public var preview: String? {
        guard let text, !text.isEmpty else { return nil }
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
    }
}

/// Les enregistrements annulés, rangés à part dans un dossier caché de la bibliothèque
/// (`~/Plume/.annules/`) : ils n'apparaissent ni dans l'index, ni dans `dernier.md`, ni dans
/// `plume last`, et ils disparaissent d'eux-mêmes passé le délai choisi dans les réglages.
///
///     ~/Plume/.annules/
///       2026-10-05_14-31-05.json       ce qu'on sait de l'enregistrement
///       2026-10-05_14-31-05_mic.m4a    l'audio du micro
///       2026-10-05_14-31-05_sys.m4a    le son de l'ordinateur (réunion)
public final class CancelledStore: @unchecked Sendable {
    public enum Failure: Error {
        /// La transcription n'a rien donné.
        case nothingHeard
    }

    public let root: URL
    private let fm = FileManager.default
    private static let lock = NSRecursiveLock()

    public init(library: URL) {
        root = library.appendingPathComponent(".annules", isDirectory: true)
    }

    private func jsonURL(forID id: String) -> URL { root.appendingPathComponent(id + ".json") }

    public func audioURLs(for recording: CancelledRecording) -> [URL] {
        recording.audioFiles.map { root.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Met de côté un enregistrement annulé. L'audio est écrit d'abord : un enregistrement
    /// n'est visible qu'une fois complet.
    /// - Parameter system: le son de l'ordinateur et son décalage par rapport au début.
    public func keep(_ recording: CancelledRecording, mic: [Float], system: (samples: [Float], offset: Double)? = nil) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var recording = recording
        recording.audioFiles = []
        let micName = "\(recording.id)_mic.m4a"
        try AudioIO.writeM4A(mic, to: root.appendingPathComponent(micName))
        recording.audioFiles.append(micName)
        if let system, !AudioLevel.isSilent(system.samples) {
            // Silence initial égal au décalage : les deux pistes restent calées l'une sur l'autre.
            let lead = [Float](repeating: 0, count: Int(system.offset * Double(SpeechEngine.sampleRate)))
            let name = "\(recording.id)_sys.m4a"
            if (try? AudioIO.writeM4A(lead + system.samples, to: root.appendingPathComponent(name))) != nil {
                recording.audioFiles.append(name)
            }
        }
        try write(recording)
    }

    /// Réécrit la fiche d'un enregistrement encore présent (texte trouvé après coup).
    public func update(_ recording: CancelledRecording) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard fm.fileExists(atPath: jsonURL(forID: recording.id).path) else { return }
        try? write(recording)
    }

    private func write(_ recording: CancelledRecording) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: jsonURL(forID: recording.id), options: .atomic)
    }

    /// Du plus récemment annulé au plus ancien.
    public func list() -> [CancelledRecording] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name in
                (try? Data(contentsOf: root.appendingPathComponent(name)))
                    .flatMap { try? decoder.decode(CancelledRecording.self, from: $0) }
            }
            .sorted { $0.cancelledAt > $1.cancelledAt }
    }

    public func load(id: String) -> CancelledRecording? {
        list().first { $0.id == id }
    }

    public func delete(id: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasPrefix(id + "_") || name == id + ".json" {
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
    }

    /// Supprime ce qui a été annulé avant `cutoff`.
    @discardableResult
    public func purge(cancelledBefore cutoff: Date) -> Int {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let expired = list().filter { $0.cancelledAt < cutoff }
        expired.forEach { delete(id: $0.id) }
        return expired.count
    }

    /// Transcrit (si besoin) un enregistrement annulé et le range dans la bibliothèque, comme
    /// s'il avait été terminé normalement. Il quitte alors les annulés.
    /// - Parameter save: faux pour une dictée quand l'historique est désactivé : le texte est
    ///   seulement rendu, rien n'est rangé.
    public func restore(
        _ recording: CancelledRecording, save: Bool = true, settings: PlumeSettings = .shared,
        engine: SpeechEngine = .shared
    ) async throws -> Transcript {
        let store = settings.store
        let urls = audioURLs(for: recording)
        guard let micURL = urls.first(where: { $0.lastPathComponent.hasSuffix("_mic.m4a") }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        // L'identifiant d'origine, sauf si une transcription l'a pris entre-temps.
        let id = store.load(id: recording.id) == nil ? recording.id : store.makeID(for: recording.createdAt)
        var transcript: Transcript
        if recording.mode == .meeting {
            try await engine.prepare(model: settings.model)
            var channels = [ChannelAudio(channel: .mic, samples: try AudioIO.loadSamples(micURL))]
            if let sys = urls.first(where: { $0.lastPathComponent.hasSuffix("_sys.m4a") }),
                let samples = try? AudioIO.loadSamples(sys)
            {
                channels.append(ChannelAudio(channel: .system, samples: samples))
            }
            let result = try await Pipeline.conversation(
                channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true)
            transcript = Transcript(
                id: id, createdAt: recording.createdAt, mode: .meeting, duration: recording.duration,
                engine: await engine.modelName, text: result.text, rawText: result.rawText,
                segments: result.segments, speakers: result.speakers, app: recording.app)
        } else {
            var text = recording.text ?? ""
            var raw = recording.rawText ?? text
            if recording.text == nil {
                try await engine.prepare(model: settings.model)
                let result = try await Pipeline.dictation(
                    samples: try AudioIO.loadSamples(micURL), engine: engine, options: DictationOptions(settings: settings))
                text = result.text
                raw = result.raw
            }
            transcript = Transcript(
                id: id, createdAt: recording.createdAt, mode: .dictation, duration: recording.duration,
                engine: await engine.modelName, text: text, rawText: raw, app: recording.app)
        }

        // Rien d'intelligible : l'enregistrement reste parmi les annulés, on peut toujours l'écouter.
        guard !transcript.text.isEmpty else { throw Failure.nothingHeard }

        if save {
            if settings.keepAudio {
                let directory = try store.ensureDirectory(forID: id)
                for url in urls {
                    let suffix = url.lastPathComponent.hasSuffix("_sys.m4a") ? "sys" : "mic"
                    let name = "\(id)_\(suffix).m4a"
                    if (try? fm.copyItem(at: url, to: directory.appendingPathComponent(name))) != nil {
                        transcript.audioFiles.append(name)
                    }
                }
            }
            try store.save(transcript)
        }
        delete(id: recording.id)
        return transcript
    }
}
