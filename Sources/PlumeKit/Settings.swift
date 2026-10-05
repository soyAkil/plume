import Foundation

/// Raccourci clavier : soit une combinaison de modificateurs seuls (`keyCode == nil`,
/// par exemple ⌃⌥), soit une touche avec modificateurs (⌥Espace).
public struct Shortcut: Codable, Sendable, Equatable {
    /// Code de touche virtuel macOS, ou `nil` pour un accord de modificateurs seuls.
    public var keyCode: Int?
    /// Masque de modificateurs (bits de `ModifierMask`).
    public var modifiers: Int

    public init(keyCode: Int?, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isModifierOnly: Bool { keyCode == nil }
    /// Raccourci non attribué.
    public var isEmpty: Bool { keyCode == nil && modifiers == 0 }
    public static let none = Shortcut(keyCode: nil, modifiers: 0)
}

/// Bits de modificateurs indépendants d'AppKit, pour rester utilisables hors macOS.
public enum ModifierMask {
    public static let control = 1 << 0
    public static let option = 1 << 1
    public static let shift = 1 << 2
    public static let command = 1 << 3
}

/// Réglages persistants, partagés entre l'app et la ligne de commande.
public final class PlumeSettings: @unchecked Sendable {
    public static let bundleID = "studio.brigode.plume"
    public static let shared = PlumeSettings()

    public let defaults: UserDefaults

    public init() {
        // PLUME_DEFAULTS : un jeu de réglages à part pour les essais, sans toucher aux vrais.
        if let suite = ProcessInfo.processInfo.environment["PLUME_DEFAULTS"], !suite.isEmpty {
            defaults = UserDefaults(suiteName: Self.bundleID + "." + suite) ?? .standard
        } else if Bundle.main.bundleIdentifier == Self.bundleID {
            defaults = .standard
        } else {
            defaults = UserDefaults(suiteName: Self.bundleID) ?? .standard
        }
        defaults.register(defaults: [
            Key.liveTranscript: false,
            Key.pasteAfterDictation: true,
            Key.restoreClipboard: true,
            Key.cleanup: true,
            Key.voiceCommands: true,
            Key.smartInsert: true,
            Key.streamingPaste: false,
            Key.keepAudio: true,
            Key.keepHistory: true,
            Key.audioRetentionDays: 0,
            Key.sounds: true,
            Key.systemAudioInMeeting: true,
            Key.meetingDetection: true,
            Key.muteWhileDictating: false,
            Key.polish: false,
            Key.autoSummary: false,
            Key.model: EngineModel.parakeetUltra.rawValue,
            Key.language: Language.english.rawValue,
            Key.soundVolume: 0.7,
            Key.soundPack: "pluck",
            Key.modeSwitchAtStart: false,
        ])
    }

    enum Key {
        static let libraryPath = "libraryPath"
        static let model = "model"
        static let liveTranscript = "liveTranscript"
        static let pasteAfterDictation = "pasteAfterDictation"
        static let restoreClipboard = "restoreClipboard"
        static let cleanup = "cleanup"
        static let voiceCommands = "voiceCommands"
        static let smartInsert = "smartInsert"
        static let streamingPaste = "streamingPaste"
        static let keepAudio = "keepAudio"
        static let keepHistory = "keepHistory"
        static let audioRetentionDays = "audioRetentionDays"
        static let customModelPath = "customModelPath"
        static let sounds = "sounds"
        static let systemAudioInMeeting = "systemAudioInMeeting"
        static let meetingDetection = "meetingDetection"
        static let muteWhileDictating = "muteWhileDictating"
        static let polish = "polish"
        static let polishInstructions = "polishInstructions"
        static let autoSummary = "autoSummary"
        static let soundVolume = "soundVolume"
        static let soundPack = "soundPack"
        static let modeSwitchAtStart = "modeSwitchAtStart"
        static let openShortcut = "openShortcut"
        static let pasteLastShortcut = "pasteLastShortcut"
        static let transformShortcut = "transformShortcut"
        static let appearance = "appearance"
        static let language = "language"
        static let microphoneUID = "microphoneUID"
        static let dictationShortcut = "dictationShortcut"
        static let meetingShortcut = "meetingShortcut"
        static let onboarded = "onboarded"
    }

    // MARK: Dossiers

    public static var defaultLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Plume", isDirectory: true)
    }

