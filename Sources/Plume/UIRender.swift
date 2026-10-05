import AppKit
import PlumeKit
import SwiftUI

/// Rendu hors écran de l'interface en PNG (`plume render <dossier>`), pour contrôler
/// l'apparence sans capture d'écran. Avec `--demo`, la fenêtre montre une bibliothèque
/// inventée et un prénom fictif : de quoi faire des captures publiables.
@MainActor
enum UIRender {
    static func run(directory: String, demo: Bool = false) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if demo { DemoLibrary.install() }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Fonts.register()

        islandStates(output)
        drawerSteps(output)

        let session = SessionController()
        session.debugSet(phase: .idle)
        let app = AppModel(session: session)
        app.refreshNow()
        if let meeting = app.library.transcripts.first(where: { $0.speakers.count > 1 }) {
            app.library.selection = meeting.id
        }
        // Les réglages en entier, sur une fenêtre très haute, pour voir toutes les sections.
        app.page = .settings
        window(
            AppShell(app: app, session: session), size: NSSize(width: 1040, height: 2500),
            name: "app-settings-entier", in: output, appearance: .darkAqua)
        for (suffix, appearance) in [("sombre", NSAppearance.Name.darkAqua), ("clair", .aqua)] {
            for page in Page.allCases {
                app.page = page
                window(
                    AppShell(app: app, session: session), size: NSSize(width: 1040, height: 680),
                    name: "app-\(page.rawValue)-\(suffix)", in: output, appearance: appearance)
            }
        }
        // Les enregistrements annulés, encore récupérables.
        app.page = .history
        app.library.filter = .cancelled
        window(
            AppShell(app: app, session: session), size: NSSize(width: 1040, height: 680),
            name: "app-history-annules-sombre", in: output, appearance: .darkAqua)
    }

    private static func islandStates(_ output: URL) {
        let session = SessionController()
        let levels: [Float] = (0..<SessionController.levelCount).map { i in
            Float(0.25 + 0.75 * abs(sin(Double(i) * 0.9) * cos(Double(i) * 0.37)))
        }
        let meeting = Transcript(id: "x", createdAt: Date(), mode: .meeting, duration: 60, engine: "", text: "", rawText: "")
        // (nom, commandes visibles, réglage de l'état)
        let states: [(String, Bool, () -> Void)] = [
            ("ile-1-debut", true, { session.debugSet(phase: .recording, elapsed: 2, levels: levels) }),
            ("ile-2-compacte", false, { session.debugSet(phase: .recording, elapsed: 21, levels: levels) }),
            (
                "ile-3-direct", false,
                {
                    session.debugSet(
                        phase: .recording, elapsed: 14, levels: levels,
                        committed: "Salut Victor, je voulais te parler du déploiement de ce matin.",
                        volatile: "On a un souci avec le webhook Shopify, il faudrait regarder les logs avant")
                }
            ),
            (
                "ile-4-reunion-survol", true,
                {
                    session.debugSet(
                        phase: .recording, mode: .meeting, elapsed: 754, levels: levels,
                        committed: "Oui, on reste sur le budget prévu au départ.",
                        volatile: "Et pour la livraison, on vise fin octobre", systemActive: true)
                }
            ),
            ("ile-5-traitement", false, { session.debugSet(phase: .processing("Transcription")) }),
            ("ile-6-colle", false, { session.debugSet(phase: .done("Collé")) }),
            (
                "ile-7-reunion-finie", false,
                { session.debugSet(phase: .done("Réunion enregistrée"), mode: .meeting, transcript: meeting) }
            ),
            ("ile-8-erreur", false, { session.debugSet(phase: .failed("Rien entendu")) }),
            ("ile-9-pause", true, { session.debugSet(phase: .recording, mode: .meeting, elapsed: 312, paused: true) }),
            ("ile-10-appel-detecte", false, { session.debugSet(phase: .suggestion("Zoom")) }),
            (
                "ile-11-consigne", false,
                { session.debugSet(phase: .recording, intent: .transform, elapsed: 2, levels: levels) }
            ),
            ("ile-12-mise-au-propre", false, { session.debugSet(phase: .processing("Mise au propre")) }),
            (
                "ile-13-micro-muet", false,
                { session.debugSet(phase: .recording, elapsed: 24, quietMic: true, levels: [Float](repeating: 0, count: SessionController.levelCount)) }
            ),
        ]
        let geometries: [(String, NotchGeometry)] = [
            ("encoche", NotchGeometry(notchWidth: 185, topHeight: 32)),
            ("ecran-externe", NotchGeometry(notchWidth: 0, topHeight: 25)),
        ]
        for (name, controls, configure) in states {
            configure()
            for (suffix, geometry) in geometries {
                let model = IslandModel()
                model.shown = true
                model.geometry = geometry
                model.pinnedControls = controls
                let view = IslandView(session: session, model: model)
                    .frame(width: 620, height: 230)
                    .background(FakeScreenTop(geometry: geometry))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                write(renderer.nsImage, to: output.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }

    /// Quatre étapes de l'ouverture du tiroir au survol, côte à côte.
    private static func drawerSteps(_ output: URL) {
        let session = SessionController()
        let levels: [Float] = (0..<SessionController.levelCount).map { i in
            Float(0.25 + 0.75 * abs(sin(Double(i) * 0.9) * cos(Double(i) * 0.37)))
        }
        session.debugSet(phase: .recording, elapsed: 21, levels: levels)
        let geometry = NotchGeometry(notchWidth: 185, topHeight: 32)
        let steps: [CGFloat] = [0, 0.3, 0.65, 1]
        let strip = HStack(spacing: 0) {
            ForEach(steps, id: \.self) { fraction in
                let model = IslandModel()
                let _ = {
                    model.shown = true
                    model.geometry = geometry
                    model.pinnedControls = true
                    model.openFraction = fraction
                }()
                IslandView(session: session, model: model)
                    .frame(width: 420, height: 130)
                    .background(FakeScreenTop(geometry: geometry))
            }
        }
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        write(renderer.nsImage, to: output.appendingPathComponent("ile-tiroir-etapes.png"))
    }

    /// Rend une vraie fenêtre AppKit hors écran.
    private static func window<V: View>(
        _ view: V, size: NSSize, name: String, in output: URL, appearance: NSAppearance.Name
    ) {
        let host = NSHostingController(rootView: view)
        let window = UnconstrainedWindow(contentViewController: host)
        window.appearance = NSAppearance(named: appearance)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        guard let frame = window.contentView?.superview ?? window.contentView else { return }
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }

    private static func write(_ image: NSImage?, to url: URL) {
        guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}

/// Fenêtre de rendu que le système ne ramène pas aux dimensions de l'écran.
private final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Haut d'écran factice pour les maquettes : un fond, la barre de menus et l'encoche.
private struct FakeScreenTop: View {
    var geometry: NotchGeometry

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.45, blue: 0.62), Color(red: 0.78, green: 0.70, blue: 0.72)],
                startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.28)).frame(height: geometry.topHeight)
            if geometry.hasNotch {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(Color.black)
                    .frame(width: geometry.notchWidth, height: geometry.topHeight)
            }
        }
    }
}

