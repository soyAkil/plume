import AppKit
import PlumeKit
import SwiftUI
import UniformTypeIdentifiers

struct PageHeader<Subtitle: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(UI.sans(24, .medium)).tracking(-0.4).foregroundStyle(UI.text)
                subtitle().font(UI.sans(14)).foregroundStyle(UI.text2)
            }
            Spacer()
            trailing()
        }
    }
}

extension PageHeader where Subtitle == Text?, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: { EmptyView() })
    }
}

extension PageHeader where Subtitle == Text? {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: trailing)
    }
}

/// La fenêtre de Plume : quatre pages, et une barre flottante en bas pour passer de l'une à
/// l'autre, changer de thème et couper le son — la même que sur le portfolio.
struct AppShell: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: SessionController
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                switch app.page {
                case .home: HomePage(app: app, session: session, settings: app.settings).transition(pageTransition)
                case .history: HistoryPage(app: app, library: app.library).transition(pageTransition)
                case .vocabulary: VocabularyPage(settings: app.settings).transition(pageTransition)
                case .apps: ApplicationsPage(settings: app.settings).transition(pageTransition)
                case .settings: SettingsPage(settings: app.settings).transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(UI.ease, value: app.page)

            Dock(app: app, settings: app.settings)
                .padding(.bottom, 18)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                UpdatePill()
                StatusPill(session: session, settings: app.settings)
            }
            .padding(.top, 11)
            .padding(.trailing, 14)
        }
        .frame(minWidth: 880, minHeight: 560)
        // Changer de langue redessine toute la fenêtre : chaque texte est relu dans la table.
        .id(app.settings.language)
        .background(UI.window)
        .foregroundStyle(UI.text)
        .tracking(-0.15)
        .ignoresSafeArea()
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(UI.text, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.text.opacity(0.05)))
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(UI.quick, value: dropTargeted)
        // Un fichier audio déposé n'importe où dans la fenêtre est transcrit.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { app.importFiles([url]) }
                }
            }
            return true
        }
    }

    /// La page qui arrive monte légèrement en se dévoilant ; celle qui part s'efface.
    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }
}

// MARK: - Barre flottante

private struct Dock: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                DockItem(
                    glyph: page.glyph, label: page.title, key: "\(index + 1)", selected: app.page == page,
                    namespace: selection
                ) {
                    withAnimation(UI.spring) { app.page = page }
                }
            }
            Rectangle().fill(UI.active).frame(width: 1, height: 18).padding(.horizontal, 7)
            // Le soleil entre et sort par la gauche, la lune par la droite, comme sur le portfolio.
            DockItem(
                glyph: scheme == .dark ? .sun : .moon, label: scheme == .dark ? tr("Thème clair") : tr("Thème sombre"),
                key: "T", slide: scheme == .dark ? -1 : 1, namespace: selection
            ) {
                Sounds.play(.tab)
                settings.appearance = scheme == .dark ? "clair" : "sombre"
            }
            DockItem(
                glyph: settings.sounds ? .speakerOn : .speakerOff, label: settings.sounds ? tr("Couper le son") : tr("Activer le son"),
                key: "S", namespace: selection
            ) {
                settings.sounds.toggle()
                if settings.sounds { Sounds.play(.confirm) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.10), radius: 18, y: 8)
    }
}

/// Glissement flou d'une icône qui en remplace une autre.
private struct SlideBlur: ViewModifier {
    var offset: CGFloat
    var hidden: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: hidden ? offset : 0)
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden ? 3 : 0)
    }
}

private struct DockItem: View {
    var glyph: Glyph
    var label: String
    var key: String
    var selected = false
    /// Sens du glissement quand l'icône change (0 : simple fondu).
    var slide: CGFloat = 0
    var namespace: Namespace.ID
    var action: () -> Void
    @State private var hovering = false
    @State private var tip = false
    @State private var tipTask: DispatchWorkItem?

    private static let side: CGFloat = 40
    private static let iconSize: CGFloat = 19

