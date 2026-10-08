import Foundation

/// Keyboard shortcut: either a combination of modifiers alone (`keyCode == nil`,
/// for example ⌃⌥), or a key with modifiers (⌥Space).
public struct Shortcut: Codable, Sendable, Equatable {
    /// macOS virtual key code, or `nil` for a chord of modifiers alone.
    public var keyCode: Int?
    /// Modifier mask (bits of `ModifierMask`).
    public var modifiers: Int

    public init(keyCode: Int?, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isModifierOnly: Bool { keyCode == nil }
    /// Unassigned shortcut.
    public var isEmpty: Bool { keyCode == nil && modifiers == 0 }
    public static let none = Shortcut(keyCode: nil, modifiers: 0)
}

/// Modifier bits independent of AppKit, to stay usable outside macOS.
public enum ModifierMask {
    public static let control = 1 << 0
    public static let option = 1 << 1
    public static let shift = 1 << 2
    public static let command = 1 << 3
}

/// Persistent settings, shared between the app and the command line.
public final class PlumeSettings: @unchecked Sendable {
    public static let bundleID = "studio.brigode.plume"
    public static let shared = PlumeSettings()

    public let defaults: UserDefaults

    public convenience init() {
        // PLUME_DEFAULTS: a separate set of settings for test runs, without touching the real ones.
        let defaults: UserDefaults
        if let suite = ProcessInfo.processInfo.environment["PLUME_DEFAULTS"], !suite.isEmpty {
            defaults = UserDefaults(suiteName: Self.bundleID + "." + suite) ?? .standard
        } else if Bundle.main.bundleIdentifier == Self.bundleID {
            defaults = .standard
        } else {
            defaults = UserDefaults(suiteName: Self.bundleID) ?? .standard
        }
        self.init(defaults: defaults)
    }

    /// Settings on a given suite: tests pass a throwaway one.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
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
            Key.cancelledRetentionHours: 24 * 7,
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
            Key.readAloudLength: SummaryLength.automatic.rawValue,
            Key.readAloudLanguage: SummaryLanguage.sameAsText.rawValue,
            Key.readAloudVoice: "supertonic3-f1",
            Key.readAloudSpeed: ReadAloudSpeed.defaultValue,
            Key.readAloudShowText: false,
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
        static let cancelledRetentionHours = "cancelledRetentionHours"
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
        static let cancelShortcut = "cancelShortcut"
        static let restoreShortcut = "restoreShortcut"
        static let appearance = "appearance"
        static let language = "language"
        static let microphoneUID = "microphoneUID"
        static let dictationShortcut = "dictationShortcut"
        static let meetingShortcut = "meetingShortcut"
        static let onboarded = "onboarded"
        static let changelogSeen = "changelogSeen"
        static let readAloudEngine = "readAloudEngine"
        static let readAloudPendingDownload = "readAloudPendingDownload"
        static let readAloudKeepLoaded = "readAloudKeepLoaded"
        static let readAloudShortcut = "readAloudShortcut"
        static let summarizeAloudShortcut = "summarizeAloudShortcut"
        static let readAloudLength = "readAloudLength"
        static let readAloudLanguage = "readAloudLanguage"
        static let readAloudVoice = "readAloudVoice"
        static let readAloudSpeed = "readAloudSpeed"
        static let readAloudShowText = "readAloudShowText"
    }

    // MARK: Folders

