import Foundation
@testable import PlumeKit

/// The invented data of the `Tests/Fixtures/` samples: the generator writes them, the
/// tests check that the files contain nothing else. Never any real data here.
/// Add, do not modify: the samples already generated depend on them.
enum FixtureSamples {
    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// A dictation with every field filled in.
    static let dictation = Transcript(
        id: "2026-10-02_09-15-00", createdAt: date("2026-10-02T07:15:00Z"), mode: .dictation, device: "mac",
        duration: 4.2, engine: "parakeet-ultra", text: "Le rapport trimestriel est prêt, je te l'envoie ce soir.",
        rawText: "euh le rapport trimestriel est prêt je te l'envoie ce soir",
        audioFiles: ["2026-10-02_09-15-00_mic.m4a"], app: "Notes", title: "Rapport trimestriel",
        summary: "Rapport prêt, envoi ce soir.")

    /// A meeting: both channels, speakers, a title and a summary.
    static let meeting = Transcript(
        id: "2026-10-02_14-31-05", createdAt: date("2026-10-02T12:31:05Z"), mode: .meeting, device: "mac",
        duration: 1834.5, engine: "parakeet-ultra",
        text: "**Moi** : On commence par le budget.\n\n**Inès** : D'accord, je partage l'écran.",
        rawText: "on commence par le budget d'accord je partage l'écran",
        segments: [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 3.25, text: "On commence par le budget."),
            Segment(id: 1, speaker: "Inès", channel: .system, start: 3.5, end: 6, text: "D'accord, je partage l'écran."),
        ],
        speakers: ["Moi", "Inès"], audioFiles: ["2026-10-02_14-31-05_mic.m4a", "2026-10-02_14-31-05_sys.m4a"],
        app: "Zoom", title: "Point budget", summary: "## Points clés\n- Budget validé.")

    /// An import reduced to the required fields, like a file from before `app`, `title` and `summary`.
    static let imported = Transcript(
        id: "2026-10-03_08-00-00", createdAt: date("2026-10-03T06:00:00Z"), mode: .imported, device: "mac",
        duration: 62, engine: "parakeet-v3", text: "Message vocal : rappelle-moi demain.",
        rawText: "message vocal rappelle-moi demain")

    static let transcripts = [dictation, meeting, imported]

    static let cancelled = CancelledRecording(
        id: "2026-10-03_10-00-00", createdAt: date("2026-10-03T08:00:00Z"), cancelledAt: date("2026-10-03T08:01:30Z"),
        mode: .dictation, duration: 12.5, app: "Mail", text: "Petite précision sur l'ordre du jour.",
        rawText: "petite précision sur l'ordre du jour", audioFiles: ["2026-10-03_10-00-00_mic.m4a"])

    static let replacements = [
        Replacement(id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000001")!, original: "sitié", with: "CTA"),
        Replacement(id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000002")!, original: "ma signature", with: "Paul\nÉquipe Plume"),
    ]

    /// One rule per style, including the one for all other apps.
    static let rules = [
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000003")!, bundleID: "com.apple.mail", name: "Mail",
            style: .standard, polish: true, instructions: "Ton cordial."),
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000004")!, bundleID: "com.tinyspeck.slackmacgap", name: "Slack",
            style: .message, pressReturn: true),
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000005")!, bundleID: "*", name: "Toutes les autres",
            style: .casual, typeText: true),
    ]

    static let voiceprint = Voiceprint(embedding: [0.125, -0.5, 0.25, 0.75], samples: 3)

    /// A backup with every key the app can save (`SettingsBackup.*Keys`).
    static let backup = SettingsBackup.File(
        date: date("2026-10-03T09:00:00Z"),
        shortcuts: [
            PlumeSettings.Key.dictationShortcut: Shortcut(keyCode: 49, modifiers: ModifierMask.option),
            PlumeSettings.Key.meetingShortcut: Shortcut(keyCode: nil, modifiers: ModifierMask.control | ModifierMask.shift),
            PlumeSettings.Key.openShortcut: Shortcut(keyCode: 35, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.pasteLastShortcut: Shortcut(keyCode: 9, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.transformShortcut: Shortcut(keyCode: 17, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.cancelShortcut: Shortcut(keyCode: 53, modifiers: 0),
            PlumeSettings.Key.restoreShortcut: Shortcut(keyCode: 15, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.readAloudShortcut: Shortcut(keyCode: 15, modifiers: ModifierMask.control | ModifierMask.shift),
            PlumeSettings.Key.summarizeAloudShortcut: Shortcut(keyCode: 1, modifiers: ModifierMask.control | ModifierMask.shift),
        ],
        booleans: Dictionary(uniqueKeysWithValues: SettingsBackup.booleanKeys.map { ($0, $0 != PlumeSettings.Key.keepHistory) }),
        numbers: [
            PlumeSettings.Key.soundVolume: 0.5, PlumeSettings.Key.audioRetentionDays: 30,
            PlumeSettings.Key.cancelledRetentionHours: 48, PlumeSettings.Key.readAloudSpeed: 1.25,
        ],
        strings: [
            PlumeSettings.Key.model: "parakeet-ultra", PlumeSettings.Key.soundPack: "pluck",
            PlumeSettings.Key.appearance: "dark", PlumeSettings.Key.polishInstructions: "Phrases courtes.",
            PlumeSettings.Key.language: "fr",
            PlumeSettings.Key.readAloudKeepLoaded: "always", PlumeSettings.Key.readAloudLength: "detailed",
            PlumeSettings.Key.readAloudLanguage: "fr", PlumeSettings.Key.readAloudVoice: "supertonic3-m2",
        ],
        replacements: replacements, rules: rules)

    /// Writes the samples into `folder` with the app's code, through explicit paths
    /// only (never the settings, the support folder or the home folder), and keeps
    /// only the JSON files the app reads back: Markdown, index, audio and the guide
    /// regenerate.
    static func write(to folder: URL) throws {
        // The settings backup, like `export`, writes into a folder that exists.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = folder.appendingPathComponent("library", isDirectory: true)
        let store = TranscriptStore(root: library)
        for transcript in transcripts { try store.save(transcript) }
        try CancelledStore(library: library).keep(cancelled, mic: [Float](repeating: 0, count: 16_000))

        let support = folder.appendingPathComponent("support", isDirectory: true)
        try ReplacementStore.write(replacements, to: support.appendingPathComponent(Fixtures.SupportFile.replacements.rawValue))
        try AppRuleStore.write(rules, to: support.appendingPathComponent("applications.json"))
        try VoiceprintStore.write(voiceprint, to: support.appendingPathComponent(Fixtures.SupportFile.voiceprint.rawValue))
        try SettingsBackup.write(backup, to: folder.appendingPathComponent(Fixtures.settingsFile))

        let fm = FileManager.default
        let everything = (fm.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for url in everything where !url.hasDirectoryPath && url.pathExtension != "json" {
            try fm.removeItem(at: url)
        }
    }

    /// Every value the samples contain, as the app encodes them (texts, dates,
    /// identifiers, numbers, voiceprint included), each as JSON text.
    static var allLeaves: Set<String> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var leaves = Set<String>()
        func add<T: Encodable>(_ value: T) {
            guard let data = try? encoder.encode(value),
                let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { return }
            leaves.formUnion(Fixtures.leaves(in: object))
        }
        add(transcripts)
        add(cancelled)
        add(replacements)
        add(rules)
        add(voiceprint)
        add(backup)
        return leaves
    }
}

/// `Tests/Fixtures/`: one folder per version that changed a format, with the JSON files that
/// version wrote and that the app must still be able to read back.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// A version folder name: `1.0.1`, `1.10`.
    static func isVersion(_ name: String) -> Bool {
        name.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
    }

    /// The version folders, oldest to newest (numeric order: 1.9 before 1.10). Any
    /// other file or folder is ignored.
    static var versions: [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return isVersion(name)
                && fm.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        .map { root.appendingPathComponent($0, isDirectory: true) }
    }

    /// Support files renamed in 1.0.2: each version folder holds the name its version wrote.
    enum SupportFile: String {
        case replacements = "replacements.json"
        case voiceprint = "voiceprint.json"

        var legacyName: String {
            switch self {
            case .replacements: "remplacements.json"
            case .voiceprint: "empreinte-vocale.json"
            }
        }
    }

    static func supportFile(_ kind: SupportFile, version: URL) -> String {
        wroteFrenchNames(version) ? kind.legacyName : kind.rawValue
    }

    /// The settings backup the generator writes; up to 1.0.1 it was `reglages.json`.
    static let settingsFile = "settings.json"

    static func settingsFile(version: URL) -> String {
        wroteFrenchNames(version) ? "reglages.json" : settingsFile
    }

    /// The cancelled recordings' folder in a version's library.
    static func cancelledFolder(version: URL) -> String {
        wroteFrenchNames(version) ? ".annules" : ".cancelled"
    }

    /// Up to 1.0.1, these files and folders had French names.
    private static func wroteFrenchNames(_ version: URL) -> Bool {
        version.lastPathComponent.compare("1.0.1", options: .numeric) != .orderedDescending
    }

    /// All JSON files in a folder, hidden folders included (`.cancelled`).
    static func jsonFiles(in folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL]) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    static func object(at url: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
    }

    /// The values of a JSON document (not the key names), each as JSON text: `"Inès"`,
    /// `0.5`, `true`. The text tells `true` from `1`, which `NSNumber` confuses.
    static func leaves(in value: Any) -> Set<String> {
        switch value {
        case let array as [Any]:
            return array.reduce(into: Set<String>()) { $0.formUnion(leaves(in: $1)) }
        case let object as [String: Any]:
            return object.values.reduce(into: Set<String>()) { $0.formUnion(leaves(in: $1)) }
        default:
            return [json(value)]
        }
    }

    /// The values of a JSON document with their path (`.segments[1].text`), like `missing`.
    static func leaves(in value: Any, at path: String) -> [(path: String, value: String)] {
        switch value {
        case let array as [Any]:
            return array.enumerated().flatMap { index, element in leaves(in: element, at: "\(path)[\(index)]") }
        case let object as [String: Any]:
            return object.keys.sorted().flatMap { key in leaves(in: object[key]!, at: path + "." + key) }
        default:
            return [(path, json(value))]
        }
    }

    /// A plain value as JSON text.
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
    }

    /// What `original` contains and `copy` no longer has, or no longer identical: the paths
    /// (`.segments[1].speaker`). Empty when nothing is lost.
    static func missing(_ original: Any, in copy: Any, at path: String = "") -> [String] {
        switch (original, copy) {
        case let (original as [String: Any], copy as [String: Any]):
            return original.keys.sorted().flatMap { key in
                copy[key].map { missing(original[key]!, in: $0, at: path + "." + key) } ?? [path + "." + key]
            }
        case let (original as [Any], copy as [Any]):
            guard original.count == copy.count else { return [path] }
            return zip(original, copy).enumerated().flatMap { index, pair in
                missing(pair.0, in: pair.1, at: "\(path)[\(index)]")
            }
        default:
            return json(original) == json(copy) ? [] : [path]
        }
    }
}