    var body: some View {
        Button {
            showTip(false)
            action()
        } label: {
            ZStack {
                Icon(glyph, size: Self.iconSize)
                    .id(glyph)
                    .transition(
                        .modifier(
                            active: SlideBlur(offset: slide * Self.iconSize * 0.7, hidden: true),
                            identity: SlideBlur(offset: 0, hidden: false)))
            }
            .foregroundStyle(selected || hovering ? UI.text : UI.text2)
            // Au survol, l'icône grossit un peu, comme sur le portfolio.
            .scaleEffect(hovering && !selected ? 1.12 : 1)
            .frame(width: Self.side, height: Self.side)
            .clipped()
            .background {
                if selected {
                    // Le fond de l'entrée active glisse d'une page à l'autre.
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                        .fill(UI.active)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover)
                }
            }
            .contentShape(Rectangle())
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: glyph)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .onHover { inside in
            hovering = inside
            if inside { Sounds.hover(.hoverNav) }
            showTip(inside)
        }
        // L'étiquette et sa touche sortent au-dessus de la barre, une fois le pointeur posé.
        .overlay(alignment: .top) {
            if tip {
                HStack(spacing: 6) {
                    Text(label).font(UI.sans(12, .medium)).foregroundStyle(UI.text)
                    Keycap(key)
                }
                .padding(.leading, 9)
                .padding(.trailing, 5)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                .fixedSize()
                .offset(y: -40)
                .transition(.opacity.combined(with: .offset(y: 4)))
                .allowsHitTesting(false)
            }
        }
        .animation(UI.quick, value: hovering)
        .animation(.easeOut(duration: 0.14), value: tip)
    }

    private func showTip(_ show: Bool) {
        tipTask?.cancel()
        guard show else {
            tip = false
            return
        }
        let work = DispatchWorkItem { tip = true }
        tipTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }
}

/// Une mise à jour trouvée en arrière-plan : un bouton discret, qui ouvre le détail.
private struct UpdatePill: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        if let version = updates.pending {
            Button(action: { updates.check() }) {
                HStack(spacing: 6) {
                    Icon(.download, size: 12)
                    Text("Plume \(version) " + tr("est disponible")).font(UI.sans(12, .medium))
                }
                .foregroundStyle(UI.onText)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.text))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .hoverSound(.hoverButton)
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }
}

/// Le modèle de transcription se télécharge une seule fois, au premier lancement : on dit
/// ce qui se passe, combien ça pèse, et où ça en est.
private struct ModelCard: View {
    @ObservedObject var session: SessionController

    private var state: (title: String, detail: String, fraction: Double?, failed: Bool)? {
        switch session.modelStatus {
        case .loading(let fraction?) where fraction < 1:
            return (
                tr("Téléchargement du modèle de transcription"),
                tr("Une seule fois, environ 600 Mo. Ensuite tout se passe sur ce Mac, sans connexion."), fraction, false
            )
        case .failed(let reason):
            return (tr("Le modèle de transcription n'a pas pu être chargé"), reason, nil, true)
        default:
            return nil
        }
    }

    var body: some View {
        if let state {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.title).font(UI.sans(14, .medium))
                            Text(state.detail).font(UI.sans(13)).foregroundStyle(UI.text2).lineLimit(2)
                        }
                        Spacer()
                        if let fraction = state.fraction {
                            Text("\(Int(fraction * 100)) %").font(UI.mono(13)).foregroundStyle(UI.text2)
                        } else if state.failed {
                            PlumeButton(title: tr("Réessayer"), kind: .primary) { session.loadModel() }
                        }
                    }
                    if let fraction = state.fraction {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(UI.active)
                                Capsule().fill(UI.text).frame(width: max(4, proxy.size.width * fraction))
                            }
                        }
                        .frame(height: 4)
                        .animation(UI.ease, value: fraction)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

