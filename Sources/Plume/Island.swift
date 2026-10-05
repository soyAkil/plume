import AppKit
import PlumeKit
import SwiftUI

enum Theme {
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.52)
    static let recording = Color(red: 1.0, green: 0.33, blue: 0.29)
    /// Pas de couleur d'accent : le mode réunion s'allume en blanc.
    static let meeting = Color.white
    static let success = Color(red: 0.36, green: 0.86, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.3)
    /// Micro qui ne capte rien : un bleu calme, pas une alerte.
    static let quiet = Color(red: 0.55, green: 0.72, blue: 1.0)

    /// Couleurs des interlocuteurs dans l'historique.
    static let speakers: [Color] = [
        Color(red: 0.42, green: 0.62, blue: 1.0),
        Color(red: 0.98, green: 0.58, blue: 0.36),
        Color(red: 0.42, green: 0.80, blue: 0.62),
        Color(red: 0.80, green: 0.56, blue: 0.96),
        Color(red: 0.95, green: 0.74, blue: 0.32),
        Color(red: 0.94, green: 0.48, blue: 0.62),
    ]
}

/// Dimensions de l'encoche de l'écran, ou d'une encoche fictive sur un écran qui n'en a pas.
struct NotchGeometry: Equatable {
    /// Largeur de l'encoche physique (0 sans encoche).
    var notchWidth: CGFloat
    /// Hauteur de la barre du haut : celle de l'encoche, sinon celle de la barre de menus.
    var topHeight: CGFloat

    var hasNotch: Bool { notchWidth > 0 }

    static let fallback = NotchGeometry(notchWidth: 0, topHeight: 30)

    init(notchWidth: CGFloat, topHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.topHeight = topHeight
    }

    init(screen: NSScreen) {
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, screen.frame.width - left.width - right.width)
            topHeight = inset
        } else {
            notchWidth = 0
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            topHeight = max(28, min(menuBar, 40))
        }
    }

    static let earWidth: CGFloat = 82
    static let flare: CGFloat = 8

    /// Largeur du corps noir quand seules les « oreilles » dépassent de l'encoche.
    var compactWidth: CGFloat { hasNotch ? notchWidth + 2 * Self.earWidth : 204 }
    /// Largeur au repos : exactement l'encoche, donc invisible.
    var restWidth: CGFloat { hasNotch ? notchWidth : 120 }
    var expandedWidth: CGFloat { max(compactWidth, 448) }
}

/// Silhouette de l'île : collée au bord haut de l'écran, avec des congés concaves qui la font
/// naître de l'encoche comme une goutte, et des coins bas arrondis.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tr = min(topRadius, h / 2, w / 4)
        let br = min(bottomRadius, max(0, h - tr), w / 4)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))
        path.addLine(to: CGPoint(x: tr, y: h - br))
        path.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))
        path.addLine(to: CGPoint(x: w - tr - br, y: h))
        path.addQuadCurve(to: CGPoint(x: w - tr, y: h - br), control: CGPoint(x: w - tr, y: h))
        path.addLine(to: CGPoint(x: w - tr, y: tr))
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tr, y: 0))
        path.closeSubpath()
        return path
    }
}

@MainActor
final class IslandModel: ObservableObject {
    /// Piloté par le contrôleur, une fois la fenêtre à l'écran, pour que la sortie soit animée.
    @Published var shown = false
    @Published var hovering = false
    @Published var geometry = NotchGeometry.fallback
    /// Force l'affichage des commandes (rendu des maquettes).
    @Published var pinnedControls = false
    /// Taille actuelle de l'île, congés compris : le contrôleur s'en sert pour savoir si la
    /// souris la survole.
    var size = CGSize.zero
    /// Rendu hors écran d'une étape de l'ouverture du tiroir (0 : fermé, 1 : ouvert), pour en
    /// contrôler le mouvement image par image.
    var openFraction: CGFloat = 1
}

