import Foundation

/// Allure du texte dicté, selon l'endroit où il est collé : un mail n'a pas la même tenue
/// qu'un message sur Slack ou qu'une commande dans le terminal.
public enum DictationStyle: String, Codable, Sendable, CaseIterable {
    /// Tel que le modèle l'écrit : majuscules et ponctuation complètes.
    case standard
    /// Message instantané : pas de point final.
    case message
    /// Décontracté : pas de majuscule en début de phrase, pas de point final.
    case casual

    public var label: String {
        switch self {
        case .standard: return tr("Standard")
        case .message: return tr("Message")
        case .casual: return tr("Décontracté")
        }
    }

    public var detail: String {
        switch self {
        case .standard: return tr("Majuscules et ponctuation complètes.")
        case .message: return tr("Sans point final, comme on écrit sur Slack ou Messages.")
        case .casual: return tr("Sans majuscule en début de phrase ni point final.")
        }
    }
}

public enum TextStyle {
    /// - Parameter final: faux pour un morceau écrit au fil de la dictée, dont le point n'est pas
    ///   le dernier : il reste.
    public static func apply(_ style: DictationStyle, to text: String, final: Bool = true) -> String {
        switch style {
        case .standard:
            return text
        case .message:
            return final ? droppingFinalPeriod(text) : text
        case .casual:
            return final ? droppingFinalPeriod(lowercasingSentences(text)) : lowercasingSentences(text)
        }
    }

    /// Retire le point final (pas les points de suspension, ni ? ni !).
    static func droppingFinalPeriod(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "\n" { result.removeLast() }
        guard result.hasSuffix("."), !result.hasSuffix("..") else { return text }
        result.removeLast()
        // Le saut de ligne final éventuel est conservé.
        return result + text.suffix(while: { $0 == "\n" })
    }

    /// Une minuscule au début de chaque phrase, sauf pour un sigle (« URL ») et le « I » anglais.
    static func lowercasingSentences(_ text: String) -> String {
        var result = ""
        var atSentenceStart = true
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if atSentenceStart, character.isLetter {
                let wordEnd = text[index...].firstIndex(where: { !$0.isLetter && $0 != "'" && $0 != "’" }) ?? text.endIndex
                let word = String(text[index..<wordEnd])
                let acronym = word.count > 1 && word.allSatisfy { $0.isUppercase }
                let english = word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’")
                result += acronym || english ? word : word.prefix(1).lowercased() + word.dropFirst()
                index = wordEnd
                atSentenceStart = false
                continue
            }
            if ".!?…\n".contains(character) {
                atSentenceStart = true
            } else if !character.isWhitespace, !"«\"(".contains(character) {
                atSentenceStart = false
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }
}

extension StringProtocol {
    /// Les derniers caractères qui vérifient la condition, dans l'ordre.
    fileprivate func suffix(while predicate: (Character) -> Bool) -> String {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return String(self[end...])
    }
}

/// Réglages de dictée propres à une application : style du texte, validation avec Entrée,
/// mise au propre par l'IA, méthode d'insertion.
public struct AppRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Identifiant de l'app (`com.tinyspeck.slackmacgap`), ou `*` pour toutes les autres.
    public var bundleID: String
    public var name: String
    public var style: DictationStyle
    /// Appuyer sur Entrée une fois le texte collé : le message part tout seul.
    public var pressReturn: Bool
    /// Mise au propre par l'IA locale, avec une consigne facultative.
    public var polish: Bool
    public var instructions: String
    /// Taper le texte touche par touche plutôt que coller, pour les apps qui refusent ⌘V.
    public var typeText: Bool

    public init(
        id: UUID = UUID(), bundleID: String, name: String, style: DictationStyle = .standard,
        pressReturn: Bool = false, polish: Bool = false, instructions: String = "", typeText: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.style = style
        self.pressReturn = pressReturn
        self.polish = polish
        self.instructions = instructions
        self.typeText = typeText
    }

    enum CodingKeys: String, CodingKey {
        case id, bundleID, name, style, pressReturn, polish, instructions, typeText
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try values.decode(String.self, forKey: .bundleID)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? bundleID
        style = try values.decodeIfPresent(DictationStyle.self, forKey: .style) ?? .standard
        pressReturn = try values.decodeIfPresent(Bool.self, forKey: .pressReturn) ?? false
        polish = try values.decodeIfPresent(Bool.self, forKey: .polish) ?? false
        instructions = try values.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        typeText = try values.decodeIfPresent(Bool.self, forKey: .typeText) ?? false
    }
}

public enum AppRuleStore {
    public static var url: URL { PlumeSettings.supportDirectory.appendingPathComponent("applications.json") }

    public static func load() -> [AppRule] {
        guard let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([AppRule].self, from: data)
        else { return [] }
        return items
    }

    public static func save(_ items: [AppRule]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(items).write(to: url, options: .atomic)
    }

    /// La règle qui s'applique à une application : la sienne, sinon celle de « toutes les autres ».
    public static func rule(for bundleID: String?, in rules: [AppRule]) -> AppRule? {
        if let bundleID, let own = rules.first(where: { $0.bundleID == bundleID }) { return own }
        return rules.first { $0.bundleID == "*" }
    }
}