/// État du moteur et rappel du raccourci, en haut à droite de la fenêtre.
private struct StatusPill: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: SettingsModel

    private var state: (color: Color, text: String, ready: Bool) {
        switch session.phase {
        case .recording: return (Theme.recording, session.mode == .meeting ? tr("Réunion en cours") : tr("Dictée en cours"), false)
        case .processing: return (UI.text, tr("Transcription…"), false)
        default:
            switch session.modelStatus {
            case .loading(let fraction?) where fraction < 1: return (UI.text, tr("Modèle :") + " \(Int(fraction * 100)) %", false)
            case .loading: return (UI.text, tr("Chargement du modèle…"), false)
            case .failed: return (Theme.recording, tr("Modèle indisponible"), false)
            case .ready: return (UI.success, tr("Prêt"), true)
            }
        }
    }

    var body: some View {
        let state = state
        HStack(spacing: 7) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .shadow(color: state.color.opacity(0.7), radius: 3)
            Text(state.text).font(UI.sans(12)).foregroundStyle(UI.text2).contentTransition(.opacity)
            if state.ready, !settings.dictationShortcut.isEmpty {
                Keycaps(shortcut: HotkeyManager.describe(settings.dictationShortcut))
            }
        }
        .frame(height: 22)
        .animation(UI.quick, value: state.text)
    }
}

// MARK: - Accueil

struct HomePage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: SessionController
    @ObservedObject var settings: SettingsModel
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var firstName: String {
        // PLUME_FIRST_NAME : prénom imposé, pour les captures de démonstration.
        let name = ProcessInfo.processInfo.environment["PLUME_FIRST_NAME"] ?? NSFullUserName()
        return name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var stats: LibraryStats { app.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: firstName.isEmpty ? tr("Bonjour") : tr("Bonjour") + " \(firstName)") {
                    HStack(spacing: 6) {
                        Text(tr("Appuie sur"))
                        Keycaps(shortcut: HotkeyManager.describe(settings.dictationShortcut))
                        Text(tr("pour dicter, le texte se colle là où est ton curseur."))
                    }
                } trailing: {
                    PlumeButton(title: tr("Transcrire un fichier"), icon: .download) { app.chooseFiles() }
                }
                .padding(.bottom, 10)
                .rise(0)

                if settings.permissionsMissing {
                    PermissionsCard(settings: settings).rise(1)
                }
                ModelCard(session: session)

                HStack(spacing: 10) {
                    TodayTile(stats: stats).rise(1)
                    StreakTile(stats: stats).rise(2)
                    StatTile(
                        value: stats.timeSaved / 60, format: HomePage.span, label: tr("gagnés sur le clavier"),
                        detail: "\(HomePage.number(Double(stats.words))) " + tr("mots au total")
                    ).rise(3)
                    StatTile(
                        value: Double(stats.wordsPerMinute), format: { $0 < 1 ? "—" : HomePage.number($0) },
                        label: tr("mots par minute"), detail: tr("au clavier : 40")
                    ).rise(4)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(tr("Activité")).font(UI.sans(14, .medium))
                            Text(tr("mots dictés par jour")).font(UI.sans(13)).foregroundStyle(UI.text2)
                        }
                        ActivityHeatmap(days: stats.days)
                    }
                }
                .rise(5)

                if let latest = app.library.transcripts.first ?? session.lastTranscript {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(tr("Dernière transcription")).font(UI.sans(14, .medium))
                                Text(TranscriptStore.title(for: latest)).font(UI.sans(13)).foregroundStyle(UI.text2)
                                Spacer()
                                CopyButton(text: latest.text)
                                PlumeButton(title: tr("Ouvrir"), icon: .arrowUpRight) { app.open(latest) }
                            }
                            Text(latest.preview)
                                .font(UI.sans(14))
                                .foregroundStyle(UI.text2)
                                .lineSpacing(5)
                                .lineLimit(3)
                        }
                    }
                    .rise(6)
                }
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .onReceive(refresh) { _ in settings.refreshPermissions() }
    }

    static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = L10n.current.locale
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    /// Durée en minutes, écrite `12 min` ou `3 h 20`.
    static func span(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole < 60 { return "\(whole) min" }
        return String(format: "%d h %02d", whole / 60, whole % 60)
    }
}

