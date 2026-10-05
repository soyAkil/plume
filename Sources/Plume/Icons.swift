import SwiftUI

/// Les icônes de Plume : celles du portfolio (soyakil.fr), dessinées au trait. La barre du
/// portfolio utilise des icônes Lucide à 1,6 d'épaisseur, bouts ronds, plus un soleil, une
/// lune et un haut-parleur maison ; tout le reste de l'app suit la même famille.
enum Glyph: String {
    case appWindow, arrowRight, arrowUpRight, audioLines, book, check, chevronDown, circleCheck, circleX, clipboardPaste
    case copy, cornerDownLeft, download, fileAudio, fileDown, fileText, flame, folder, history, home, keyboard, layoutGrid, listChecks
    case mic, micOff, moon, pause, pencil, phoneCall, play, plus, search, sliders, smartphone, sparkles, speakerOff, speakerOn
    /// La plume de l'icône de l'app (Resources/Plume.svg) : une forme pleine, pas un trait.
    case plume
    /// « zZ » : rien ne rentre dans le micro.
    case sleep
    case sun, trash, triangleAlert, users, volume, volumeHigh, wandSparkles, x

    /// Côté de la grille dans laquelle l'icône est dessinée.
    var box: CGFloat {
        switch self {
        case .speakerOn, .speakerOff: return 17
        case .plume: return 1023
        default: return 24
        }
    }

    /// Épaisseur du trait, dans l'unité de la grille.
    var stroke: CGFloat {
        switch self {
        case .speakerOn, .speakerOff: return 1.3
        case .sun, .moon: return 1.7
        case .plume: return 0
        default: return 1.6
        }
    }

