import Foundation

/// Langue de l'interface. Le code est écrit en français ; l'anglais vient d'une table de
/// traduction, et c'est la langue par défaut de l'app. L'autre langue se choisit dans les
/// réglages, sans tenir compte de celle du système.
public enum Language: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case french = "fr"

    public var id: String { rawValue }

    /// Le nom de la langue, dans la langue elle-même.
    public var label: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        }
    }

    /// Pour les dates et les nombres.
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .french: return Locale(identifier: "fr_FR")
        }
    }
}

public enum L10n {
    /// Langue en vigueur. Les sources sont en français : c'est la valeur de départ, et celle
    /// des tests ; l'app et la ligne de commande la règlent au lancement d'après les réglages.
    nonisolated(unsafe) public static var current: Language = .french

    /// Traduction d'une chaîne française. Une chaîne absente de la table revient telle quelle.
    public static func translate(_ french: String) -> String {
        guard current == .english else { return french }
        return english[french] ?? french
    }

    /// Les chaînes de la table qui ne sont pas traduites (diagnostic).
    public static var missing: [String] { english.filter { $0.value.isEmpty }.map(\.key).sorted() }

    /// Français → anglais, pour tout ce que l'interface affiche.
    static let english: [String: String] = L10nTable.english
}

/// `tr("Historique")` : le texte dans la langue en vigueur.
public func tr(_ french: String) -> String {
    L10n.translate(french)
}
