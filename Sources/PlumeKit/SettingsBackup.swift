import Foundation

/// Sauvegarde et restauration de tous les réglages dans un seul fichier JSON : raccourcis,
/// options, vocabulaire, règles par application. Pour retrouver son Plume sur un autre Mac,
/// ou partager sa configuration. Le dossier de bibliothèque et le micro, propres à chaque
/// machine, n'en font pas partie.
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
        PlumeSettings.Key.modeSwitchAtStart,
    ]
    static let numberKeys = [PlumeSettings.Key.soundVolume, PlumeSettings.Key.audioRetentionDays]
    static let stringKeys = [
        PlumeSettings.Key.model, PlumeSettings.Key.soundPack, PlumeSettings.Key.appearance, PlumeSettings.Key.polishInstructions,
        PlumeSettings.Key.language,
    ]
    static let shortcutKeys = [
        PlumeSettings.Key.dictationShortcut, PlumeSettings.Key.meetingShortcut, PlumeSettings.Key.openShortcut,
        PlumeSettings.Key.pasteLastShortcut, PlumeSettings.Key.transformShortcut,
    ]

    public static func snapshot(settings: PlumeSettings = .shared) -> File {
        let defaults = settings.defaults
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
            strings: Dictionary(uniqueKeysWithValues: stringKeys.compactMap { key in defaults.string(forKey: key).map { (key, $0) } }),
            replacements: ReplacementStore.load(),
            rules: AppRuleStore.load())
    }

    public static func export(to url: URL, settings: PlumeSettings = .shared) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot(settings: settings)).write(to: url, options: .atomic)
    }

    public static func restore(_ file: File, settings: PlumeSettings = .shared) {
        let defaults = settings.defaults
        // Seules les clés connues sont relues : un fichier bricolé ne peut rien écrire d'autre.
        for (key, value) in file.booleans where booleanKeys.contains(key) { defaults.set(value, forKey: key) }
        for (key, value) in file.numbers where numberKeys.contains(key) {
            if key == PlumeSettings.Key.audioRetentionDays { defaults.set(Int(value), forKey: key) } else { defaults.set(value, forKey: key) }
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        restore(try decoder.decode(File.self, from: Data(contentsOf: url)), settings: settings)
    }
}