/// Apparition et disparition du contenu de l'île : fondu, léger flou, légère mise à l'échelle.
private struct BlurFade: ViewModifier {
    var hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden ? 7 : 0)
            .scaleEffect(hidden ? 0.95 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(hidden: true), identity: BlurFade(hidden: false))
    }
}

/// L'île : ce qui sort de l'encoche pendant qu'on parle.
struct IslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject var model: IslandModel
    var onOpen: (Transcript) -> Void = { _ in }

    private let settings = PlumeSettings.shared
    private var geometry: NotchGeometry { model.geometry }

    // MARK: Ce qui est affiché

    private var phase: SessionController.Phase { session.displayPhase }
    private var recording: Bool { phase == .recording }

    private var liveText: (committed: String, volatile: String)? {
        guard recording, settings.liveTranscript else { return nil }
        let committed = session.liveCommitted
        let volatile = session.liveVolatile
        guard !(committed.isEmpty && volatile.isEmpty) else { return nil }
        // On ne montre que la fin : ce qui vient d'être dit.
        let budget = 150
        if volatile.count >= budget { return ("", "…" + Self.tail(volatile, budget)) }
        let room = budget - volatile.count
        let head = committed.count > room ? "…" + Self.tail(committed, room) : committed
        return (head, volatile)
    }

    /// Les `count` derniers caractères, coupés proprement au début d'un mot.
    static func tail(_ text: String, _ count: Int) -> String {
        guard text.count > count else { return text }
        let suffix = text.suffix(count)
        if let space = suffix.firstIndex(of: " ") {
            return String(suffix[suffix.index(after: space)...])
        }
        return String(suffix)
    }

    /// Les commandes (dictée / réunion, annuler, terminer) apparaissent au survol, et d'office
    /// pendant les premières secondes pour pouvoir passer en réunion tout de suite.
    private var showsControls: Bool {
        guard recording else { return false }
        if model.hovering || model.pinnedControls { return true }
        return settings.modeSwitchAtStart && session.elapsed < 6
    }

    /// Message affiché sous l'encoche quand il ne tient pas dans une oreille.
    private var statusLine: (symbol: String?, tint: Color, text: String)? {
        switch phase {
        case .processing(let label):
            switch session.modelStatus {
            case .loading(let fraction?) where fraction < 1:
                return (nil, .white, tr("Téléchargement du modèle") + " \(Int(fraction * 100)) %")
            case .loading:
                return (nil, .white, tr("Chargement du modèle…"))
            default:
                return session.mode == .meeting || label != tr("Transcription") ? (nil, .white, label + "…") : nil
            }
        // Un message court (« Collé », « Rien entendu ») tient dans l'oreille droite ; seul un
        // message long ouvre une ligne sous l'encoche. La coche ou l'alerte est à gauche.
        case .done(let label), .failed(let label):
            return earLabel == nil ? (nil, .white, label) : nil
        case .suggestion(let app):
            return (nil, .white, "\(app) " + tr("utilise le micro"))
        case .recording:
            if session.intent == .transform, session.elapsed < 4 {
                return (nil, .white, session.hasSelection ? tr("Dicte ce qu'il faut faire du texte sélectionné") : tr("Dicte ce qu'il faut écrire"))
            }
            return nil
        default:
            return nil
        }
    }

    /// Message assez court pour s'écrire à hauteur d'encoche, à droite.
    private var earLabel: String? {
        switch phase {
        case .done(let label), .failed(let label): return label.count <= 14 ? label : nil
        default: return nil
        }
    }

    private static let labelFont: NSFont =
        NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "Geist"]), size: 13) ?? NSFont.systemFont(ofSize: 13)

    /// Largeur qu'il faut à l'île pour loger le message court dans son oreille.
    private var earLabelWidth: CGFloat {
        guard let label = earLabel else { return 0 }
        let text = ceil((label as NSString).size(withAttributes: [.font: Self.labelFont]).width) + 4
        // Avec encoche, les deux oreilles ont la même largeur ; sans, le texte suit l'icône.
        return geometry.hasNotch ? geometry.notchWidth + 2 * (text + 18 + 6) : text + 16 + 2 * 18 + 22
    }

    /// Ce que contient le tiroir qui descend sous l'encoche.
    private struct Drawer: Equatable {
        enum Action: Equatable {
            case openTranscript
            case startMeeting
        }

        var status: String?
        /// Bouton à droite de la ligne d'état : « Ouvrir », « Enregistrer ».
        var action: Action?
        var committed = ""
        var volatile = ""
        var controls = false
        var mode: RecordingMode = .dictation
        var paused = false

        var hasText: Bool { !(committed.isEmpty && volatile.isEmpty) }
        var isEmpty: Bool { status == nil && !hasText && !controls }
    }

    private var drawer: Drawer {
        var drawer = Drawer(mode: session.mode, paused: session.paused)
        drawer.status = statusLine?.text
        if case .done = phase, session.mode == .meeting, session.lastTranscript != nil { drawer.action = .openTranscript }
        if case .suggestion = phase { drawer.action = .startMeeting }
        if let live = liveText {
            drawer.committed = live.committed
            drawer.volatile = live.volatile
        }
        drawer.controls = showsControls
        return drawer
    }

    /// Dernier contenu non vide : il reste dessiné pendant que le tiroir se referme, au lieu de
    /// disparaître d'un coup.
    @State private var retained = Drawer()
    /// Valeur de `model.shown` au rendu précédent, pour reconnaître une sortie ou une rentrée.
    @State private var wasShown = false

    /// Tout ce dont dépend la silhouette de l'île.
    private struct Motion: Equatable {
        var shown: Bool
        var width: CGFloat
        var height: CGFloat
        var phase: Int
    }

    private static let rowSpacing: CGFloat = 11
    private static let statusHeight: CGFloat = 26
    private static let controlsHeight: CGFloat = 30
    private static let textFont: NSFont =
        NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "Geist"]), size: 14) ?? NSFont.systemFont(ofSize: 14)
    private static let lineSpacing: CGFloat = 3.5

    private var drawerTop: CGFloat { geometry.hasNotch ? 8 : 5 }
    private static let drawerBottom: CGFloat = 15

    /// Hauteur du texte en direct, trois lignes au plus, calculée d'avance pour que la
    /// silhouette et son contenu s'animent ensemble.
    private func textHeight(_ drawer: Drawer, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Self.lineSpacing
        let text = NSAttributedString(
            string: [drawer.committed, drawer.volatile].filter { !$0.isEmpty }.joined(separator: " "),
            attributes: [.font: Self.textFont, .paragraphStyle: style])
        let bounds = text.boundingRect(
            with: NSSize(width: width - 40, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let line = ceil(Self.textFont.ascender - Self.textFont.descender + Self.textFont.leading)
        return min(ceil(bounds.height), line * 3 + Self.lineSpacing * 2)
    }

    private func height(of drawer: Drawer, width: CGFloat) -> CGFloat {
        guard !drawer.isEmpty else { return 0 }
        var rows: [CGFloat] = []
        if drawer.status != nil { rows.append(Self.statusHeight) }
        if drawer.hasText { rows.append(textHeight(drawer, width: width)) }
        if drawer.controls { rows.append(Self.controlsHeight) }
        return drawerTop + rows.reduce(0, +) + Self.rowSpacing * CGFloat(rows.count - 1) + Self.drawerBottom
    }

    /// Largeur du corps noir, hors congés.
    private func width(for drawer: Drawer) -> CGFloat {
        guard model.shown else { return geometry.restWidth }
        if drawer.hasText { return geometry.expandedWidth }
        if drawer.controls { return max(geometry.compactWidth, 372) }
        if drawer.status != nil { return max(geometry.compactWidth, drawer.action == nil ? 320 : 372) }
        return max(geometry.compactWidth, earLabelWidth)
    }

    private var topHeight: CGFloat {
        model.shown || geometry.hasNotch ? geometry.topHeight : 0
    }

    private var phaseKind: Int {
        switch phase {
        case .idle: return 0
        case .recording: return session.paused ? 6 : 1
        case .processing: return 2
        case .done: return 3
        case .failed: return 4
        case .suggestion: return 5
        }
    }

    // MARK: Vue

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let current = drawer
        let open = model.shown && !current.isEmpty
        // Pendant la fermeture, on continue de dessiner ce qui était affiché.
        let content = current.isEmpty ? retained : current
        let width = width(for: current)
        let contentWidth = open ? width : max(width, self.width(for: content))
        let drawerHeight = height(of: content, width: contentWidth)
        let height = topHeight + (open ? drawerHeight * model.openFraction : 0)
        let shape = NotchShape(topRadius: model.shown ? NotchGeometry.flare : 4, bottomRadius: open ? 26 : 13)

        return ZStack(alignment: .top) {
            // Le tiroir est accroché au bord bas de l'île : quand elle s'allonge, il glisse de
            // derrière l'encoche vers le bas, au lieu d'apparaître sur place.
            drawerView(content)
                .frame(width: contentWidth, height: drawerHeight, alignment: .top)
                .frame(height: max(height, 0), alignment: .bottom)
                // Le tiroir n'existe que sous la barre du haut. Sans ce masque, refermé, il
                // dépassait derrière elle : sur un écran sans encoche, où il est plus large que
                // l'île, un bout de ses commandes se voyait dans l'arrondi gauche.
                .mask(alignment: .bottom) { Rectangle().frame(height: max(height - topHeight, 0)) }
                .opacity(model.shown ? 1 : 0)
            topBar
                .frame(width: width, height: topHeight)
                .background(Color.black)
                .opacity(model.shown ? 1 : 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .padding(.horizontal, NotchGeometry.flare)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.size = $0 }
        .shadow(color: .black.opacity(open ? 0.30 : 0), radius: 16, y: 7)
        .onChange(of: current, initial: true) { _, new in
            if !new.isEmpty { retained = new }
        }
        .onChange(of: model.shown) { _, new in wasShown = new }
        // Un seul ressort à la fois pour toute la silhouette, taille et position ensemble :
        // les deux bords de l'île bougent ainsi exactement de la même façon.
        .animation(motion, value: Motion(shown: model.shown, width: width, height: height, phase: phaseKind))
    }

    private var motion: Animation {
        // Sortie de l'encoche : ressort peu amorti, l'île dépasse sa taille puis se pose.
        // Rentrée : plus sèche.
        if model.shown != wasShown {
            return model.shown ? .spring(duration: 0.46, bounce: 0.36) : .spring(duration: 0.34, bounce: 0.05)
        }
        // Tiroir et changements d'état : un mouvement net, à peine rebondi.
        return .spring(duration: 0.36, bounce: 0.16)
    }

    /// « Annuler (⇧⎋) », ou « Annuler » quand aucun raccourci n'est attribué.
    private var cancelHelp: String {
        let shortcut = settings.cancelShortcut
        return shortcut.isEmpty ? tr("Annuler") : tr("Annuler") + " (" + HotkeyManager.describe(shortcut) + ")"
    }

    private func label(for action: Drawer.Action) -> String {
        switch action {
        case .openTranscript: return tr("Ouvrir")
        case .startMeeting: return tr("Enregistrer")
        }
    }

    /// Contenu du tiroir, à hauteurs fixes : rien ne bouge à l'intérieur pendant qu'il glisse.
    private func drawerView(_ drawer: Drawer) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if let status = drawer.status {
                HStack(spacing: 8) {
                    Text(status)
                        .font(UI.sans(13, .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let action = drawer.action {
                        Button {
                            switch action {
                            case .openTranscript: if let transcript = session.lastTranscript { onOpen(transcript) }
                            case .startMeeting: session.acceptSuggestion()
                            }
                        } label: {
                            Text(label(for: action))
                                .font(UI.sans(12, .medium))
                                .foregroundColor(.black.opacity(0.88))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.94)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: Self.statusHeight)
                .transition(.opacity)
            }
            if drawer.hasText {
                (Text(drawer.committed.isEmpty ? "" : drawer.committed + " ")
                    .foregroundColor(Theme.textPrimary)
                    + Text(drawer.volatile).foregroundColor(Theme.textSecondary))
                    .font(UI.sans(14))
                    .lineSpacing(Self.lineSpacing)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
            if drawer.controls {
                controls(mode: drawer.mode, paused: drawer.paused)
                    .frame(height: Self.controlsHeight)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, drawerTop)
        .padding(.bottom, Self.drawerBottom)
        .animation(.easeOut(duration: 0.18), value: drawer.controls)
        .animation(.easeOut(duration: 0.18), value: drawer.status)
    }

    /// La ligne à hauteur d'encoche : onde à gauche, durée à droite, calées sur les bords.
    private var topBar: some View {
        // Les deux conteneurs existent en permanence : ils partent du bord de l'encoche et
        // glissent vers l'extérieur avec la silhouette, du même pas à gauche et à droite.
        // Leur contenu, lui, n'existe que lorsque l'île est sortie : à la sortie suivante,
        // il ne reste rien de l'état précédent (l'ancienne coche ne réapparaît pas).
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if model.shown {
                    leftEar
                        .id(phaseKind)
                        .transition(.blurFade)
                }
            }
            .frame(minWidth: 1, alignment: .leading)
            Spacer(minLength: geometry.hasNotch ? geometry.notchWidth : 12)
            ZStack(alignment: .trailing) {
                if model.shown {
                    rightEar
                        .id(phaseKind)
                        .transition(.blurFade)
                }
            }
            .frame(minWidth: 1, alignment: .trailing)
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var leftEar: some View {
        switch phase {
        case .recording where session.paused:
            Icon(.pause, size: 13, filled: true)
                .foregroundColor(Color.white.opacity(0.8))
        case .recording:
            // Rien capté depuis un moment : l'onde s'éteint et un « zZ » bleuté se pose dessus.
            // Pas de message, c'est l'image qui le dit.
            ZStack {
                Waveform(levels: session.levels, tint: session.mode == .meeting ? Theme.meeting : .white)
                    .opacity(session.quietMic ? 0.22 : 1)
                if session.quietMic {
                    Icon(.sleep, size: 15)
                        .foregroundColor(Theme.quiet)
                        .transition(.blurFade)
                }
            }
            .animation(.easeOut(duration: 0.35), value: session.quietMic)
        case .processing:
            Spinner()
        case .done:
            Icon(.circleCheck, size: 16)
                .foregroundColor(Theme.success)
        case .failed:
            Icon(.triangleAlert, size: 15)
                .foregroundColor(Theme.warning)
        case .suggestion:
            Icon(.phoneCall, size: 14)
                .foregroundColor(Theme.success)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rightEar: some View {
        switch phase {
        case .recording:
            HStack(spacing: 5) {
                if session.mode == .meeting {
                    // S'allume quand le son de l'ordinateur porte de la parole.
                    Icon(.users, size: 12)
                        .foregroundColor(session.systemActive ? Theme.meeting : Theme.meeting.opacity(0.45))
                } else if session.intent == .transform {
                    // Une consigne pour l'IA, pas une dictée.
                    Icon(.sparkles, size: 12)
                        .foregroundColor(Theme.textPrimary)
                }
                Text(session.paused ? tr("Pause") : Format.clock(session.elapsed))
                    .font(UI.mono(12.5, .medium))
                    .foregroundColor(session.paused ? Theme.textSecondary : Theme.textPrimary)
            }
        case .done, .failed:
            if let label = earLabel {
                Text(label)
                    .font(UI.sans(13, .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
        case .suggestion:
            Text(tr("Réunion ?"))
                .font(UI.sans(13, .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
        default:
            EmptyView()
        }
    }

    private func controls(mode: RecordingMode, paused: Bool) -> some View {
        HStack(spacing: 6) {
            MeetingKey(on: mode == .meeting) { session.switchMode(to: mode == .meeting ? .dictation : .meeting) }
            Spacer(minLength: 0)
            IslandButton(help: paused ? tr("Reprendre") : tr("Mettre en pause"), action: { session.togglePause() }) {
                Icon(paused ? .play : .pause, size: 11, filled: true)
            }
            IslandButton(help: cancelHelp, action: { session.cancel() }) {
                Icon(.x, size: 12)
            }
            IslandButton(help: tr("Terminer"), prominent: true, action: { session.stop() }) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .frame(width: 9.5, height: 9.5)
            }
        }
    }
}

/// Le mode réunion s'enclenche comme une touche qui reste enfoncée : éteinte en dictée,
/// pleine et blanche tant que la réunion est captée.
private struct MeetingKey: View {
    var on: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(.users, size: 13)
                    .frame(width: 16)
                Text(tr("Réunion"))
                    .font(UI.sans(12.5, .medium))
                // Voyant : il s'allume avec le mode.
                Circle()
                    .fill(on ? Color.black : Color.white.opacity(0.22))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 1)
            }
            .foregroundColor(on ? .black : Color.white.opacity(hovering ? 0.95 : 0.72))
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? Color.white.opacity(hovering ? 1 : 0.92) : Color.white.opacity(hovering ? 0.17 : 0.11))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.25), value: on)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(on ? tr("Revenir à une simple dictée") : tr("Capter aussi le son de l'ordinateur et séparer les interlocuteurs"))
    }
}

/// Bouton carré du tiroir, aux coins de 8 comme ceux de la barre de la fenêtre.
private struct IslandButton<Label: View>: View {
    var help: String
    var prominent = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    private var fill: Color {
        if prominent { return Color.white.opacity(hovering ? 1 : 0.92) }
        return Color.white.opacity(hovering ? 0.17 : 0.11)
    }

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(prominent ? .black : Color.white.opacity(hovering ? 0.95 : 0.8))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

/// Barres qui suivent le niveau de la voix, les plus récentes à droite.
struct Waveform: View {
    var levels: [Float]
    var tint: Color = .white
    private let bars = 11

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.suffix(bars).enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: 3, height: 3.5 + CGFloat(level) * 17)
            }
        }
        .frame(height: 21)
        .animation(.linear(duration: 0.09), value: levels)
    }
}

private struct Spinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - Fenêtre

/// Vue hôte qui accepte le premier clic : l'île réagit sans que Plume prenne le focus.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Place l'île sur l'encoche de l'écran où se trouve la souris, au-dessus de la barre de
/// menus, sans jamais prendre le focus à l'application dans laquelle on dicte.
@MainActor
final class IslandController {
    private let session: SessionController
    private let model = IslandModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private var tracker: Timer?
    private var leaveDeadline: Date?
    private var enterDate: Date?
    private var screen: NSScreen?
    private var debugTurn = 0
    var onOpen: (Transcript) -> Void = { _ in }

    init(session: SessionController) {
        self.session = session
        let panel = IslandPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Au-dessus de la barre de menus, pour recouvrir la zone de l'encoche.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        self.panel = panel
        let view = IslandView(session: session, model: model) { [weak self] in self?.onOpen($0) }
        panel.contentView = FirstClickHostingView(rootView: view)
    }

    func phaseChanged(_ phase: SessionController.Phase) {
        hideWork?.cancel()
        if phase == .idle {
            model.shown = false
            // On laisse l'île se rétracter dans l'encoche avant de retirer la fenêtre.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.session.phase == .idle else { return }
                self.stopTracking()
                self.panel.orderOut(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }
        if !panel.isVisible || !model.shown {
            let mouse = NSEvent.mouseLocation
            var screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
                ?? NSScreen.screens.first
            // Diagnostic : forcer l'écran à encoche, où que soit la souris, ou alterner entre
            // les écrans à chaque sortie.
            switch ProcessInfo.processInfo.environment["PLUME_SCREEN"] {
            case "encoche":
                screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screen
            case "alterne":
                let screens = NSScreen.screens
                debugTurn += 1
                screen = screens.isEmpty ? screen : screens[debugTurn % screens.count]
            case "externe":
                screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top == 0 }) ?? screen
            default:
                break
            }
            self.screen = screen
            model.geometry = screen.map(NotchGeometry.init(screen:)) ?? .fallback
            applyFrame()
            panel.orderFrontRegardless()
            startTracking()
        }
        // Un tour de boucle plus tard : la fenêtre est à l'écran, la sortie peut s'animer.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session.phase != .idle else { return }
            self.model.shown = true
        }
    }

    /// Fenêtre de taille fixe, assez grande pour l'île déployée : elle ne bouge plus pendant
    /// l'enregistrement, ce qui évite tout à-coup dans l'animation.
    private func applyFrame() {
        guard let screen = screen ?? NSScreen.main else { return }
        let geometry = model.geometry
        let size = NSSize(width: geometry.expandedWidth + 140, height: geometry.topHeight + 280)
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width,
                height: size.height), display: true)
    }

    /// Diagnostic : ouvre ou referme le tiroir des commandes, comme le ferait un survol.
    func debugPin(_ pinned: Bool) {
        model.pinnedControls = pinned
    }

    /// Diagnostic : enregistre ce que la fenêtre de l'île dessine réellement, et sa géométrie.
    func debugSnapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        let screenFrame = screen?.frame ?? .zero
        Log.write(
            "île : fenêtre \(panel.frame), écran \(screenFrame), vue \(view.frame), île \(model.size), "
                + "encoche \(model.geometry.notchWidth)×\(model.geometry.topHeight), "
                + "zones hautes gauche \(screen?.auxiliaryTopLeftArea ?? .zero) droite \(screen?.auxiliaryTopRightArea ?? .zero)")
    }

    // MARK: Survol

    /// La fenêtre est transparente autour de l'île et ne doit rien intercepter : elle n'accepte
    /// les clics que lorsque la souris est sur l'île. On suit donc la position de la souris,
    /// ce qui donne aussi un survol fiable alors que Plume n'est jamais l'app active.
    private func startTracking() {
        tracker?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.track() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracker = timer
    }

    private func stopTracking() {
        tracker?.invalidate()
        tracker = nil
        leaveDeadline = nil
        enterDate = nil
        panel.ignoresMouseEvents = true
        if model.hovering { model.hovering = false }
    }

    private func track() {
        guard let screen, model.shown else { return }
        let size = model.size
        let island = NSRect(
            x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width,
            height: size.height
        ).insetBy(dx: -4, dy: -4)
        let inside = size.width > 0 && island.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside {
            leaveDeadline = nil
            // On n'ouvre que si la souris s'attarde : la traverser pour atteindre la barre de
            // menus ne doit rien déclencher.
            if !model.hovering {
                if let entered = enterDate {
                    if Date().timeIntervalSince(entered) >= 0.12 { model.hovering = true }
                } else {
                    enterDate = Date()
                }
            }
        } else if !model.hovering {
            enterDate = nil
        } else {
            enterDate = nil
            // Un court délai avant de refermer : la souris peut frôler le bord.
            if let deadline = leaveDeadline {
                if Date() >= deadline {
                    model.hovering = false
                    leaveDeadline = nil
                }
            } else {
                leaveDeadline = Date().addingTimeInterval(0.22)
            }
        }
    }
}