    public static var defaultLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Plume", isDirectory: true)
    }

    /// Auxiliary settings (vocabulary, per-app rules, voiceprint):
    /// `~/Library/Application Support/Plume`, or the `PLUME_SUPPORT` folder for test runs.
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PLUME_SUPPORT"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Plume", isDirectory: true)
    }

    public var libraryURL: URL {
        get {
            // Stand-in library for test runs, without touching the real one.
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

    // MARK: Behavior

    public var model: EngineModel {
        get { EngineModel(rawValue: defaults.string(forKey: Key.model) ?? "") ?? .parakeetUltra }
        set { defaults.set(newValue.rawValue, forKey: Key.model) }
    }

    /// Folder of the custom model (`EngineModel.custom`), or `nil`.
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

    /// Light, deterministic cleanup of the dictated text (hesitations, stuttered words).
    public var cleanup: Bool {
        get { defaults.bool(forKey: Key.cleanup) }
        set { defaults.set(newValue, forKey: Key.cleanup) }
    }

    /// "New line" (« à la ligne »), "new paragraph", "delete that"… executed rather than written.
    public var voiceCommands: Bool {
        get { defaults.bool(forKey: Key.voiceCommands) }
        set { defaults.set(newValue, forKey: Key.voiceCommands) }
    }

    /// Space, capital and final period adapted to what surrounds the cursor.
    public var smartInsert: Bool {
        get { defaults.bool(forKey: Key.smartInsert) }
        set { defaults.set(newValue, forKey: Key.smartInsert) }
    }

    /// Sentences are typed into the field as the dictation goes, instead of being pasted at the end.
    public var streamingPaste: Bool {
        get { defaults.bool(forKey: Key.streamingPaste) }
        set { defaults.set(newValue, forKey: Key.streamingPaste) }
    }

    public var keepAudio: Bool {
        get { defaults.bool(forKey: Key.keepAudio) }
        set { defaults.set(newValue, forKey: Key.keepAudio) }
    }

    /// File dictations in the library. Otherwise the text is pasted then forgotten: no
    /// history, no audio, no backup file. Meetings, which have no other outlet
    /// than the history, are always filed.
    public var keepHistory: Bool {
        get { defaults.bool(forKey: Key.keepHistory) }
        set { defaults.set(newValue, forKey: Key.keepHistory) }
    }

    /// Number of days the audio is kept (0: always).
    public var audioRetentionDays: Int {
        get { defaults.integer(forKey: Key.audioRetentionDays) }
        set { defaults.set(newValue, forKey: Key.audioRetentionDays) }
    }

    /// Number of hours a cancelled recording stays recoverable
    /// (0: it is thrown away right away).
    public var cancelledRetentionHours: Int {
        get { defaults.integer(forKey: Key.cancelledRetentionHours) }
        set { defaults.set(newValue, forKey: Key.cancelledRetentionHours) }
    }

    /// Cancelled recordings that are still recoverable.
    public var cancelled: CancelledStore { CancelledStore(library: libraryURL) }

    /// Offer to record when a video-call app starts using the microphone.
    public var meetingDetection: Bool {
        get { defaults.bool(forKey: Key.meetingDetection) }
        set { defaults.set(newValue, forKey: Key.meetingDetection) }
    }

    /// Mute the system audio for the length of a dictation (music, video).
    public var muteWhileDictating: Bool {
        get { defaults.bool(forKey: Key.muteWhileDictating) }
        set { defaults.set(newValue, forKey: Key.muteWhileDictating) }
    }

    /// AI clean-up of each dictation by the local AI, unless a rule says otherwise for the app.
    public var polish: Bool {
        get { defaults.bool(forKey: Key.polish) }
        set { defaults.set(newValue, forKey: Key.polish) }
    }

    /// Instructions given to the AI for the clean-up ("use informal 'tu'", "no emojis"…).
    public var polishInstructions: String {
        get { defaults.string(forKey: Key.polishInstructions) ?? "" }
        set { defaults.set(newValue, forKey: Key.polishInstructions) }
    }

    /// Summarize each meeting with the local AI as soon as it is transcribed.
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

    /// Volume of the start and end sounds (0…1).
    public var soundVolume: Double {
        get { defaults.double(forKey: Key.soundVolume) }
        set { defaults.set(newValue, forKey: Key.soundVolume) }
    }

    /// Recording sound pack (identifier, see `SoundPack` in the app).
    public var soundPack: String {
        get { Self.normalizedSoundPack(defaults.string(forKey: Key.soundPack)) }
        set { defaults.set(newValue, forKey: Key.soundPack) }
    }

    /// Identifier of the chosen microphone. `nil`: the Mac's built-in microphone.
    public var microphoneUID: String? {
        get {
            let value = defaults.string(forKey: Key.microphoneUID)
            return value?.isEmpty == false ? value : nil
        }
        set { defaults.set(newValue ?? "", forKey: Key.microphoneUID) }
    }

    /// Interface language (English by default).
    public var language: Language {
        get { Language(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    /// Window appearance: `dark` (default), `light` or `system`.
    public var appearance: String {
        get { Self.normalizedAppearance(defaults.string(forKey: Key.appearance)) }
        set { defaults.set(newValue, forKey: Key.appearance) }
    }

    /// Reads a stored appearance, French values up to 1.0.1 included. No default is
    /// registered for `appearance`: it would end up in every settings export.
    public static func normalizedAppearance(_ raw: String?) -> String {
        switch raw {
        case "sombre": return "dark"
        case "clair": return "light"
        case "systeme": return "system"
        case "light", "system": return raw!
        default: return "dark"
        }
    }

    /// Reads a stored sound pack, French values up to 1.0.1 included. Unknown values
    /// are kept: the app falls back to the standard pack itself.
    public static func normalizedSoundPack(_ raw: String?) -> String {
        switch raw {
        case nil: return "pluck"
        case "bips": return "beeps"
        case "clics": return "clicks"
        case "melodie": return "melody"
        case "glisse": return "glide"
        case "bois": return "wood"
        default: return raw!
        }
    }

    /// Shows the dictation / meeting choice during the first seconds of a recording.
    public var modeSwitchAtStart: Bool {
        get { defaults.bool(forKey: Key.modeSwitchAtStart) }
        set { defaults.set(newValue, forKey: Key.modeSwitchAtStart) }
    }

    /// Fingerprint of the changelog the last time "What's new" was opened.
    public var changelogSeen: String {
        get { defaults.string(forKey: Key.changelogSeen) ?? "" }
        set { defaults.set(newValue, forKey: Key.changelogSeen) }
    }

    public var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    // MARK: Shortcuts

    /// ⌃⇧ by default, like Superwhisper: short press to start then stop,
    /// hold to speak while pressing.
    public static let defaultDictationShortcut = Shortcut(
        keyCode: nil, modifiers: ModifierMask.control | ModifierMask.shift)
    /// ⌃⇧⌘ by default. Meeting mode can also be started from the island.
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

    /// Shortcut that opens the Plume window (none by default).
    public var openShortcut: Shortcut {
        get { shortcut(forKey: Key.openShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.openShortcut) }
    }

    /// Shortcut that pastes the last dictation again where the cursor is (none by default).
    public var pasteLastShortcut: Shortcut {
        get { shortcut(forKey: Key.pasteLastShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.pasteLastShortcut) }
    }

    /// "Transform the selection" shortcut: you dictate an instruction, the local AI rewrites the
    /// selected text (none by default).
    public var transformShortcut: Shortcut {
        get { shortcut(forKey: Key.transformShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.transformShortcut) }
    }

    /// Esc by default. Changeable (⇧⎋, ⌃⎋…) for those who press Esc by reflex in other apps.
    public static let defaultCancelShortcut = Shortcut(keyCode: 53, modifiers: 0)

    /// Shortcut that cancels the current recording. It is only intercepted during a
    /// recording: the rest of the time, the key keeps its usual role.
    public var cancelShortcut: Shortcut {
        get { shortcut(forKey: Key.cancelShortcut) ?? Self.defaultCancelShortcut }
        set { setShortcut(newValue, forKey: Key.cancelShortcut) }
    }

    /// Shortcut that restores the last cancelled recording (none by default).
    public var restoreShortcut: Shortcut {
        get { shortcut(forKey: Key.restoreShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.restoreShortcut) }
    }

    // MARK: Read aloud

    /// Summary engine in use (catalog id); empty when none is chosen. Not in backups: the
    /// model files are not on a restored Mac.
    public var readAloudEngine: String {
        get { defaults.string(forKey: Key.readAloudEngine) ?? "" }
        set { defaults.set(newValue, forKey: Key.readAloudEngine) }
    }

    /// Download started from the app and not finished (`voice` or an engine id), resumed at launch.
    public var readAloudPendingDownload: String {
        get { defaults.string(forKey: Key.readAloudPendingDownload) ?? "" }
        set { defaults.set(newValue, forKey: Key.readAloudPendingDownload) }
    }

    /// `nil` until the user chooses; the default then depends on the Mac's memory
    /// (`KeepLoaded.defaultFor`). No registered default, so a backup carries only a real choice.
    public var readAloudKeepLoaded: KeepLoaded? {
        get { defaults.string(forKey: Key.readAloudKeepLoaded).flatMap(KeepLoaded.init(rawValue:)) }
        set {
            if let newValue { defaults.set(newValue.rawValue, forKey: Key.readAloudKeepLoaded) } else {
                defaults.removeObject(forKey: Key.readAloudKeepLoaded)
            }
        }
    }

    public var readAloudLength: SummaryLength {
        get { SummaryLength(rawValue: defaults.string(forKey: Key.readAloudLength) ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.readAloudLength) }
    }

    public var readAloudLanguage: SummaryLanguage {
        get { SummaryLanguage(rawValue: defaults.string(forKey: Key.readAloudLanguage) ?? "") ?? .sameAsText }
        set { defaults.set(newValue.rawValue, forKey: Key.readAloudLanguage) }
    }

    /// Voice id (`VoiceCatalog`); an unknown id falls back to the default voice there.
    public var readAloudVoice: String {
        get { defaults.string(forKey: Key.readAloudVoice) ?? "supertonic3-f1" }
        set { defaults.set(newValue, forKey: Key.readAloudVoice) }
    }

    public var readAloudSpeed: Double {
        get { ReadAloudSpeed.clamped(defaults.double(forKey: Key.readAloudSpeed)) }
        set { defaults.set(ReadAloudSpeed.clamped(newValue), forKey: Key.readAloudSpeed) }
    }

    public var readAloudShowText: Bool {
        get { defaults.bool(forKey: Key.readAloudShowText) }
        set { defaults.set(newValue, forKey: Key.readAloudShowText) }
    }

    /// "Read aloud" (word for word) shortcut, none by default.
    public var readAloudShortcut: Shortcut {
        get { shortcut(forKey: Key.readAloudShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.readAloudShortcut) }
    }

    /// "Summarize aloud" shortcut, none by default.
    public var summarizeAloudShortcut: Shortcut {
        get { shortcut(forKey: Key.summarizeAloudShortcut) ?? .none }
        set { setShortcut(newValue, forKey: Key.summarizeAloudShortcut) }
    }

    private func shortcut(forKey key: String) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private func setShortcut(_ shortcut: Shortcut, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
}
