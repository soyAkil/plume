import Foundation
import Testing
@testable import PlumeKit

/// What a dictation becomes, from raw model output to pasted text, one line per case.
/// Each fix or new command adds its lines: the case handled, and the closest ordinary
/// sentence, which must not change. A known issue is written with the expected result
/// and the reason: once it is fixed, its line asks for the mention to be removed.
@Suite("Dictation text")
struct DictationCorpusTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var raw: String
        var expected: String
        var pressReturn = false
        var options = DictationOptions()
        var vocabulary: [Replacement] = []
        var final = true
        /// Known issue, not fixed yet: the line says what is expected, and this says why
        /// it fails today.
        var knownIssue: String?
        /// The known issue also affects the Enter press.
        var knownIssueOnReturn = false

        var testDescription: String {
            var label = raw.replacingOccurrences(of: "\n", with: "⏎")
            if options.style != .standard { label += " [\(options.style.rawValue)]" }
            if !options.cleanup { label += " [no cleanup]" }
            if !options.voiceCommands { label += " [no commands]" }
            if !final { label += " [in progress]" }
            return label
        }

        /// A sentence that must come out unchanged.
        static func same(_ raw: String, options: DictationOptions = DictationOptions()) -> Case {
            Case(raw: raw, expected: raw, options: options)
        }
    }

    static let ordinary: [Case] = [
        .same("Le rendez-vous est à 16 h 30, salle 2."),
        .same("J'ai 2 enfants et 3 chats."),
        .same("Ça coûte 25 € par mois."),
        .same("It costs 25 dollars a month."),
        .same("Call me at 3 pm, okay?"),
        .same("Marie-Claire et Jean-Pierre arrivent demain."),
        .same("Est-ce que tu viens ?"),
        .same("Il a dit : « oui »."),
        .same("La version 2.0 est sortie."),
        .same("Écris à contact@example.com demain."),
        .same("Le taux est de 3,5 %."),
        .same("Rendez-vous à 9 h 15 ou à 10:30."),
        .same("Il est très très content."),
        .same("Le chien le chat le chien le chat."),
        .same("Bah oui, bien sûr."),
        .same("Ben voilà, c'est fait."),
        .same("Le mot ainsi vient du latin."),
    ]

    /// Phrases close to a command that are not one.
    static let lookalikes: [Case] = [
        .same("Il part à la pêche à la ligne demain."),
        .same("La nouvelle ligne de produits sort lundi."),
        .same("Regarde à la ligne 12 du fichier."),
        .same("Il est parti à la ligne 3 du tableau."),
        .same("Passe à la ligne suivante."),
        .same("On se voit à la ligne d'arrivée."),
        .same("C'est un nouveau paragraphe du contrat."),
        .same("Il y a deux points de vue."),
        .same("Je suis à deux points de la victoire."),
        .same("Efface ça et recommence."),
        .same("Appuie sur entrée pour valider le formulaire."),
        .same("Press enter to continue."),
        .same("The new line of products ships Monday."),
        .same("Read the new line."),
        .same("Add a new paragraph about pricing."),
        .same("Ouvre la fenêtre et ferme la porte."),
    ]

    static let commands: [Case] = [
        Case(raw: "Bonjour, à la ligne, je voulais te dire merci.", expected: "Bonjour,\nJe voulais te dire merci."),
        Case(raw: "Bonjour va à la ligne merci", expected: "Bonjour\nMerci"),
        Case(raw: "Bonjour Marie, à la ligne, merci pour ton aide, à la ligne, Paul", expected: "Bonjour Marie,\nMerci pour ton aide,\nPaul"),
        Case(raw: "Premier point. Nouveau paragraphe. Deuxième point.", expected: "Premier point.\n\nDeuxième point."),
        Case(raw: "C'est fini point à la ligne on recommence", expected: "C'est fini.\nOn recommence"),
        Case(raw: "Tu viens point d'interrogation", expected: "Tu viens ?"),
        Case(raw: "Génial point d'exclamation", expected: "Génial !"),
        Case(raw: "Voici la liste deux points", expected: "Voici la liste :"),
        Case(raw: "Merci point virgule à demain", expected: "Merci ; à demain"),
        Case(raw: "Attends points de suspension", expected: "Attends…"),
        Case(raw: "Il a dit ouvrez les guillemets oui fermez les guillemets.", expected: "Il a dit « oui »."),
        Case(raw: "Le projet ouvrez la parenthèse en retard fermez la parenthèse.", expected: "Le projet (en retard)."),
        Case(raw: "Courses nouvelle puce lait nouvelle puce pain", expected: "Courses\n- lait\n- pain"),
        Case(raw: "Courses, à la ligne, tiret lait, à la ligne, tiret pain", expected: "Courses\n- lait\n- pain"),
        // Two sentences before the command: "efface ça" removes only the last, "efface tout" removes all.
        Case(raw: "Premier essai. Deuxième essai. Efface ça. Bonjour.", expected: "Premier essai. Bonjour."),
        Case(raw: "Ok, efface ça.", expected: ""),
        Case(raw: "Premier essai. Deuxième essai. Efface tout. Bonjour.", expected: "Bonjour."),
        Case(raw: "Nouveau paragraphe", expected: ""),
        Case(raw: "À la ligne", expected: ""),
        Case(raw: "Hello new line how are you", expected: "Hello\nHow are you"),
        Case(raw: "First item new paragraph second item", expected: "First item\n\nSecond item"),
        Case(raw: "Are you coming question mark", expected: "Are you coming?"),
        Case(raw: "Wow exclamation mark", expected: "Wow!"),
        Case(raw: "He said open quotes hello close quotes", expected: "He said \"hello\""),
        Case(raw: "First try. Second try. Scratch that. Hi.", expected: "First try. Hi."),
        Case(raw: "Le projet open paren en retard close paren.", expected: "Le projet (en retard)."),
        Case(raw: "Courses bullet point milk new bullet bread", expected: "Courses\n- milk\n- bread"),
        Case(raw: "Bonjour retour à la ligne merci", expected: "Bonjour\nMerci"),
        Case(raw: "Bonjour nouvelle ligne merci", expected: "Bonjour\nMerci"),
        Case(raw: "Premier essai. Deuxième essai. Supprime ça. Bonjour.", expected: "Premier essai. Bonjour."),
        Case(raw: "Premier essai. Deuxième essai. Annule ça. Bonjour.", expected: "Premier essai. Bonjour."),
        Case(raw: "Premier essai. Deuxième essai. Annule tout. Bonjour.", expected: "Bonjour."),
        Case(raw: "Premier essai. Deuxième essai. Tout effacer. Bonjour.", expected: "Bonjour."),
        Case(raw: "First try. Second try. Delete that. Hi.", expected: "First try. Hi."),
        Case(raw: "First try. Second try. Delete everything. Hi.", expected: "Hi."),
        Case(raw: "First try. Second try. Clear everything. Hi.", expected: "Hi."),
    ]

    /// "Appuie sur Entrée" at the very end: the text goes out, the command is not written.
    static let send: [Case] = [
        Case(raw: "On se voit demain, appuie sur entrée.", expected: "On se voit demain", pressReturn: true),
        Case(raw: "Merci beaucoup, appuyez sur entrée", expected: "Merci beaucoup", pressReturn: true),
        Case(raw: "C'est noté. Appuie sur Entrée.", expected: "C'est noté.", pressReturn: true),
        Case(raw: "See you tomorrow press enter", expected: "See you tomorrow", pressReturn: true),
        Case(raw: "Thanks a lot, hit enter.", expected: "Thanks a lot", pressReturn: true),
    ]

    static let cleanup: [Case] = [
        Case(raw: "Euh je pense que euh c'est bon.", expected: "Je pense que c'est bon."),
        Case(raw: "Je je pense que c'est c'est bon.", expected: "Je pense que c'est bon."),
        Case(raw: "C'est c'est c'est bon.", expected: "C'est bon."),
        Case(raw: "Je pense que que oui.", expected: "Je pense que oui."),
        Case(raw: "Hum, je sais pas.", expected: "Je sais pas."),
        Case(raw: "Um I think uh it works.", expected: "I think it works."),
        Case(raw: "Uh, well, okay.", expected: "Well, okay."),
        Case(raw: "Euh.", expected: ""),
        Case(raw: "Euh, euh.", expected: ""),
        .same("Euh je pense que euh c'est bon.", options: DictationOptions(cleanup: false)),
        .same("Je je pense.", options: DictationOptions(cleanup: false)),
    ]

    /// Voice commands off: they are written as spoken.
    static let commandsOff: [Case] = [
        .same("Bonjour, à la ligne, merci.", options: DictationOptions(voiceCommands: false)),
        .same("Tu viens point d'interrogation", options: DictationOptions(voiceCommands: false)),
        .same("Merci, appuie sur entrée.", options: DictationOptions(voiceCommands: false)),
    ]

    static let vocabulary: [Case] = {
        let cta = [Replacement(original: "sitié", with: "CTA")]
        return [
            Case(raw: "Le sitié est prêt.", expected: "Le CTA est prêt.", vocabulary: cta),
            Case(raw: "LE SITIÉ EST PRÊT.", expected: "LE CTA EST PRÊT.", vocabulary: cta),
            Case(raw: "Les sitiés sont prêts.", expected: "Les sitiés sont prêts.", vocabulary: cta),
            Case(raw: "Le xsitié est prêt.", expected: "Le xsitié est prêt.", vocabulary: cta),
            Case(
                raw: "J'utilise super whisper.", expected: "J'utilise Superwhisper.",
                vocabulary: [Replacement(original: "super", with: "génial"), Replacement(original: "super whisper", with: "Superwhisper")]),
            Case(raw: "Le prix est fixé.", expected: "Le $5 \\1 est fixé.", vocabulary: [Replacement(original: "prix", with: "$5 \\1")]),
            Case(
                raw: "Merci, ma signature", expected: "Merci, Paul\nÉquipe Plume",
                vocabulary: [Replacement(original: "ma signature", with: "Paul\nÉquipe Plume")]),
        ]
    }()

    static let styles: [Case] = [
        Case(raw: "Bonjour à tous. Merci pour votre message.", expected: "Bonjour à tous. Merci pour votre message", options: DictationOptions(style: .message)),
        Case(raw: "Merci, à bientôt.", expected: "Merci, à bientôt", options: DictationOptions(style: .message)),
        .same("Tu viens ?", options: DictationOptions(style: .message)),
        Case(raw: "Bonjour à tous. Merci pour votre message.", expected: "bonjour à tous. merci pour votre message", options: DictationOptions(style: .casual)),
        Case(raw: "Bonjour Paul, merci pour ton aide. À demain.", expected: "bonjour Paul, merci pour ton aide. à demain", options: DictationOptions(style: .casual)),
        Case(raw: "Génial !", expected: "génial !", options: DictationOptions(style: .casual)),
        Case(raw: "I think the URL is fine.", expected: "I think the URL is fine", options: DictationOptions(style: .casual)),
        Case(raw: "URL à vérifier.", expected: "URL à vérifier", options: DictationOptions(style: .casual)),
        // A chunk written mid-dictation keeps its period: it is not the end.
        Case(raw: "Bonjour à tous. Merci pour votre message.", expected: "Bonjour à tous. Merci pour votre message.", options: DictationOptions(style: .message), final: false),
        Case(raw: "Bonjour à tous. Merci pour votre message.", expected: "bonjour à tous. merci pour votre message.", options: DictationOptions(style: .casual), final: false),
    ]

    /// Parakeet's `<unk>` markers, removed by the engine before formatting.
    static let unknownTokens: [Case] = [
        Case(raw: "Le mot <unk>ssi<unk> <unk> vient du latin.", expected: "Le mot ssi vient du latin."),
        Case(raw: "<unk>, bonjour à tous.", expected: "Bonjour à tous."),
        Case(raw: "<unk>", expected: ""),
    ]

    /// Known issues: the expected result, not today's.
    static let knownIssues: [Case] = [
        Case(raw: "Le score final est de 2 points.", expected: "Le score final est de 2 points.", knownIssue: "'2 points' at the end of a sentence becomes ':'"),
        Case(raw: "On a marqué deux points.", expected: "On a marqué deux points.", knownIssue: "'deux points' at the end of a sentence becomes ':'"),
        Case(
            raw: "N'oublie pas d'appuyer sur entrée.", expected: "N'oublie pas d'appuyer sur entrée.",
            knownIssue: "cuts the sentence and presses Enter", knownIssueOnReturn: true),
        Case(
            raw: "Don't forget to press enter.", expected: "Don't forget to press enter.",
            knownIssue: "cuts the sentence and presses Enter", knownIssueOnReturn: true),
        Case(
            raw: "Il a dit ouvrez les guillemets bonjour fermez les guillemets et il est parti.",
            expected: "Il a dit « bonjour » et il est parti.", knownIssue: "the closing quote sticks to the next word"),
        Case(
            raw: "Le projet ouvrez la parenthèse en retard fermez la parenthèse avance",
            expected: "Le projet (en retard) avance", knownIssue: "the closing parenthesis sticks to the next word"),
        Case(raw: "Je ne sais pas... peut-être.", expected: "Je ne sais pas... peut-être.", knownIssue: "'...' becomes '..'"),
        Case(raw: "Attends...", expected: "Attends...", knownIssue: "'...' becomes '..'"),
        Case(
            raw: "Merci, ma signature", expected: "merci, Paul\nÉquipe Plume", options: DictationOptions(style: .casual),
            vocabulary: [Replacement(original: "ma signature", with: "Paul\nÉquipe Plume")],
            knownIssue: "the casual style lowercases the lines of an excerpt"),
    ]

    /// From raw model output, as `SpeechEngine.transcribe` hands it on, to pasted text.
    private func formatted(_ c: Case) -> DictationResult {
        Pipeline.format(
            SpeechEngine.removingUnknownTokens(c.raw), options: c.options, replacements: c.vocabulary, final: c.final)
    }

    private func check(_ c: Case) {
        let result = formatted(c)
        #expect(result.text == c.expected)
        #expect(result.pressReturn == c.pressReturn)
    }

    @Test(arguments: ordinary + lookalikes) func anOrdinarySentenceDoesNotChange(_ c: Case) { check(c) }
    @Test(arguments: commands) func voiceCommandsRun(_ c: Case) { check(c) }
    @Test(arguments: send) func pressEnterSendsTheText(_ c: Case) { check(c) }
    @Test(arguments: cleanup) func cleanupRemovesHesitations(_ c: Case) { check(c) }
    @Test(arguments: commandsOff) func withoutVoiceCommandsNothingRuns(_ c: Case) { check(c) }
    @Test(arguments: vocabulary) func vocabularyReplacesWholeWords(_ c: Case) { check(c) }
    @Test(arguments: styles) func styleFollowsTheApp(_ c: Case) { check(c) }
    @Test(arguments: unknownTokens) func unknownTokenMarkersAreRemoved(_ c: Case) { check(c) }

    @Test(arguments: knownIssues) func knownIssuesStayMarked(_ c: Case) {
        guard let issue = c.knownIssue else { return check(c) }
        let result = formatted(c)
        // Only the expectation that fails today is marked: the other keeps watching.
        withKnownIssue(Comment(rawValue: issue)) {
            #expect(result.text == c.expected)
            if c.knownIssueOnReturn { #expect(result.pressReturn == c.pressReturn) }
        }
        if !c.knownIssueOnReturn { #expect(result.pressReturn == c.pressReturn) }
    }
}
