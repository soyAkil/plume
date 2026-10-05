import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// L'IA locale : le modèle de langage d'Apple Intelligence, qui tourne sur l'appareil
/// (macOS 26 ou plus récent, Apple Intelligence activée). Rien ne quitte le Mac. Elle sert à
/// mettre une dictée au propre, à résumer une réunion et à transformer un texte sur consigne.
/// Toujours en option : sans elle, Plume fait tout de façon déterministe.
public enum LocalAI {
    public enum Availability: Sendable, Equatable {
        case available
        case unavailable(String)

        public var isAvailable: Bool { self == .available }
        public var reason: String? {
            if case .unavailable(let reason) = self { return reason }
            return nil
        }
    }

    public enum Failure: LocalizedError {
        case unavailable(String)
        case refused
        case empty

        public var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .refused: return tr("L'IA locale n'a pas voulu traiter ce texte.")
            case .empty: return tr("L'IA locale n'a rien répondu.")
            }
        }
    }

    public struct Summary: Sendable, Equatable {
        public var title: String
        /// Markdown : points clés, décisions, actions.
        public var markdown: String
    }

    /// Taille maximale d'un texte soumis d'un coup, en caractères : le modèle sur l'appareil
    /// n'a qu'une fenêtre de 4 096 jetons, réponse comprise.
    static let chunkCharacters = 5_000

    public static var availability: Availability {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return .available
                case .unavailable(let reason):
                    switch reason {
                    case .deviceNotEligible: return .unavailable("Ce Mac ne prend pas en charge Apple Intelligence.")
                    case .appleIntelligenceNotEnabled:
                        return .unavailable("Apple Intelligence n'est pas activée (Réglages Système › Apple Intelligence et Siri).")
                    case .modelNotReady: return .unavailable("Le modèle d'Apple Intelligence se télécharge encore.")
                    @unknown default: return .unavailable("Apple Intelligence n'est pas disponible.")
                    }
                }
            }
            return .unavailable("L'IA locale demande macOS 26 ou plus récent.")
        #else
            return .unavailable("L'IA locale demande macOS 26 ou plus récent.")
        #endif
    }

    /// Prépare le modèle en mémoire, pour que la première réponse ne traîne pas.
    public static func prewarm() {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *), availability.isAvailable {
                LanguageModelSession().prewarm()
            }
        #endif
    }

    // MARK: - Mise au propre d'une dictée

    static let polishInstructions = """
        Tu es un correcteur discret. On te donne la transcription brute d'une dictée vocale.
        Réécris-la proprement : ponctuation, majuscules, fautes évidentes de transcription.
        Retire les hésitations et les faux départs. Quand la personne se corrige (« non pardon »,
        « je veux dire », « plutôt »), ne garde que la version corrigée.
        Ne change pas le sens, n'ajoute rien, ne résume pas, ne commente pas, ne réponds pas au
        texte. Garde la langue d'origine, le tutoiement ou le vouvoiement, et les sauts de ligne.
        Réponds uniquement avec le texte final, sans guillemets ni introduction.
        """

    /// Met une dictée au propre. Le texte est rendu tel quel si la réponse paraît douteuse
    /// (vide, bien plus longue ou plus courte que l'original).
    public static func polish(_ text: String, instructions: String = "") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        var system = polishInstructions
        let extra = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { system += "\nConsignes particulières : \(extra)" }
        var pieces: [String] = []
        for chunk in chunks(of: trimmed) {
            let answer = try await respond(instructions: system, prompt: chunk)
            pieces.append(plausible(answer, for: chunk) ? answer : chunk)
        }
        return pieces.joined(separator: "\n\n")
    }

    /// Une réponse de mise au propre doit ressembler à l'original : ni vide, ni deux fois plus
    /// longue, ni réduite de moitié (le modèle a parfois répondu au texte au lieu de le corriger).
    static func plausible(_ answer: String, for original: String) -> Bool {
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let ratio = Double(cleaned.count) / Double(max(1, original.count))
        let short = original.count < 60
        return ratio <= (short ? 2.5 : 1.5) && ratio >= (short ? 0.3 : 0.5)
    }

    // MARK: - Transformation sur consigne

    static let transformInstructions = """
        Tu modifies un texte selon une consigne dictée à voix haute. Applique la consigne
        fidèlement (reformuler, traduire, raccourcir, corriger, changer le ton, mettre en liste…).
        Réponds uniquement avec le texte résultat, sans explication, sans guillemets, dans la
        langue demandée ou sinon celle du texte.
        """

    static let composeInstructions = """
        Tu rédiges un texte à partir d'une consigne dictée à voix haute (un message, un mail, une
        note, une liste…). Reste sobre et direct, dans la langue de la consigne. Réponds uniquement
        avec le texte demandé, sans explication ni formule d'accompagnement.
        """

    /// Réécrit `selection` selon `instruction` ; sans sélection, rédige à partir de la consigne.
    public static func transform(_ selection: String, instruction: String) async throws -> String {
        let consigne = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consigne.isEmpty else { throw Failure.empty }
        if text.isEmpty {
            return try await respond(instructions: composeInstructions, prompt: consigne)
        }
        var pieces: [String] = []
        for chunk in chunks(of: text) {
            pieces.append(try await respond(instructions: transformInstructions, prompt: "Consigne : \(consigne)\n\nTexte :\n\(chunk)"))
        }
        return pieces.joined(separator: "\n\n")
    }

    // MARK: - Résumé d'une réunion

    /// Les notes sont rédigées dans la langue de l'interface.
    static var notesInstructions: String {
        L10n.current == .french
            ? """
            Tu prends des notes de réunion à partir d'une transcription (« Moi » désigne le
            propriétaire de l'appareil). Rédige en français, en Markdown, sans titre de niveau 1 :
            - une section « ## Points clés » : 3 à 7 puces, factuelles et concises ;
            - une section « ## Décisions » : les décisions prises (ou « Aucune ») ;
            - une section « ## Actions » : une puce par action, avec qui s'en charge quand c'est dit.
            N'invente rien : si quelque chose n'est pas dans la transcription, ne l'écris pas.
            Réponds uniquement avec ces notes.
            """
            : """
            You take meeting notes from a transcript ("Me" is the owner of the device).
            Write in English, in Markdown, with no level-1 heading:
            - a "## Key points" section: 3 to 7 factual, concise bullets;
            - a "## Decisions" section: the decisions made (or "None");
            - an "## Actions" section: one bullet per action, with who owns it when it is said.
            Do not invent anything: if it is not in the transcript, do not write it.
            Reply with these notes only.
            """
    }

    static var mergeInstructions: String {
        L10n.current == .french
            ? """
            On te donne plusieurs séries de notes prises sur les parties successives d'une même
            réunion. Fusionne-les en une seule série de notes, en français, en Markdown, sans titre de
            niveau 1, avec les sections « ## Points clés », « ## Décisions » et « ## Actions ».
            Supprime les redites, garde l'ordre chronologique, n'invente rien.
            Réponds uniquement avec les notes fusionnées.
            """
            : """
            You are given several sets of notes taken on successive parts of the same meeting.
            Merge them into a single set of notes, in English, in Markdown, with no level-1
            heading, with the sections "## Key points", "## Decisions" and "## Actions".
            Remove repetitions, keep the chronological order, do not invent anything.
            Reply with the merged notes only.
            """
    }

    static var titleInstructions: String {
        L10n.current == .french
            ? """
            Donne un titre court (au plus six mots, sans ponctuation finale, sans guillemets) à une
            réunion, à partir de ses notes. Réponds uniquement avec le titre.
            """
            : """
            Give a short title (six words at most, no final punctuation, no quotes) to a meeting,
            from its notes. Reply with the title only.
            """
    }

    public static func summarize(_ transcript: Transcript) async throws -> Summary {
        let text = transcript.speakers.count > 1 ? TranscriptBuilder.text(for: transcript.segments) : transcript.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        var notes: [String] = []
        for chunk in chunks(of: text) {
            notes.append(try await respond(instructions: notesInstructions, prompt: chunk))
        }
        // Les notes partielles sont fusionnées, par étapes si elles sont elles-mêmes trop longues.
        while notes.count > 1 {
            var merged: [String] = []
            for group in chunks(of: notes.joined(separator: "\n\n---\n\n")) {
                merged.append(try await respond(instructions: mergeInstructions, prompt: group))
            }
            if merged.count >= notes.count { break }
            notes = merged
        }
        let markdown = tidyMarkdown(notes.joined(separator: "\n\n"))
        var title = try await respond(instructions: titleInstructions, prompt: markdown)
        title = title.components(separatedBy: .newlines).first ?? title
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \"«»“”.:!*#"))
        return Summary(title: String(title.prefix(80)), markdown: markdown)
    }

    /// Le modèle met parfois les titres en puces et indente les listes : on remet d'aplomb.
    static func tidyMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { raw -> String in
            var line = raw.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: "^[-*•]\\s+(#+\\s)", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "^[*•]\\s+", with: "- ", options: .regularExpression)
            line = line.replacingOccurrences(of: "^#\\s+", with: "## ", options: .regularExpression)
            return line
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Découpage et appel du modèle

    /// Découpe un long texte en morceaux de taille raisonnable, aux fins de paragraphe ou de phrase.
    static func chunks(of text: String, limit: Int = chunkCharacters) -> [String] {
        guard text.count > limit else { return [text] }
        var chunks: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            let candidate = current.isEmpty ? paragraph : current + "\n" + paragraph
            if candidate.count <= limit {
                current = candidate
                continue
            }
            if !current.isEmpty { chunks.append(current) }
            current = ""
            // Un paragraphe trop long à lui seul : coupé aux phrases.
            var sentences = ""
            for sentence in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let next = sentences.isEmpty ? String(sentence) : sentences + " " + sentence
                if next.count > limit, !sentences.isEmpty {
                    chunks.append(sentences)
                    sentences = String(sentence)
                } else {
                    sentences = next
                }
            }
            current = sentences
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Une question, une réponse. Chaque appel ouvre une session neuve : rien ne déborde d'une
    /// dictée sur la suivante.
    static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                guard availability.isAvailable else { throw Failure.unavailable(availability.reason ?? "") }
                let session = LanguageModelSession(instructions: instructions)
                do {
                    let response = try await session.respond(
                        to: prompt, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 1_500))
                    let answer = stripped(response.content)
                    guard !answer.isEmpty else { throw Failure.empty }
                    return answer
                } catch let error as LanguageModelSession.GenerationError {
                    switch error {
                    case .guardrailViolation, .refusal: throw Failure.refused
                    default: throw error
                    }
                }
            }
        #endif
        throw Failure.unavailable(availability.reason ?? "")
    }

    /// Le modèle encadre parfois sa réponse (« Voici le texte corrigé : », guillemets, bloc de
    /// code) : on ne garde que le contenu.
    static func stripped(_ answer: String) -> String {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "^```[a-z]*\\n?", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(
            of: "^(?:voici|here is|here's)[^:\\n]{0,60}:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        if text.count > 2, let first = text.first, let last = text.last,
            ("\"" == first && "\"" == last) || ("«" == first && "»" == last)
        {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