    /// Réglages annexes (vocabulaire, règles par application, empreinte vocale) :
    /// `~/Library/Application Support/Plume`, ou le dossier `PLUME_SUPPORT` pour les essais.
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PLUME_SUPPORT"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Plume", isDirectory: true)
    }

    public var libraryURL: URL {
        get {
            // Bibliothèque de substitution pour les essais, sans toucher à la vraie.
            if let override = ProcessInfo.processInfo.environment["PLUME_LIBRARY"], !override.isEmpty {
                return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            }
            if let path = defaults.string(forKey: Key.libraryPath), !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
            return Self.defaultLibraryURL
        }
        set { defaults.set(newValue.path, forKey: Key.libraryPath) }
    }

    public var store: TranscriptStore { TranscriptStore(root: libraryURL) }

    // MARK: Comportement

    public var model: EngineModel {
        get { EngineModel(rawValue: defaults.string(forKey: Key.model) ?? "") ?? .parakeetUltra }
        set { defaults.set(newValue.rawValue, forKey: Key.model) }
    }

    /// Dossier du modèle personnalisé (`EngineModel.custom`), ou `nil`.
    public var customModelURL: URL? {
        get {
            guard let path = defaults.string(forKey: Key.customModelPath), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        set { defaults.set(newValue?.path ?? "", forKey: Key.customModelPath) }
    }

    public var liveTranscript: Bool {
        get { defaults.bool(forKey: Key.liveTranscript) }
        set { defaults.set(newValue, forKey: Key.liveTranscript) }
    }

    public var pasteAfterDictation: Bool {
        get { defaults.bool(forKey: Key.pasteAfterDictation) }
        set { defaults.set(newValue, forKey: Key.pasteAfterDictation) }
    }

    public var restoreClipboard: Bool {
        get { defaults.bool(forKey: Key.restoreClipboard) }
        set { defaults.set(newValue, forKey: Key.restoreClipboard) }
    }

    /// Nettoyage léger et déterministe du texte dicté (hésitations, mots bégayés).
    public var cleanup: Bool {
        get { defaults.bool(forKey: Key.cleanup) }
        set { defaults.set(newValue, forKey: Key.cleanup) }
    }

    /// « À la ligne », « nouveau paragraphe », « efface ça »… exécutés plutôt qu'écrits.
    public var voiceCommands: Bool {
        get { defaults.bool(forKey: Key.voiceCommands) }
        set { defaults.set(newValue, forKey: Key.voiceCommands) }
    }

    /// Espace, majuscule et point final adaptés à ce qui entoure le curseur.
    public var smartInsert: Bool {
        get { defaults.bool(forKey: Key.smartInsert) }
        set { defaults.set(newValue, forKey: Key.smartInsert) }
    }

    /// Les phrases se tapent dans le champ au fil de la dictée, au lieu d'être collées à la fin.
    public var streamingPaste: Bool {
        get { defaults.bool(forKey: Key.streamingPaste) }
        set { defaults.set(newValue, forKey: Key.streamingPaste) }
    }

    public var keepAudio: Bool {
        get { defaults.bool(forKey: Key.keepAudio) }
        set { defaults.set(newValue, forKey: Key.keepAudio) }
    }

    /// Ranger les dictées dans la bibliothèque. Sinon, le texte est collé puis oublié : pas
    /// d'historique, pas d'audio, pas de fichier de secours. Les réunions, qui n'ont pas
    /// d'autre débouché que l'historique, y sont toujours rangées.
    public var keepHistory: Bool {
        get { defaults.bool(forKey: Key.keepHistory) }
        set { defaults.set(newValue, forKey: Key.keepHistory) }
    }

    /// Nombre de jours pendant lesquels l'audio est gardé (0 : toujours).
    public var audioRetentionDays: Int {
        get { defaults.integer(forKey: Key.audioRetentionDays) }
        set { defaults.set(newValue, forKey: Key.audioRetentionDays) }
    }

    /// Proposer d'enregistrer quand une app de visio se met à utiliser le micro.
    public var meetingDetection: Bool {
        get { defaults.bool(forKey: Key.meetingDetection) }
        set { defaults.set(newValue, forKey: Key.meetingDetection) }
    }

    /// Couper le son de l'ordinateur le temps d'une dictée (musique, vidéo).
    public var muteWhileDictating: Bool {
        get { defaults.bool(forKey: Key.muteWhileDictating) }
        set { defaults.set(newValue, forKey: Key.muteWhileDictating) }
    }

    /// Mise au propre de chaque dictée par l'IA locale, sauf règle contraire pour l'app.
    public var polish: Bool {
        get { defaults.bool(forKey: Key.polish) }
        set { defaults.set(newValue, forKey: Key.polish) }
    }

    /// Consignes données à l'IA pour la mise au propre (« tutoie », « pas d'émojis »…).
    public var polishInstructions: String {
        get { defaults.string(forKey: Key.polishInstructions) ?? "" }
        set { defaults.set(newValue, forKey: Key.polishInstructions) }
    }

    /// Résumer chaque réunion par l'IA locale dès qu'elle est transcrite.
    public var autoSummary: Bool {
        get { defaults.bool(forKey: Key.autoSummary) }
        set { defaults.set(newValue, forKey: Key.autoSummary) }
    }

    public var sounds: Bool {
        get { defaults.bool(forKey: Key.sounds) }
        set { defaults.set(newValue, forKey: Key.sounds) }
    }

    public var systemAudioInMeeting: Bool {
        get { defaults.bool(forKey: Key.systemAudioInMeeting) }
        set { defaults.set(newValue, forKey: Key.systemAudioInMeeting) }
    }

    /// Volume des sons de début et de fin (0…1).
    public var soundVolume: Double {
        get { defaults.double(forKey: Key.soundVolume) }
        set { defaults.set(newValue, forKey: Key.soundVolume) }
    }

    /// Pack de sons d'enregistrement (identifiant, voir `SoundPack` dans l'app).
    public var soundPack: String {
        get { defaults.string(forKey: Key.soundPack) ?? "pluck" }
        set { defaults.set(newValue, forKey: Key.soundPack) }
    }

    /// Identifiant du micro choisi. `nil` : le micro intégré du Mac.
    public var microphoneUID: String? {
        get {
            let value = defaults.string(forKey: Key.microphoneUID)
            return value?.isEmpty == false ? value : nil
        }
        set { defaults.set(newValue ?? "", forKey: Key.microphoneUID) }
    }

    /// Langue de l'interface (anglais par défaut).
    public var language: Language {
        get { Language(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    /// Apparence de la fenêtre : `sombre` (par défaut), `clair` ou `systeme`.
    public var appearance: String {
        get { defaults.string(forKey: Key.appearance) ?? "sombre" }
        set { defaults.set(newValue, forKey: Key.appearance) }
    }

    /// Affiche le choix dictée / réunion pendant les premières secondes d'un enregistrement.
    public var modeSwitchAtStart: Bool {
        get { defaults.bool(forKey: Key.modeSwitchAtStart) }
        set { defaults.set(newValue, forKey: Key.modeSwitchAtStart) }
    }

    public var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    // MARK: Raccourcis

    /// ⌃⇧ par défaut, comme Superwhisper : appui bref pour démarrer puis arrêter,
    /// maintien pour parler tant qu'on appuie.
    public static let defaultDictationShortcut = Shortcut(
        keyCode: nil, modifiers: ModifierMask.control | ModifierMask.shift)
    /// ⌃⇧⌘ par défaut. Le mode réunion s'active aussi depuis la pastille.
    public static let defaultMeetingShortcut = Shortcut(
        keyCode: nil, modifiers: ModifierMask.control | ModifierMask.shift | ModifierMask.command)

    public var dictationShortcut: Shortcut {
        get { shortcut(forKey: Key.dictationShortcut) ?? Self.defaultDictationShortcut }
        set { setShortcut(newValue, forKey: Key.dictationShortcut) }
    }

    public var meetingShortcut: Shortcut {
        get { shortcut(forKey: Key.meetingShortcut) ?? Self.defaultMeetingShortcut }
        set { setShortcut(newValue, forKey: Key.meetingShortcut) }
    }

    /// Raccourci qui ouvre la fenêtre de Plume (aucun par défaut).
    public var openShortcut: Shortcut {
        get { shortcut(forKey: Key.openShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.openShortcut) }
    }

    /// Raccourci qui recolle la dernière dictée là où est le curseur (aucun par défaut).
    public var pasteLastShortcut: Shortcut {
        get { shortcut(forKey: Key.pasteLastShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.pasteLastShortcut) }
    }

    /// Raccourci « transformer la sélection » : on dicte une consigne, l'IA locale réécrit le
    /// texte sélectionné (aucun par défaut).
    public var transformShortcut: Shortcut {
        get { shortcut(forKey: Key.transformShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.transformShortcut) }
    }

    private func shortcut(forKey key: String) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private func setShortcut(_ shortcut: Shortcut, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
}
