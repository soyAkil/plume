import Foundation

/// Ce qui entoure le curseur dans le champ actif, quelques caractères de chaque côté.
public struct InsertionContext: Sendable, Equatable {
    public var before: String
    public var after: String

    public init(before: String, after: String = "") {
        self.before = before
        self.after = after
    }

    public static let empty = InsertionContext(before: "")
}

/// Adapte une dictée à l'endroit où elle est collée : une espace si le curseur est collé à un
/// mot, une minuscule si la phrase est déjà commencée, pas de point final si elle continue.
/// Le modèle écrit chaque dictée comme un texte complet ; ici on la fond dans l'existant.
public enum SmartInsert {
    public static func adapt(_ text: String, context: InsertionContext) -> String {
        guard !text.isEmpty else { return text }
        let before = context.before
        let after = context.after
        var result = text

        // Dernier caractère visible avant le curseur ; rien, ou un saut de ligne : début de texte.
        let previous = before.last(where: { $0 != " " && $0 != "\t" && $0 != "\u{A0}" })
        guard let previous, previous != "\n", previous != "\r" else { return result }
        let next = after.first(where: { $0 != " " && $0 != "\t" && $0 != "\u{A0}" })

        // La phrase en cours n'est pas finie : on la continue en minuscule.
        let midSentence = previous.isLetter || previous.isNumber || ",;:)]}»\"'".contains(previous)
        if midSentence, let first = result.first, first.isUppercase, startsWithCommonWord(result) {
            result = first.lowercased() + result.dropFirst()
        }
        // Et pas de point final si elle se poursuit après le curseur, sur la même ligne.
        let continues = next.map { $0.isLetter || $0.isNumber || ",;".contains($0) } ?? false
        let sameLine = !after.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("\n")
        if continues, sameLine, result.hasSuffix("."), !result.hasSuffix("..") { result.removeLast() }

        // Une espace entre le mot précédent et la dictée ; aucune après une ouverture.
        if let last = before.last, !last.isWhitespace, !"([{«\"'‘“/".contains(last), !result.hasPrefix("\n") {
            result = " " + result
        }
        // Et une après, si le texte reprend tout de suite.
        if let first = after.first, first.isLetter || first.isNumber || "([«".contains(first), !result.hasSuffix("\n") {
            result += " "
        }
        return result
    }

    /// Mots courants qui ouvrent une phrase : ceux-là perdent leur majuscule sans risque,
    /// contrairement à un nom propre (« Paris ») qu'on ne sait pas reconnaître.
    private static let commonWords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "au", "aux", "et", "ou", "mais", "donc", "or",
        "ni", "car", "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ce", "c", "ça", "cela",
        "ceci", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
        "votre", "vos", "leur", "leurs", "que", "qu", "qui", "quoi", "dont", "où", "quand", "comme", "si", "pour",
        "par", "sur", "sous", "dans", "avec", "sans", "chez", "vers", "entre", "en", "à", "y", "ne", "n", "pas",
        "plus", "moins", "très", "trop", "bien", "mal", "aussi", "alors", "puis", "ensuite", "enfin", "encore",
        "déjà", "toujours", "jamais", "peut", "peut-être", "est", "sont", "a", "ai", "as", "avons", "avez", "ont",
        "été", "être", "avoir", "faire", "fait", "faut", "va", "vais", "vas", "vont", "voilà", "voici", "merci",
        "oui", "non", "bon", "bonne", "tout", "tous", "toute", "toutes", "rien", "chaque", "quelque", "quelques",
        "après", "avant", "depuis", "pendant", "parce", "lorsque", "comment", "pourquoi", "combien", "ici", "là",
        "the", "a", "an", "and", "or", "but", "so", "if", "it", "its", "it's", "he", "she", "we", "they", "you",
        "this", "that", "these", "those", "my", "your", "our", "their", "his", "her", "to", "of", "in", "on", "at",
        "for", "with", "from", "by", "as", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do",
        "does", "did", "not", "no", "yes", "then", "also", "just", "very", "more", "less", "can", "could", "will",
        "would", "should", "there", "here", "when", "where", "what", "which", "who", "how", "why", "because",
        "please", "thanks", "ok", "okay", "let's", "let", "all", "some", "any", "every", "about", "into", "over",
    ]

    private static func startsWithCommonWord(_ text: String) -> Bool {
        let end = text.firstIndex(where: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }) ?? text.endIndex
        var word = String(text[..<end]).lowercased().replacingOccurrences(of: "’", with: "'")
        // « J'ai » : c'est le pronom élidé qui compte.
        if let apostrophe = word.firstIndex(of: "'") { word = String(word[..<apostrophe]) }
        return commonWords.contains(word)
    }
}
