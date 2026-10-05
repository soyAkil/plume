import Foundation

public enum RecordingMode: String, Codable, Sendable, CaseIterable {
    /// Dictée : micro seul, texte collé dans le champ actif.
    case dictation
    /// Réunion : micro + audio système, séparation des interlocuteurs.
    case meeting
    /// Fichier audio importé (glisser-déposer, menu, CLI).
    case imported

    public var label: String {
        switch self {
        case .dictation: return tr("Dictée")
        case .meeting: return tr("Réunion")
        case .imported: return tr("Import")
        }
    }

    public var slug: String {
        switch self {
        case .dictation: return "dictee"
        case .meeting: return "reunion"
        case .imported: return "import"
        }
    }

    public init?(slug: String) {
        switch slug.lowercased() {
        case "dictee", "dictée", "dictation": self = .dictation
        case "reunion", "réunion", "meeting": self = .meeting
        case "import", "imported": self = .imported
        default: return nil
        }
    }
}

public enum AudioChannel: String, Codable, Sendable {
    case mic
    case system
}

public struct Word: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Un tour de parole : un interlocuteur, un intervalle, un texte.
public struct Segment: Codable, Sendable, Identifiable, Equatable {
    public var id: Int
    public var speaker: String
    public var channel: AudioChannel
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: Int, speaker: String, channel: AudioChannel, start: Double, end: Double, text: String) {
        self.id = id
        self.speaker = speaker
        self.channel = channel
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct Transcript: Codable, Sendable, Identifiable, Equatable {
    /// Identifiant triable : `2026-10-02_14-31-05`.
    public var id: String
    public var createdAt: Date
    public var mode: RecordingMode
    /// `mac`, `iphone`…
    public var device: String
    public var duration: Double
    public var engine: String
    /// Texte final (dictée nettoyée, ou dialogue rendu pour une réunion).
    public var text: String
    /// Sortie brute du modèle, avant nettoyage.
    public var rawText: String
    public var segments: [Segment]
    public var speakers: [String]
    /// Noms de fichiers audio, relatifs au dossier du transcript.
    public var audioFiles: [String]
    /// Application au premier plan au moment de la dictée.
    public var app: String?
    /// Titre donné par l'utilisateur ou proposé par l'IA locale (sinon, la date fait office de titre).
    public var title: String?
    /// Résumé en Markdown (points clés, décisions, actions), écrit par l'IA locale.
    public var summary: String?

    public init(
        id: String, createdAt: Date, mode: RecordingMode, device: String = "mac", duration: Double,
        engine: String, text: String, rawText: String, segments: [Segment] = [], speakers: [String] = [],
        audioFiles: [String] = [], app: String? = nil, title: String? = nil, summary: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.device = device
        self.duration = duration
        self.engine = engine
        self.text = text
        self.rawText = rawText
        self.segments = segments
        self.speakers = speakers
        self.audioFiles = audioFiles
        self.app = app
        self.title = title
        self.summary = summary
    }

    /// Première ligne utile, pour les listes.
    public var preview: String {
        let source = segments.first?.text ?? text
        let flat = source.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
    }
}

public enum Format {
    /// `1:05` ou `1:02:03`.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// `45 s`, `12 min 05 s`, `1 h 02 min`.
    public static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        if total < 3600 { return String(format: "%d min %02d s", total / 60, total % 60) }
        return String(format: "%d h %02d min", total / 3600, (total % 3600) / 60)
    }
}
