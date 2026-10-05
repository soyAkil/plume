import Foundation

/// Remplacement appliqué au texte transcrit : « sitié » → « CTA », « super whisper » → « Superwhisper ».
public struct Replacement: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var original: String
    public var with: String

    public init(id: UUID = UUID(), original: String, with: String) {
        self.id = id
        self.original = original
        self.with = with
    }
}

public enum ReplacementStore {
    public static var url: URL { PlumeSettings.supportDirectory.appendingPathComponent("remplacements.json") }

    public static func load() -> [Replacement] {
        if let data = try? Data(contentsOf: url),
            let items = try? JSONDecoder().decode([Replacement].self, from: data)
        {
            return items
        }
        // Premier lancement : on reprend les remplacements déjà réglés dans Superwhisper.
        let imported = importFromSuperwhisper()
        if !imported.isEmpty { save(imported) }
        return imported
    }

    public static func save(_ items: [Replacement]) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? encoder.encode(items).write(to: url, options: .atomic)
    }

    static func importFromSuperwhisper() -> [Replacement] {
        struct Settings: Decodable {
            struct Item: Decodable {
                var original: String
                var with: String
            }
            var replacements: [Item]?
        }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/superwhisper/settings/settings.json")
        guard let data = try? Data(contentsOf: file),
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return [] }
        return (settings.replacements ?? []).map { Replacement(original: $0.original, with: $0.with) }
    }

    /// Applique les remplacements, sans tenir compte de la casse, sur des mots entiers.
    public static func apply(_ replacements: [Replacement], to text: String) -> String {
        var result = text
        // Les expressions les plus longues d'abord, pour qu'une courte n'en entame pas une longue.
        for item in replacements.sorted(by: { $0.original.count > $1.original.count }) {
            let original = item.original.trimmingCharacters(in: .whitespaces)
            guard !original.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: original) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: item.with))
        }
        return result
    }
}
