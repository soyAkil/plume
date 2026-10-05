import AppKit
import CoreText
import SwiftUI

/// Direction artistique de la fenêtre. Le socle vient du portfolio soyakil.fr :
/// gris neutres, Geist, rayons de 8, touches de clavier dessinées, barre flottante en bas,
/// icônes au trait, un son discret sur chaque geste. Aucune couleur d'accent : ce qui doit
/// ressortir prend la couleur du texte (blanc en sombre, presque noir en clair). Une touche
/// de jeu et de mouvement : séries, records, activité, compteurs.
enum UI {
    // MARK: Couleurs

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        func make(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark, darkAlpha) : make(light, lightAlpha)
            })
    }

    // Les six gris du portfolio, du fond vers le premier plan.
    static let window = dynamic(light: 0xF7F7F7, dark: 0x0F0F0F)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x151515)
    static let raised = dynamic(light: 0xF1F1F1, dark: 0x1B1B1B)
    static let line = dynamic(light: 0xE6E6E6, dark: 0x242424)
    /// Fond de l'entrée active de la barre, contour des touches.
    static let active = dynamic(light: 0xD9D9D9, dark: 0x2F2F2F)
    static let hover = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.055)
    static let selected = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.075, darkAlpha: 0.09)
    static let text = dynamic(light: 0x292929, dark: 0xEDEDED)
    static let text2 = dynamic(light: 0x5D5D5D, dark: 0xA1A1A1)
    static let text3 = dynamic(light: 0x9E9E9E, dark: 0x6E6E6E)
    /// Texte posé sur un bouton plein (qui prend la couleur du texte).
    static let onText = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
    /// Étiquette « bêta » : un mauve, lisible sur les deux fonds.
    static let beta = dynamic(light: 0x7C4DCC, dark: 0xC9A7FF)
    /// Intensité d'activité, de la plus faible à la plus forte : du gris discret à la couleur du texte.
    static let activity: [Color] = [
        dynamic(light: 0xD0D0D0, dark: 0x3A3A3A),
        dynamic(light: 0x9E9E9E, dark: 0x6E6E6E),
        dynamic(light: 0x5D5D5D, dark: 0xA1A1A1),
        text,
    ]

    static let radius: CGFloat = 8
    static let pagePadding: CGFloat = 36
    /// Place laissée en bas de chaque page pour la barre flottante.
    static let dockClearance: CGFloat = 96

    // MARK: Mouvement

    /// Décélération franche : part vite, se pose en douceur.
    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)
    static let quick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
    static let spring = Animation.spring(duration: 0.38, bounce: 0.22)

    // MARK: Typographie

    private static var cache: [String: Font] = [:]

    private static func variable(_ family: String, _ size: CGFloat, _ weight: Font.Weight) -> Font? {
        let value: CGFloat
        switch weight {
        case .medium: value = 500
        case .semibold: value = 600
        case .bold, .heavy, .black: value = 700
        default: value = 400
        }
        let key = "\(family)-\(size)-\(value)"
        if let font = cache[key] { return font }
        let weightAxis = 2_003_265_652  // « wght »
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .variation: [weightAxis: value],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size).map({ Font($0) }) else { return nil }
        cache[key] = font
        return font
    }

    /// Geist à graisse variable ; police système si elle n'a pas pu être chargée.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard Fonts.available, let font = variable("Geist", size, weight) else { return .system(size: size, weight: weight) }
        return font
    }

    /// Geist Mono, pour les durées et les chiffres alignés.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard Fonts.available, let font = variable("Geist Mono", size, weight) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return font
    }
}

extension Bundle {
    /// Dossier `Resources/<name>` du dépôt, quand le binaire est lancé depuis `.build` plutôt
    /// que depuis l'app : on remonte depuis l'exécutable jusqu'au `Package.swift`. Aucun chemin
    /// de la machine de compilation n'est ainsi inscrit dans le binaire.
    static func repositoryResource(_ name: String) -> URL? {
        var directory = main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        while let current = directory, current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current.appendingPathComponent("Resources/\(name)", isDirectory: true)
            }
            directory = current.deletingLastPathComponent()
        }
        return nil
    }
}

/// Chargement des polices embarquées (licence libre SIL OFL).
enum Fonts {
    private(set) static var available = false

    static func register() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true)
        // Binaire lancé hors de l'app (développement) : les polices sont dans le dépôt.
        let development = Bundle.repositoryResource("Fonts")
        for directory in [bundled, development].compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for url in files where url.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            if NSFontManager.shared.availableFontFamilies.contains("Geist") { break }
        }
        available = NSFontManager.shared.availableFontFamilies.contains("Geist")
    }
}

// MARK: - Composants

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = UI.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
    }
}

/// Tout ce qui se clique s'enfonce légèrement sous le doigt.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

struct PlumeButton: View {
    enum Kind { case primary, secondary, ghost }

    var title: String?
    var icon: Glyph?
    var kind: Kind = .secondary
    var help: String?
    /// Son joué au clic ; par défaut, seuls les boutons pleins sonnent.
    var sound: Sounds.Kind?
    var action: () -> Void
    @State private var hovering = false

    private var foreground: Color {
        kind == .primary ? UI.onText : UI.text
    }

    private var background: Color {
        switch kind {
        case .primary: return UI.text.opacity(hovering ? 0.86 : 1)
        case .secondary: return hovering ? UI.selected : UI.hover
        case .ghost: return hovering ? UI.hover : .clear
        }
    }

    var body: some View {
        Button {
            if let sound = sound ?? (kind == .primary ? .click : nil) { Sounds.play(sound) }
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Icon(icon, size: 14)
                        .id(icon)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
                if let title { Text(title).font(UI.sans(13, .medium)) }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 9 : 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover {
            hovering = $0
            if $0 { Sounds.hover(.hoverButton) }
        }
        .animation(UI.quick, value: hovering)
        .help(help ?? title ?? "")
    }
}

/// Interrupteur : allumé, il prend la couleur du texte ; le curseur glisse avec un léger rebond.
struct PlumeSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            Sounds.play(configuration.isOn ? .toggleOff : .toggleOn)
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? UI.text : UI.active)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? UI.onText : Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2.5)
                }
                .animation(.spring(duration: 0.28, bounce: 0.3), value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Une touche de clavier, dessinée comme sur le portfolio.
struct Keycap: View {
    var label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(UI.sans(11, .medium))
            .foregroundStyle(UI.text)
            .padding(.horizontal, 5)
            .frame(minWidth: 20)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(UI.active, lineWidth: 1))
            // Le filet du bas, plus épais, donne l'épaisseur de la touche.
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous)
                    .fill(UI.active)
                    .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Un raccourci écrit en touches : une touche par modificateur, une pour le reste.
struct Keycaps: View {
    var shortcut: String

    private var keys: [String] {
        var keys: [String] = []
        var rest = ""
        for character in shortcut {
            if "⌃⌥⇧⌘".contains(character) { keys.append(String(character)) } else { rest.append(character) }
        }
        if !rest.isEmpty { keys.append(rest) }
        return keys
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
        }
    }
}

/// Nombre qui défile jusqu'à sa valeur quand il apparaît ou change.
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// Apparition d'un bloc : il monte de quelques points en se dévoilant, avec un retard
/// proportionnel à son rang pour un effet de cascade.
struct Rise: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(UI.ease.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func rise(_ index: Int = 0) -> some View { modifier(Rise(index: index)) }

    /// Son discret quand le pointeur arrive sur l'élément.
    func hoverSound(_ kind: Sounds.Kind) -> some View {
        onHover { if $0 { Sounds.hover(kind) } }
    }
}
