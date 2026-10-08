import Foundation

/// Backup and restore of all the settings in a single JSON file: shortcuts,
/// options, vocabulary, per-app rules. To get your Plume back on another Mac,
/// or share your configuration. The library folder and the microphone, specific to each
/// machine, are not part of it.
public enum SettingsBackup {
    public struct File: Codable, Sendable, Equatable {
        public var version = 1
        public var date: Date
        public var shortcuts: [String: Shortcut]
        public var booleans: [String: Bool]
        public var numbers: [String: Double]
        public var strings: [String: String]
        public var replacements: [Replacement]
        public var rules: [AppRule]
    }

    static let booleanKeys = [
        PlumeSettings.Key.liveTranscript, PlumeSettings.Key.pasteAfterDictation, PlumeSettings.Key.restoreClipboard,
        PlumeSettings.Key.cleanup, PlumeSettings.Key.voiceCommands, PlumeSettings.Key.smartInsert, PlumeSettings.Key.keepAudio,
        PlumeSettings.Key.keepHistory, PlumeSettings.Key.streamingPaste,
        PlumeSettings.Key.sounds, PlumeSettings.Key.systemAudioInMeeting, PlumeSettings.Key.meetingDetection,
        PlumeSettings.Key.muteWhileDictating, PlumeSettings.Key.polish, PlumeSettings.Key.autoSummary,
        PlumeSettings.Key.modeSwitchAtStart, PlumeSettings.Key.readAloudShowText,
    ]
    static let numberKeys = [
        PlumeSettings.Key.soundVolume, PlumeSettings.Key.audioRetentionDays, PlumeSettings.Key.cancelledRetentionHours,
        PlumeSettings.Key.readAloudSpeed,
    ]
    static let stringKeys = [
        PlumeSettings.Key.model, PlumeSettings.Key.soundPack, PlumeSettings.Key.appearance, PlumeSettings.Key.polishInstructions,
        PlumeSettings.Key.language, PlumeSettings.Key.readAloudKeepLoaded, PlumeSettings.Key.readAloudLength,
        PlumeSettings.Key.readAloudLanguage, PlumeSettings.Key.readAloudVoice,
    ]
    static let shortcutKeys = [
        PlumeSettings.Key.dictationShortcut, PlumeSettings.Key.meetingShortcut, PlumeSettings.Key.openShortcut,
        PlumeSettings.Key.pasteLastShortcut, PlumeSettings.Key.transformShortcut, PlumeSettings.Key.cancelShortcut,
        PlumeSettings.Key.restoreShortcut, PlumeSettings.Key.readAloudShortcut, PlumeSettings.Key.summarizeAloudShortcut,
    ]

    public static func snapshot(settings: PlumeSettings = .shared) -> File {
        snapshot(defaults: settings.defaults, replacements: ReplacementStore.load(), rules: AppRuleStore.load())
    }

    /// The stores are passed in so tests never read the real ones. French values stored
    /// by older versions are exported as English; an unset value stays absent.
    static func snapshot(defaults: UserDefaults, replacements: [Replacement], rules: [AppRule]) -> File {
        var shortcuts: [String: Shortcut] = [:]
        for key in shortcutKeys {
            if let data = defaults.data(forKey: key), let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                shortcuts[key] = shortcut
            }
        }
        return File(
            date: Date(),
            shortcuts: shortcuts,
            booleans: Dictionary(uniqueKeysWithValues: booleanKeys.map { ($0, defaults.bool(forKey: $0)) }),
            numbers: Dictionary(uniqueKeysWithValues: numberKeys.map { ($0, defaults.double(forKey: $0)) }),
            strings: Dictionary(
                uniqueKeysWithValues: stringKeys.compactMap { key in
                    defaults.string(forKey: key).map { raw in
                        switch key {
                        case PlumeSettings.Key.appearance: return (key, PlumeSettings.normalizedAppearance(raw))
                        case PlumeSettings.Key.soundPack: return (key, PlumeSettings.normalizedSoundPack(raw))
                        default: return (key, raw)
                        }
                    }
                }),
            replacements: replacements,
            rules: rules)
    }

    public static func export(to url: URL, settings: PlumeSettings = .shared) throws {
        try write(snapshot(settings: settings), to: url)
    }

    public static func write(_ file: File, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    public static func restore(_ file: File, settings: PlumeSettings = .shared) {
        let defaults = settings.defaults
        // Only known keys are read back: a tampered file can't write anything else.
        for (key, value) in file.booleans where booleanKeys.contains(key) { defaults.set(value, forKey: key) }
        for (key, value) in file.numbers where numberKeys.contains(key) {
            let integer = key == PlumeSettings.Key.audioRetentionDays || key == PlumeSettings.Key.cancelledRetentionHours
            if integer { defaults.set(Int(value), forKey: key) } else { defaults.set(value, forKey: key) }
        }
        for (key, value) in file.strings where stringKeys.contains(key) { defaults.set(value, forKey: key) }
        for key in shortcutKeys {
            if let shortcut = file.shortcuts[key] {
                defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        ReplacementStore.save(file.replacements)
        AppRuleStore.save(file.rules)
    }

    public static func `import`(from url: URL, settings: PlumeSettings = .shared) throws {
        restore(try read(from: url), settings: settings)
    }

    public static func read(from url: URL) throws -> File {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(File.self, from: Data(contentsOf: url))
    }
}