/// Gabarit commun des tuiles de l'accueil : elles se soulèvent légèrement au survol, avec
/// un liseré plus clair et une note.
private struct Tile<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.card))
            .overlay(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .strokeBorder(hovering ? UI.text3 : UI.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 14, y: 6)
            .offset(y: hovering ? -2 : 0)
            .onHover {
                hovering = $0
                if $0 { Sounds.hover(.hoverCard) }
            }
            .animation(UI.spring, value: hovering)
    }
}

private struct TileFigure: View {
    var value: Double
    var format: (Double) -> String

    var body: some View {
        CountingText(value: value, format: format)
            .font(UI.sans(28, .medium))
            .tracking(-0.6)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Un chiffre clé : la valeur en grand (elle défile à l'apparition), ce qu'elle mesure, une précision.
private struct StatTile: View {
    var value: Double
    var format: (Double) -> String
    var label: String
    var detail: String
    @State private var shown: Double = 0

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: format)
                Text(label).font(UI.sans(13, .medium))
                Text(detail).font(UI.sans(12)).foregroundStyle(UI.text2).lineLimit(1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = value } }
        .onChange(of: value) { _, new in withAnimation(.easeOut(duration: 0.6)) { shown = new } }
    }
}

/// Les mots du jour, avec un anneau qui se remplit vers la meilleure journée.
private struct TodayTile: View {
    var stats: LibraryStats
    @State private var shown: Double = 0
    @State private var progress: Double = 0

    private var record: Int { stats.bestDay?.words ?? 0 }
    private var isRecord: Bool { stats.wordsToday > 0 && stats.wordsToday >= record }
    private var target: Double { record > 0 ? min(1, Double(stats.wordsToday) / Double(record)) : 0 }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: HomePage.number)
                Text(tr("mots aujourd'hui")).font(UI.sans(13, .medium)).lineLimit(1)
                Text(isRecord ? tr("Meilleure journée") : tr("record :") + " \(HomePage.number(Double(record)))")
                    .font(UI.sans(12))
                    .foregroundStyle(isRecord ? UI.text : UI.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().stroke(UI.active, lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(UI.text, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                .padding(.top, 4)
            }
        }
        .onAppear { animate() }
        .onChange(of: stats.wordsToday) { _, _ in animate() }
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.9)) { shown = Double(stats.wordsToday) }
        withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.15)) { progress = target }
    }
}

/// La série de jours consécutifs, flamme allumée quand elle est en cours.
private struct StreakTile: View {
    var stats: LibraryStats
    @State private var shown: Double = 0
    @State private var lit = false

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: HomePage.number)
                Text(stats.streak > 1 ? tr("jours d'affilée") : tr("jour d'affilée")).font(UI.sans(13, .medium)).lineLimit(1)
                Text(tr("record :") + " \(stats.bestStreak) " + tr(stats.bestStreak > 1 ? "jours" : "jour"))
                    .font(UI.sans(12))
                    .foregroundStyle(UI.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Icon(.flame, size: 24, filled: stats.streak > 0)
                    .foregroundStyle(stats.streak > 0 ? UI.text : UI.text3)
                    .shadow(color: UI.text.opacity(stats.streak > 0 ? 0.3 : 0), radius: lit ? 8 : 2)
                    .scaleEffect(lit ? 1.06 : 0.96)
                    .padding(.top, 3)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = Double(stats.streak) }
            guard stats.streak > 0 else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { lit = true }
        }
        .onChange(of: stats.streak) { _, new in withAnimation(.easeOut(duration: 0.6)) { shown = Double(new) } }
    }
}