    fileprivate static let paths: [Glyph: [String]] = [
        .plume: ["M780.68 0.10692C803.342 -1.11279 819.666 8.10606 831.477 27.608C854.23 65.1814 854.592 117.558 845.303 159.384C838.923 188.116 826.23 214.949 810.885 239.809C748.828 341.176 649.684 408.888 551.348 470.861C526.004 486.98 500.581 502.961 475.073 518.813C485.28 506.935 495.603 494.787 504.972 482.241C538.538 437.284 566.9 380.989 578.558 325.726C563.422 348.807 549.211 372.032 533.377 394.84C517.738 416.936 501.016 438.243 483.266 458.683C427.57 521.851 364.768 574.674 309.882 640.099C275.781 681.344 244.821 725.087 217.263 770.961C202.195 795.998 187.448 823.184 173.322 848.754C164.113 863.792 155.905 879.896 146.485 894.977C122.941 932.823 97.5405 970.645 63.7854 1000.23C52.3604 1010.24 38.3202 1021.18 22.3991 1022.1C18.9138 1022.31 11.8344 1021.39 9.10228 1019.24C-19.6252 996.717 27.3649 955.907 43.7734 941.145C68.2032 919.169 90.0545 898.118 110.845 872.836C132.36 846.599 149.891 817.33 162.871 785.98C180.226 743.052 185.18 702.015 176.119 656.57C172.623 639.027 168.374 621.772 166.367 604.028C157.956 529.663 191.494 452.607 230.335 390.91C303.561 274.596 411.485 189.482 535.183 131.479C554.979 122.24 574.989 113.467 595.195 105.166C621.322 94.3057 643.408 85.6814 668.445 71.9119C683.832 63.2968 698.668 53.7289 712.867 43.2634C729.534 30.7687 746.569 13.8042 764.993 4.69614C769.181 2.62533 776.125 1.1209 780.68 0.10692Z", "M847.263 215.896C849.4 221.934 852.032 242.189 852.865 249.126C859.796 306.55 854.206 364.281 830.657 417.579C790.643 508.146 715.856 561.662 626.992 597.598C668.47 598.614 719.891 587.587 757.07 568.954C754.076 573.847 750.304 582.401 747.23 588.003C739.981 601.358 731.574 614.051 722.107 625.936C678.04 682.194 613.583 718.669 542.219 723.078C510.875 725.013 481.074 723.88 450.024 726.09C403.954 729.366 347.64 743.431 306.138 763.986C276.535 779.146 252.471 793.676 226.994 815.677C220.499 821.285 213.901 826.324 208.277 832.87C248.902 750.533 332.3 653.177 403.856 595.412C438.359 567.565 483.486 538.7 521.982 516.37C550.95 499.574 581.59 483.373 610.791 466.501C679.081 427.042 741.854 381.059 790.606 318.229C809.018 294.503 824.326 267.589 837.288 240.528C841.005 232.767 843.454 223.886 847.005 216.417L847.263 215.896Z"],
        .appWindow: ["M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2Z", "M10 4v4", "M2 8h20", "M6 4v4"],
        .arrowRight: ["M5 12h14", "m12 5 7 7-7 7"],
        .clipboardPaste: ["M11 14h10", "M16 4h2a2 2 0 0 1 2 2v1.344", "m17 18 4-4-4-4", "M8 4H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 1.793-1.113", "M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1 -1 1h-6a1 1 0 0 1 -1 -1v-2a1 1 0 0 1 1 -1Z"],
        .cornerDownLeft: ["M20 4v7a4 4 0 0 1-4 4H4", "m9 10-5 5 5 5"],
        .fileDown: ["M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z", "M14 2v5a1 1 0 0 0 1 1h5", "M12 18v-6", "m9 15 3 3 3-3"],
        .fileText: ["M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z", "M14 2v5a1 1 0 0 0 1 1h5", "M10 9H8", "M16 13H8", "M16 17H8"],
        .keyboard: ["M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2Z", "M10 8h.01", "M12 12h.01", "M14 8h.01", "M16 12h.01", "M18 8h.01", "M6 8h.01", "M7 16h10", "M8 12h.01"],
        .layoutGrid: ["M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1Z", "M15 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1Z", "M15 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1Z", "M4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1Z"],
        .listChecks: ["M13 5h8", "M13 12h8", "M13 19h8", "m3 17 2 2 4-4", "m3 7 2 2 4-4"],
        .pencil: ["M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z", "m15 5 4 4"],
        .phoneCall: ["M13 2a9 9 0 0 1 9 9", "M13 6a5 5 0 0 1 5 5", "M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384"],
        .sparkles: ["M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z", "M20 2v4", "M22 4h-4", "M2 20a2 2 0 1 0 4 0a2 2 0 1 0 -4 0Z"],
        .wandSparkles: ["m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72", "m14 7 3 3", "M5 6v4", "M19 14v4", "M10 2v2", "M7 8H3", "M21 16h-4", "M11 3H9"],
        .arrowUpRight: ["M7 7h10v10", "M7 17 17 7"],
        .audioLines: ["M2 10v3", "M6 6v11", "M10 3v18", "M14 8v7", "M18 5v13", "M22 10v3"],
        .book: ["M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20", "m8 13 4-7 4 7", "M9.1 11h5.7"],
        .check: ["M20 6 9 17l-5-5"],
        .chevronDown: ["m6 9 6 6 6-6"],
        .circleCheck: ["M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0Z", "m16 9-5.5 5.5L8 12"],
        .circleX: ["M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0Z", "m15 9-6 6", "m9 9 6 6"],
        .copy: ["M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2Z", "M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"],
        .download: ["M12 17V3", "m6 11 6 6 6-6", "M19 21H5"],
        .fileAudio: ["M4 6.835V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.706.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2h-.343", "M14 2v5a1 1 0 0 0 1 1h5", "M2 19a2 2 0 0 1 4 0v1a2 2 0 0 1-4 0v-4a6 6 0 0 1 12 0v4a2 2 0 0 1-4 0v-1a2 2 0 0 1 4 0"],
        .flame: ["M12 3q1 4 4 6.5t3 5.5a1 1 0 0 1-14 0 5 5 0 0 1 1-3 1 1 0 0 0 5 0c0-2-1.5-3-1.5-5q0-2 2.5-4"],
        .folder: ["M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"],
        .history: ["M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8", "M3 3v5h5", "M12 7v5l4 2"],
        .home: ["M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8", "M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"],
        .mic: ["M12 19v3", "M19 10v2a7 7 0 0 1-14 0v-2", "M12 2h0a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h-0a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3Z"],
        .micOff: ["M12 19v3", "M15 9.34V5a3 3 0 0 0-5.68-1.33", "M16.95 16.95A7 7 0 0 1 5 12v-2", "M18.89 13.23A7 7 0 0 0 19 12v-2", "m2 2 20 20", "M9 9v3a3 3 0 0 0 5.12 2.12"],
        .moon: ["M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"],
        .pause: ["M15 3h3a1 1 0 0 1 1 1v16a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1v-16a1 1 0 0 1 1 -1Z", "M6 3h3a1 1 0 0 1 1 1v16a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1v-16a1 1 0 0 1 1 -1Z"],
        .play: ["M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"],
        .plus: ["M5 12h14", "M12 5v14"],
        .search: ["m21 21-4.34-4.34", "M3 11a8 8 0 1 0 16 0a8 8 0 1 0 -16 0Z"],
        .sleep: ["M3 10h8l-8 8h8", "M14 3h7l-7 7h7"],
        .sliders: ["M10 5H3", "M12 19H3", "M14 3v4", "M16 17v4", "M21 12h-9", "M21 19h-5", "M21 5h-7", "M8 10v4", "M8 12H3"],
        .smartphone: ["M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-16a2 2 0 0 1 2 -2Z", "M12 18h.01"],
        .speakerOff: ["M7.4 3.6 4.6 6H2.8a.8.8 0 0 0-.8.8v3.4a.8.8 0 0 0 .8.8h1.8l2.8 2.4a.5.5 0 0 0 .8-.4V4a.5.5 0 0 0-.8-.4Z", "M11.2 6.4 15 10.2M15 6.4l-3.8 3.8"],
        .speakerOn: ["M7.4 3.6 4.6 6H2.8a.8.8 0 0 0-.8.8v3.4a.8.8 0 0 0 .8.8h1.8l2.8 2.4a.5.5 0 0 0 .8-.4V4a.5.5 0 0 0-.8-.4Z", "M11 6.2a3.2 3.2 0 0 1 0 4.6", "M13.1 4.4a6 6 0 0 1 0 8.2"],
        .sun: ["M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0Z", "M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"],
        .trash: ["M10 11v6", "M14 11v6", "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6", "M3 6h18", "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"],
        .triangleAlert: ["m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3", "M12 9v4", "M12 17h.01"],
        .users: ["M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", "M16 3.128a4 4 0 0 1 0 7.744", "M22 21v-2a4 4 0 0 0-3-3.87", "M5 7a4 4 0 1 0 8 0a4 4 0 1 0 -8 0Z"],
        .volume: ["M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"],
        .volumeHigh: ["M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z", "M16 9a5 5 0 0 1 0 6", "M19.364 18.364a9 9 0 0 0 0-12.728"],
        .x: ["M18 6 6 18", "m6 6 12 12"],
    ]

