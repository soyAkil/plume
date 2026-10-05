import Foundation

/// Nettoyage léger et déterministe d'une dictée : retire les hésitations et les mots
/// bégayés, sans jamais reformuler. Le texte brut reste conservé dans le transcript.
public enum TextCleanup {
    /// Hésitations supprimées quand elles forment un mot à part entière.
    private static let fillers: Set<String> = ["euh", "heu", "euhm", "hum", "hmm", "mmh", "um", "uh", "uhm", "erm"]

    /// Mots-outils qui ne se répètent jamais légitimement (« de de », « mon mon »).
    /// « nous » et « vous » en sont exclus : « nous nous sommes », « vous vous êtes ».
    private static let functionWords: Set<String> = [
        "le", "la", "les", "l'", "un", "une", "des", "de", "du", "d'", "à", "au", "aux", "et", "en",
        "je", "j'", "tu", "il", "elle", "on", "ils", "elles", "ce", "ça", "c'est", "que", "qu'", "qui",
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "votre", "leur",
        "pour", "par", "sur", "dans", "avec", "mais", "ou", "donc", "pas", "ne", "n'", "y", "se",
        "quand", "comme", "est", "sont", "ai", "a", "j'ai", "c'était", "qu'il", "qu'on", "si",
        "the", "an", "to", "of", "and", "in", "i", "it", "is", "that", "this", "we", "you",
    ]

    public static func clean(_ text: String) -> String {
        var tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        tokens = removeFillers(tokens)
        for n in [3, 2, 1] {
            tokens = collapseRepeats(tokens, n: n)
        }
        var result = tokens.joined(separator: " ")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: ",,", with: ",")
        result = result.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix(",") { result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return capitalizeFirst(result)
    }

    /// Forme de comparaison : minuscules, sans ponctuation finale.
    private static func key(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…"))
    }

    private static func hasPunctuation(_ token: String) -> Bool {
        token.last.map { ".,;:!?…".contains($0) } ?? false
    }

    private static func removeFillers(_ tokens: [String]) -> [String] {
        var out: [String] = []
        for token in tokens {
            guard fillers.contains(key(token)) else {
                out.append(token)
                continue
            }
            // « bon, euh. Voilà » : la ponctuation forte portée par l'hésitation revient au mot précédent.
            if let mark = token.last, ".?!".contains(mark), let last = out.last, !hasPunctuation(last) {
                out[out.count - 1] = last + String(mark)
            }
        }
        return out
    }

    /// Supprime les répétitions immédiates d'un groupe de `n` mots (« ça le ça le ça le marque »).
    private static func collapseRepeats(_ tokens: [String], n: Int) -> [String] {
        guard tokens.count >= 2 * n else { return tokens }
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if i + 2 * n <= tokens.count {
                let first = Array(tokens[i..<i + n])
                let second = Array(tokens[i + n..<i + 2 * n])
                let sameWords = zip(first, second).allSatisfy { key($0) == key($1) }
                // Une ponctuation dans la première occurrence signale une vraie reprise de phrase.
                let cleanFirst = !first.contains(where: hasPunctuation)
                if sameWords, cleanFirst, isStutter(first.map(key)) {
                    i += n
                    continue
                }
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    private static func isStutter(_ words: [String]) -> Bool {
        if words.count == 1 { return functionWords.contains(words[0]) }
        return words.contains(where: functionWords.contains)
    }

    /// Une majuscule au premier mot, s'il n'en a pas.
    public static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