/// Bibliothèque inventée pour les captures (`plume render <dossier> --demo`) : quelques
/// semaines de dictées et une réunion à trois, dans un dossier temporaire.
@MainActor
enum DemoLibrary {
    static func install() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-demo-\(UUID().uuidString)")
        setenv("PLUME_LIBRARY", root.path, 1)
        setenv("PLUME_FIRST_NAME", "Léa", 1)
        // Vocabulaire et règles inventés eux aussi : rien du vrai dossier Application Support.
        setenv("PLUME_SUPPORT", root.appendingPathComponent("support").path, 1)
        ReplacementStore.save([
            Replacement(original: "super whisper", with: "Superwhisper"),
            Replacement(original: "ma signature", with: "Léa Martin\nDirectrice artistique · studio Brume\n06 12 34 56 78"),
            Replacement(original: "sitié", with: "CTA"),
        ])
        AppRuleStore.save([
            AppRule(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", style: .message, pressReturn: true),
            AppRule(bundleID: "com.apple.mail", name: "Mail", style: .standard, polish: true, instructions: "vouvoie, reste chaleureuse"),
            AppRule(bundleID: "com.apple.Terminal", name: "Terminal", style: .casual, typeText: true),
            AppRule(bundleID: "*", name: "Toutes les autres applications"),
        ])
        let store = TranscriptStore(root: root)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let sentences = [
            "Penser à envoyer le devis à l'agence avant vendredi.",
            "Idée pour la newsletter : un récap des nouveautés du mois, court et visuel.",
            "Réponds à Marc que la maquette est validée, on part sur la version deux.",
            "Liste de courses : pâtes, tomates, basilic, parmesan et du café.",
            "Le bug de connexion vient du jeton expiré, il faut le rafraîchir au démarrage.",
            "Merci pour ton retour, je regarde ça demain matin et je te dis.",
            "Pour l'article de blog, commencer par une anecdote plutôt que par les chiffres.",
            "Rappeler le garage pour le contrôle technique.",
        ]
        var generator = SystemRandomNumberGenerator()
        // Près d'un an d'activité, de plus en plus régulière.
        for day in stride(from: 320, through: 1, by: -1) {
            let chance = day < 30 ? 0.9 : day < 120 ? 0.6 : 0.3
            guard Double.random(in: 0..<1, using: &generator) < chance else { continue }
            let count = day < 14 ? 4 : Int.random(in: 1...3, using: &generator)
            for n in 0..<count {
                let date = calendar.date(byAdding: .minute, value: 9 * 60 + n * 95, to: calendar.date(byAdding: .day, value: -day, to: today)!)!
                let text = (0..<Int.random(in: 3...12, using: &generator)).map { _ in sentences.randomElement()! }.joined(separator: " ")
                save(store, at: date, text: text)
            }
        }
        // Aujourd'hui : les dictées visibles en tête de l'historique.
        let recent: [(Int, String, String?)] = [
            (9 * 60 + 12, "Bonjour à tous, petit point sur le lancement : la page est en ligne et les premiers retours sont très bons.", "Slack"),
            (10 * 60 + 47, "Réponds à Marc que la maquette est validée, on part sur la version deux avec le bouton plus visible.", "Mail"),
            (14 * 60 + 5, "Idée pour la newsletter : un récap des nouveautés du mois, court et visuel, avec une capture par nouveauté.", "Notion"),
            (16 * 60 + 38, "Le bug de connexion vient du jeton expiré : il faut le rafraîchir au démarrage de l'app, pas seulement à la connexion.", "Cursor"),
        ]
        let meetingStart = calendar.date(byAdding: .minute, value: 11 * 60 + 30, to: today)!
        let lines: [(String, AudioChannel, String)] = [
            ("Inès", .system, "Bon, on fait le point sur le lancement de la nouvelle version ?"),
            (tr("Moi"), .mic, "Oui. La page est prête, il reste les captures et le texte de l'annonce."),
            ("Thomas", .system, "Je peux m'occuper des captures cet après-midi, il me faut juste la dernière version."),
            (tr("Moi"), .mic, "Parfait, je te l'envoie après la réunion."),
            ("Inès", .system, "Pour l'annonce, on vise jeudi matin ? C'est là qu'on a le plus d'ouvertures."),
            ("Thomas", .system, "Jeudi ça me va. On prévoit aussi un message pour les anciens utilisateurs ?"),
            (tr("Moi"), .mic, "Bonne idée, un mail court avec les trois nouveautés principales et un lien vers la page."),
            ("Inès", .system, "Je le rédige demain et je vous le partage avant midi."),
        ]
        var segments: [Segment] = []
        var clock = 1.0
        for (i, line) in lines.enumerated() {
            let length = Double(line.2.split(separator: " ").count) * 0.38
            segments.append(Segment(id: i, speaker: line.0, channel: line.1, start: clock, end: clock + length, text: line.2))
            clock += length + 1.2
        }
        try? store.save(
            Transcript(
                id: store.makeID(for: meetingStart), createdAt: meetingStart, mode: .meeting, duration: 1_472, engine: "demo",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments, speakers: [tr("Moi"), "Inès", "Thomas"],
                title: "Lancement de la nouvelle version",
                summary: """
                    ## Points clés
                    - La page de lancement est prête ; il reste les captures d'écran et le texte de l'annonce.
                    - L'annonce est visée jeudi matin, moment où les ouvertures sont les plus nombreuses.
                    - Un mail court préviendra les anciens utilisateurs, avec les trois nouveautés principales.

                    ## Décisions
                    - Annonce jeudi matin.
                    - Mail aux anciens utilisateurs, avec un lien vers la page.

                    ## Actions
                    - **Thomas** : les captures, cet après-midi.
                    - **\(tr("Moi"))** : envoyer la dernière version à Thomas après la réunion.
                    - **Inès** : rédiger le mail demain et le partager avant midi.
                    """))
        for (minutes, text, app) in recent {
            save(store, at: calendar.date(byAdding: .minute, value: minutes, to: today)!, text: text, app: app)
        }
        // Deux enregistrements annulés par erreur, dont une réunion pas encore transcrite.
        let cancelled = CancelledStore(library: root)
        let tone = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 16_000)) * 0.2 }
        let dictationStart = calendar.date(byAdding: .minute, value: 17 * 60 + 2, to: today)!
        try? cancelled.keep(
            CancelledRecording(
                id: store.makeID(for: dictationStart), createdAt: dictationStart, cancelledAt: dictationStart.addingTimeInterval(14),
                mode: .dictation, duration: 14, app: "Mail",
                text: "Merci pour l'invitation, je serai là jeudi. Je t'envoie la présentation ce soir.",
                rawText: "merci pour l'invitation je serai là jeudi je t'envoie la présentation ce soir"),
            mic: tone)
        let meetingCancel = calendar.date(byAdding: .minute, value: 15 * 60, to: today)!
        try? cancelled.keep(
            CancelledRecording(
                id: store.makeID(for: meetingCancel), createdAt: meetingCancel, cancelledAt: meetingCancel.addingTimeInterval(1_260),
                mode: .meeting, duration: 1_260, app: "Zoom"),
            mic: tone, system: (samples: tone, offset: 0))
    }

    private static func save(_ store: TranscriptStore, at date: Date, text: String, app: String? = nil) {
        let words = text.split(separator: " ").count
        try? store.save(
            Transcript(
                id: store.makeID(for: date), createdAt: date, mode: .dictation, duration: Double(words) / 2.4, engine: "demo",
                text: text, rawText: text.lowercased(), app: app))
    }
}