/// Calendrier d'activité : une case par jour, d'autant plus vive que la journée a été bavarde.
private struct ActivityHeatmap: View {
    var days: [LibraryStats.Day]
    @State private var hovered: Date?
    @State private var revealed = false

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }

    /// Semaines du lundi au dimanche, la dernière pouvant être incomplète.
    private var weeks: [[LibraryStats.Day?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        var columns: [[LibraryStats.Day?]] = []
        var current: [LibraryStats.Day?] = []
        for day in days {
            let weekday = (calendar.component(.weekday, from: day.date) + 5) % 7  // lundi = 0
            if current.isEmpty, weekday > 0 { current = Array(repeating: nil, count: weekday) }
            current.append(day)
            if current.count == 7 {
                columns.append(current)
                current = []
            }
        }
        if !current.isEmpty { columns.append(current + Array(repeating: nil, count: 7 - current.count)) }
        return columns
    }

    private func color(_ words: Int, peak: Int) -> Color {
        guard words > 0 else { return UI.hover }
        let ratio = Double(words) / Double(max(peak, 1))
        let step = ratio > 0.75 ? 3 : (ratio > 0.45 ? 2 : (ratio > 0.2 ? 1 : 0))
        return UI.activity[step]
    }

    private static let cell: CGFloat = 15
    private static let gap: CGFloat = 4

    var body: some View {
        let peak = days.map(\.words).max() ?? 0
        let all = weeks
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                // On montre autant de semaines que la carte peut en contenir, les plus récentes.
                let fit = max(1, Int((proxy.size.width + Self.gap) / (Self.cell + Self.gap)))
                let columns = Array(all.suffix(fit))
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: Self.gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(day.map { color($0.words, peak: peak) } ?? Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(UI.text.opacity(hovered != nil && hovered == day?.date ? 0.7 : 0), lineWidth: 1.5)
                                    )
                                    .frame(width: Self.cell, height: Self.cell)
                                    .onHover { inside in
                                        guard let day else { return }
                                        hovered = inside ? day.date : (hovered == day.date ? nil : hovered)
                                        if inside, day.words > 0 { Sounds.hover(.hoverRow) }
                                    }
                            }
                        }
                        // Les colonnes apparaissent en cascade, de la plus ancienne à la plus récente.
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 6)
                        .animation(UI.ease.delay(Double(index) * 0.012), value: revealed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: Self.cell * 7 + Self.gap * 6)

            HStack(spacing: 6) {
                if let hovered, let day = days.first(where: { $0.date == hovered }) {
                    Text(Self.dayFormatter.string(from: day.date).capitalizedFirst)
                        .foregroundStyle(UI.text)
                    Text(day.words == 0 ? tr("rien dicté") : "\(HomePage.number(Double(day.words))) " + tr("mots"))
                } else {
                    Text(tr("Survole une case pour voir le détail d'une journée."))
                }
                Spacer()
                Text(tr("Moins"))
                ForEach(0..<4, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(UI.activity[step]).frame(width: 11, height: 11)
                }
                Text(tr("Plus"))
            }
            .font(UI.sans(12))
            .foregroundStyle(UI.text2)
            .animation(UI.quick, value: hovered)
        }
        .onAppear { revealed = true }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Bouton « Copier » qui confirme d'une coche et d'une note.
struct CopyButton: View {
    var text: String
    var prominent = false
    @State private var copied = false

    var body: some View {
        PlumeButton(
            title: copied ? tr("Copié") : tr("Copier"), icon: copied ? .check : .copy,
            kind: prominent ? .primary : .secondary, sound: .confirm
        ) {
            Paster.copy(text)
            withAnimation(UI.spring) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(UI.spring) { copied = false } }
        }
    }
}

/// Les deux autorisations indispensables, tant qu'elles ne sont pas accordées.
struct PermissionsCard: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Deux autorisations pour commencer")).font(UI.sans(14, .medium))
                PermissionRow(
                    title: tr("Microphone"), detail: tr("Pour entendre ta voix."), granted: settings.microphoneGranted,
                    action: settings.requestMicrophone)
                Rectangle().fill(UI.line).frame(height: 1)
                PermissionRow(
                    title: tr("Accessibilité"), detail: tr("Pour coller le texte dans le champ actif."),
                    granted: settings.accessibilityGranted, action: settings.requestAccessibility)
            }
        }
    }
}

struct PermissionRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.sans(14))
                Text(detail).font(UI.sans(13)).foregroundStyle(UI.text2)
            }
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Icon(.circleCheck, size: 15)
                    Text(tr("Accordée")).font(UI.sans(13, .medium))
                }
                .foregroundStyle(UI.success)
                .transition(.scale.combined(with: .opacity))
            } else {
                PlumeButton(title: tr("Autoriser"), kind: .primary, action: action)
            }
        }
        .animation(UI.spring, value: granted)
    }
}
