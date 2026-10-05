import Foundation

/// Commandes dictées à voix haute : « à la ligne », « nouveau paragraphe », « point
/// d'interrogation », « efface ça », « appuie sur Entrée »… Le modèle les écrit comme des
/// mots ordinaires, le plus souvent entourés de ponctuation (« Bonjour, à la ligne, je
/// voulais… ») : on les retrouve ici après coup pour les exécuter. En français comme en anglais.
public enum VoiceCommands {
    public struct Result: Sendable, Equatable {
        public var text: String
        /// La dictée se terminait par « appuie sur Entrée » : valider une fois le texte collé.
        public var pressReturn: Bool

        public init(text: String, pressReturn: Bool = false) {
            self.text = text
            self.pressReturn = pressReturn
        }
    }

    public static func apply(to text: String) -> Result {
        var result = text
        var pressReturn = false
        if let range = sendCommand.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)).flatMap({ Range($0.range, in: result) }) {
            result.removeSubrange(range)
            pressReturn = true
        }
        for (regex, template) in rewrites {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        result = scratched(result)
        return Result(text: tidy(result), pressReturn: pressReturn)
    }

    // MARK: - Les commandes

    /// Espaces et ponctuation que le modèle colle avant ou après une commande.
    private static let before = "[ \\t]*"
    private static let after = "[ \\t]*[.,;:]*[ \\t]*"
    /// La commande est une phrase à elle seule : précédée d'une ponctuation ou du début du texte.
    private static let isolatedBefore = "(?:^|(?<=[.!?…,;\\n]))[ \\t]*"
    private static let isolatedAfter = "[ \\t]*(?=[.!?…,;\\n]|$)[.!?…,;]*[ \\t]*"

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// « Appuie sur Entrée » tout à la fin : le message part dès qu'il est collé.
    private static let sendCommand = regex(
        "[ \\t]*[,;]?[ \\t]*\\b(?:appu(?:ie|ies|ya|yer|yez) sur (?:la touche )?entr(?:ée|ee|er|ez)|press enter|hit enter)\\b[ \\t.!,]*$")!

    /// Réécritures dans l'ordre : ponctuation et guillemets dictés, puis sauts de ligne, puis puces.
    private static let rewrites: [(NSRegularExpression, String)] = [
        // Ponctuation dite explicitement (le modèle ponctue déjà tout seul, on ne garde que ce
        // qui ne peut pas être un mot ordinaire). À la française : une espace avant ? ! : ;
        ("\(before)[,.;]?\(before)\\bpoint d['’]interrogation\\b\(after)", " ? "),
        ("\(before)[,.;]?\(before)\\bpoint d['’]exclamation\\b\(after)", " ! "),
        ("\(before)[,.;]?\(before)\\bpoints? de suspension\\b\(after)", "… "),
        ("\(before)[,.;]?\(before)\\bpoint[ -]virgule\\b\(after)", " ; "),
        // « Deux points » n'est une commande que s'il est suivi d'une pause (ponctuation) ou de la fin.
        ("\(before)[,.;]?\(before)\\b(?:deux|2)[ -]points\\b(?=[ \\t]*(?:[,.;:\\n]|$))\(after)", " : "),
        ("\(before)[,.;]?\(before)\\bquestion mark\\b\(after)", "? "),
        ("\(before)[,.;]?\(before)\\bexclamation (?:mark|point)\\b\(after)", "! "),
        // Guillemets et parenthèses. Après une fermeture, la ponctuation reste : « oui ».
        ("\(before)\\bouvr(?:ez|e|ir) (?:les?|des) guillemets?\\b\(after)", " « "),
        ("\(before)[,.;]?\(before)\\bferm(?:ez|e|er) (?:les?|des) guillemets?\\b[ \\t]*", " »"),
        ("\(before)\\bopen quotes?\\b\(after)", " \""),
        ("\(before)[,.;]?\(before)\\b(?:close quotes?|end quotes?|unquote)\\b[ \\t]*", "\""),
        ("\(before)\\bouvr(?:ez|e|ir) (?:la |une )?parenth[èe]se\\b\(after)", " ("),
        ("\(before)[,.;]?\(before)\\bferm(?:ez|e|er) (?:la )?parenth[èe]se\\b[ \\t]*", ")"),
        ("\(before)\\bopen paren(?:thesis)?\\b\(after)", " ("),
        ("\(before)[,.;]?\(before)\\bclose paren(?:thesis)?\\b[ \\t]*", ")"),
        // Sauts. « Un nouveau paragraphe », « la nouvelle ligne de produits », « pêche à la ligne »
        // ou « à la ligne 12 » ne sont pas des commandes.
        ("\(before)\\bpoint à la ligne\\b(?!\\s*\\d)\(after)", ".\n"),
        ("\(before)(?<!\\b(?:le|un|ce|du|au|chaque|premier|dernier|a|the|this|each|first|last) )\\b(?:nouveau paragraphe|new paragraph)\\b\(after)", "\n\n"),
        (
            "\(before)(?<!\\b(?:la|une|cette|notre|votre|leur|sa|ma|ta|de|the|a|this|each|next|one) )(?<!\\bpêch(?:e|er|ent|es|ez|ait|ant) )"
                + "\\b(?:retour à la ligne|(?:aller |va |passe |passer )?à la ligne|nouvelle ligne|new ?line)\\b"
                + "(?![ \\t]*(?:\\d|(?:suivante|précédente|près|d['’e]|du|des|below|above)\\b))\(after)", "\n"
        ),
        // Puces : « nouvelle puce », ou « tiret » juste après un saut de ligne.
        ("\(before)\\b(?:nouvelle puce|bullet point|new bullet)\\b\(after)", "\n- "),
        ("\\n[ \\t]*\\btiret\\b[ \\t]*[,.;:]?[ \\t]*", "\n- "),
    ].compactMap { (pattern: String, template: String) -> (NSRegularExpression, String)? in
        regex(pattern).map { ($0, template) }
    }

    /// « Efface ça » retire la phrase qui précède ; « efface tout » retire tout ce qui précède.
    private static let scratchCommand = regex(
        "\(isolatedBefore)\\b(?:(efface(?:r|z)? tout|annule(?:r|z)? tout|tout effacer|delete everything|clear everything)"
            + "|efface(?:r|z)? (?:ça|cela|ca)|supprime(?:r|z)? (?:ça|cela)|annule(?:r|z)? (?:ça|cela)|scratch that|delete that)\\b\(isolatedAfter)")!

    private static func scratched(_ text: String) -> String {
        var result = text
        while let match = scratchCommand.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
            let range = Range(match.range, in: result)
        {
            let everything = match.range(at: 1).location != NSNotFound
            var kept = String(result[..<range.lowerBound])
            if everything {
                kept = ""
            } else {
                // La ponctuation de la phrase à effacer, puis la phrase elle-même, jusqu'à la fin
                // de celle d'avant.
                while let last = kept.last, " .!?…".contains(last) { kept.removeLast() }
                if let boundary = kept.lastIndex(where: { ".!?…\n".contains($0) }) {
                    kept = String(kept[...boundary])
                } else {
                    kept = ""
                }
            }
            var rest = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = capitalizingFirst(rest)
            if !kept.isEmpty, !rest.isEmpty, kept.last != "\n" { kept += " " }
            result = kept + rest
        }
        return result
    }

    // MARK: - Mise au net

    private static let tidyRules: [(NSRegularExpression, String)] = [
        ("[ \\t]+\\n", "\n"),
        ("\\n[ \\t]+", "\n"),
        ("\\n{3,}", "\n\n"),
        ("[ \\t]{2,}", " "),
        // Pas d'espace avant une virgule ni un point (le point-virgule en garde une, à la française).
        ("[ \\t]+([,.])", "$1"),
        ("([,;:])[,;:]+", "$1"),
        ("\\.{2}(?!\\.)", "."),
        // Rien ne précède une ponctuation en début de ligne, hormis une puce.
        ("(^|\\n)[,.;:]+[ \\t]*", "$1"),
        ("« {2,}", "« "),
        (" {2,}»", " »"),
        // Une virgule orpheline en fin de texte (« à bientôt, appuie sur Entrée »), ou devant une puce.
        ("[ \\t]*[,;]+[ \\t]*$", ""),
        ("[,;]+\\n(- )", "\n$1"),
    ].compactMap { (pattern: String, template: String) -> (NSRegularExpression, String)? in
        regex(pattern).map { ($0, template) }
    }

    private static func tidy(_ text: String) -> String {
        var result = text
        for (regex, template) in tidyRules {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        // Une majuscule après chaque saut de ligne (sauf sur une puce, qui garde la casse dictée).
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        result = lines.enumerated().map { index, line in
            index == 0 || line.hasPrefix("- ") ? line : capitalizingFirst(line)
        }.joined(separator: "\n")
        // Les espaces en bordure partent ; un saut de ligne final dicté reste.
        while let first = result.first, first == " " || first == "\t" { result.removeFirst() }
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result.allSatisfy(\.isWhitespace) ? "" : result
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter }), text[index].isLowercase,
            text[..<index].allSatisfy({ " «\"(".contains($0) })
        else { return text }
        return String(text[..<index]) + text[index].uppercased() + String(text[text.index(after: index)...])
    }
}
