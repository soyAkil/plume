import Foundation

/// Look of the dictated text, depending on where it is pasted: an email calls for a different register
/// than a Slack message or a command in the terminal.
public enum DictationStyle: String, Codable, Sendable, CaseIterable {
    /// As the model writes it: full capitals and punctuation.
    case standard
    /// Instant message: no final period.
    case message
    /// Casual: no capital at the start of a sentence, no final period.
    case casual

    public var label: String {
        switch self {
        case .standard: return tr("Standard")
        case .message: return tr("Message")
        case .casual: return tr("Casual")
        }
    }

    public var detail: String {
        switch self {
        case .standard: return tr("Full capitals and punctuation.")
        case .message: return tr("No final period, the way you write on Slack or Messages.")
        case .casual: return tr("No capital at the start of a sentence, no final period.")
        }
    }
}

public enum TextStyle {
    /// - Parameter final: false for a chunk typed as the dictation goes, whose period is not
    ///   the last one: it stays.
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

    /// Removes the final period (not ellipses, nor ? or !).
    static func droppingFinalPeriod(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "\n" { result.removeLast() }
        guard result.hasSuffix("."), !result.hasSuffix("..") else { return text }
        result.removeLast()
        // The final line break, if any, is kept.
        return result + text.suffix(while: { $0 == "\n" })
    }

    /// A lowercase letter at the start of each sentence, except for an acronym ("URL") and the English "I".
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
    /// The last characters that satisfy the condition, in order.
    fileprivate func suffix(while predicate: (Character) -> Bool) -> String {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return String(self[end...])
    }
}

/// Per-app dictation settings: text style, validating with Return,
/// AI clean-up, insertion method.
public struct AppRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// App identifier (`com.tinyspeck.slackmacgap`), or `*` for all the others.
    public var bundleID: String
    public var name: String
    public var style: DictationStyle
    /// Press Return once the text is pasted: the message sends itself.
    public var pressReturn: Bool
    /// Clean-up by the local AI, with an optional instruction.
    public var polish: Bool
    public var instructions: String
    /// Type the text key by key rather than pasting, for apps that refuse ⌘V.
    public var typeText: Bool
    /// A key pressed before pasting, to open the field: `T` opens the Minecraft chat. Empty: none.
    public var openKey: String
    /// Seconds given to the field to appear after the opening key, before the paste.
    public var openDelay: Double

    public init(
        id: UUID = UUID(), bundleID: String, name: String, style: DictationStyle = .standard,
        pressReturn: Bool = false, polish: Bool = false, instructions: String = "", typeText: Bool = false,
        openKey: String = "", openDelay: Double = 0.5
    ) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.style = style
        self.pressReturn = pressReturn
        self.polish = polish
        self.instructions = instructions
        self.typeText = typeText
        self.openKey = openKey
        self.openDelay = openDelay
    }

    /// Comes with Plume (`AppRuleStore.builtIn`): editable, not removable.
    public var isBuiltIn: Bool { AppRuleStore.builtIn.contains { $0.bundleID == bundleID } }

    /// What a rule is keyed on: the bundle identifier, or `process:<name>` for an app that has
    /// none (the Minecraft game is a bare `java` process).
    public static func identifier(bundleID: String?, processName: String?) -> String? {
        if let bundleID, !bundleID.isEmpty { return bundleID }
        return processName.map { "process:\($0)" }
    }

    enum CodingKeys: String, CodingKey {
        case id, bundleID, name, style, pressReturn, polish, instructions, typeText, openKey, openDelay
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
        openKey = try values.decodeIfPresent(String.self, forKey: .openKey) ?? ""
        openDelay = try values.decodeIfPresent(Double.self, forKey: .openDelay) ?? 0.5
    }
}

public enum AppRuleStore {
    public static var url: URL { PlumeSettings.supportDirectory.appendingPathComponent("applications.json") }

    /// Rules that come with Plume, for apps that need one to work at all: in Minecraft the chat
    /// box has to be opened (T) and the message sent (Return). Shown and edited like the others;
    /// a saved rule for the same app replaces it.
    public static let builtIn = [
        AppRule(
            id: UUID(uuidString: "4D494E45-4352-4146-5400-000000000001")!,
            bundleID: AppRule.identifier(bundleID: nil, processName: "java")!, name: "Minecraft",
            style: .message, pressReturn: true, openKey: "T"),
    ]

    /// The saved rules, plus the built-in ones they don't replace.
    public static func withBuiltIn(_ rules: [AppRule]) -> [AppRule] {
        rules + builtIn.filter { built in !rules.contains { $0.bundleID == built.bundleID } }
    }

    public static func load() -> [AppRule] {
        withBuiltIn(read(from: url) ?? [])
    }

    public static func save(_ items: [AppRule]) {
        try? write(items, to: url)
    }

    /// A rules file, `nil` if it is missing or unreadable.
    public static func read(from url: URL) -> [AppRule]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([AppRule].self, from: data)
    }

    public static func write(_ items: [AppRule], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    /// The rule that applies to an app: its own, otherwise the one for "all the others".
    public static func rule(for bundleID: String?, in rules: [AppRule]) -> AppRule? {
        if let bundleID, let own = rules.first(where: { $0.bundleID == bundleID }) { return own }
        return rules.first { $0.bundleID == "*" }
    }
}