    private static var cache: [Glyph: Path] = [:]

    /// Le tracé complet de l'icône, dans sa grille.
    var path: Path {
        if let path = Self.cache[self] { return path }
        var path = Path()
        for data in Self.paths[self] ?? [] { path.addPath(SVGPath.parse(data)) }
        // La plume est dessinée sur 856 × 1023 : on la centre dans sa grille carrée.
        if self == .plume { path = path.offsetBy(dx: (1023 - 856) / 2, dy: 0) }
        Self.cache[self] = path
        return path
    }
}

extension Glyph {
    /// L'icône en image AppKit teintable, pour la barre de menus.
    func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: size / self.box, y: size / self.box)
            context.addPath(self.path.cgPath)
            if self.stroke == 0 {
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
            } else {
                context.setLineWidth(self.stroke)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(NSColor.black.cgColor)
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct Icon: View {
    var glyph: Glyph
    var size: CGFloat = 16
    /// Remplit aussi la forme (lecture, pause, flamme allumée).
    var filled = false

    init(_ glyph: Glyph, size: CGFloat = 16, filled: Bool = false) {
        self.glyph = glyph
        self.size = size
        self.filled = filled
    }

    var body: some View {
        let shape = GlyphShape(glyph: glyph)
        let style = StrokeStyle(lineWidth: glyph.stroke * size / glyph.box, lineCap: .round, lineJoin: .round)
        ZStack {
            if filled || glyph.stroke == 0 { shape.fill() }
            if glyph.stroke > 0 { shape.stroke(style: style) }
        }
        .frame(width: size, height: size)
    }
}

private struct GlyphShape: Shape {
    var glyph: Glyph

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / glyph.box
        return glyph.path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Lecture des données d'un tracé SVG (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z`,
/// en absolu comme en relatif).
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var reader = Reader(data)
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"

        while true {
            reader.skipSeparators()
            guard let next = reader.peek else { break }
            if next.isLetter {
                command = next
                reader.advance()
            }
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch Character(command.uppercased()) {
            case "M":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = point(x, y)
                start = current
                path.move(to: current)
                lastControl = nil
                // Les couples suivants sont des lignes.
                command = relative ? "l" : "L"
            case "L":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                guard let x = reader.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = reader.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let x1 = reader.number(), let y1 = reader.number(), let x2 = reader.number(), let y2 = reader.number(),
                    let x = reader.number(), let y = reader.number()
                else { return path }
                let c1 = point(x1, y1)
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "S":
                guard let x2 = reader.number(), let y2 = reader.number(), let x = reader.number(), let y = reader.number()
                else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "Q":
                guard let x1 = reader.number(), let y1 = reader.number(), let x = reader.number(), let y = reader.number()
                else { return path }
                let c = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "T":
                guard let x = reader.number(), let y = reader.number() else { return path }
                let c = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "A":
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(),
                    let large = reader.flag(), let sweep = reader.flag(), let x = reader.number(), let y = reader.number()
                else { return path }
                let end = point(x, y)
                arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// Arc d'ellipse SVG, converti en courbes de Bézier (au plus un quart de tour chacune).
    private static func arc(
        _ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool,
        sweep: Bool
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2
        let dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let handle = 4 / 3 * tan(step / 4)
        func ellipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for i in 0..<segments {
            let t0 = theta + CGFloat(i) * step
            let t1 = t0 + step
            let a = ellipse(t0)
            let b = ellipse(t1)
            let ta = tangent(t0)
            let tb = tangent(t1)
            path.addCurve(
                to: i == segments - 1 ? p1 : b, control1: CGPoint(x: a.x + handle * ta.x, y: a.y + handle * ta.y),
                control2: CGPoint(x: b.x - handle * tb.x, y: b.y - handle * tb.y))
        }
    }

    private struct Reader {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) { characters = Array(text) }

        var peek: Character? { index < characters.count ? characters[index] : nil }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while let c = peek, c == " " || c == "," || c == "\n" || c == "\t" { index += 1 }
        }

        /// Un nombre : signe, chiffres, point, exposant. `1.5.5` se lit `1.5` puis `.5`.
        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false
            if let c = peek, c == "-" || c == "+" {
                text.append(c)
                index += 1
            }
            while let c = peek {
                if c.isNumber {
                    text.append(c)
                } else if c == ".", !seenDot {
                    seenDot = true
                    text.append(c)
                } else if c == "e" || c == "E" {
                    text.append(c)
                    index += 1
                    if let sign = peek, sign == "-" || sign == "+" {
                        text.append(sign)
                        index += 1
                    }
                    continue
                } else {
                    break
                }
                index += 1
            }
            return Double(text).map { CGFloat($0) }
        }

        /// Un drapeau d'arc : un seul caractère, `0` ou `1`, parfois collé au nombre suivant.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek, c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }
    }
}
