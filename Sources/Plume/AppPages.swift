import AppKit
import PlumeKit
import SwiftUI

// MARK: - Historique

struct HistoryPage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var library: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 324)
            Rectangle().fill(UI.line).frame(width: 1)
            ZStack {
                if let transcript = library.selected {
                    TranscriptDetail(transcript: transcript, library: library, player: library.player)
                        .id(transcript.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    emptyState.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(UI.ease, value: library.selection)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr("Historique")).font(UI.sans(24, .medium)).tracking(-0.4)
                    Spacer()
                    if library.importing > 0 {
                        ProgressView().controlSize(.small).transition(.opacity)
                    }
                    PlumeButton(icon: .plus, help: tr("Transcrire un fichier audio")) { app.chooseFiles() }
                }
                HStack(spacing: 7) {
                    Icon(.search, size: 14).foregroundStyle(UI.text2)
                    TextField(tr("Rechercher"), text: $library.query)
                        .textFieldStyle(.plain)
                        .font(UI.sans(14))
                    if !library.query.isEmpty {
                        Button(action: { library.query = "" }) {
                            Icon(.circleX, size: 14).foregroundStyle(UI.text3)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))

                FilterBar(selection: $library.filter)
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(library.sections, id: \.title) { section in
                        Text(section.title)
                            .font(UI.sans(12, .medium))
                            .foregroundStyle(UI.text2)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            .padding(.bottom, 3)
                        ForEach(section.items) { transcript in
                            HistoryRow(transcript: transcript, selected: library.selection == transcript.id) {
                                library.selection = transcript.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, UI.dockClearance)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Icon(library.query.isEmpty ? .audioLines : .search, size: 28)
                .foregroundStyle(UI.text3)
            Text(library.query.isEmpty ? tr("Aucune transcription") : tr("Aucun résultat"))
                .font(UI.sans(15, .medium))
            if library.query.isEmpty {
                Text(tr("Dicte quelque chose, ou dépose un fichier audio dans cette fenêtre."))
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Filtres de l'historique ; le fond de l'onglet actif glisse de l'un à l'autre.
private struct FilterBar: View {
    @Binding var selection: HistoryFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases) { filter in
                let active = selection == filter
                Button {
                    Sounds.play(.tab)
                    withAnimation(UI.spring) { selection = filter }
                } label: {
                    Text(filter.title)
                        .font(UI.sans(13, active ? .semibold : .regular))
                        .foregroundStyle(active ? UI.text : UI.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(UI.selected)
                                    .matchedGeometryEffect(id: "filter", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

private struct HistoryRow: View {
    var transcript: Transcript
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var glyph: Glyph {
        if transcript.device == "iphone" { return .smartphone }
        switch transcript.mode {
        case .dictation: return .mic
        case .meeting: return .users
        case .imported: return .fileAudio
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Icon(glyph, size: 13)
                    .foregroundStyle(selected ? UI.onText : UI.text2)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? UI.text : UI.hover))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Self.time.string(from: transcript.createdAt))
                            .font(UI.mono(12))
                            .foregroundStyle(UI.text)
                        Text(transcript.mode.label)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                        Spacer(minLength: 4)
                        Text(Format.clock(transcript.duration))
                            .font(UI.mono(11))
                            .foregroundStyle(UI.text3)
                    }
                    Text(transcript.preview)
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .fill(selected ? UI.selected : (hovering ? UI.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .onHover {
            hovering = $0
            if $0, !selected { Sounds.hover(.hoverRow) }
        }
        .animation(UI.quick, value: hovering)
        .animation(UI.quick, value: selected)
    }
}

private struct TranscriptDetail: View {
    var transcript: Transcript
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: AudioPlayerModel

    @State private var renaming: String?
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var editingTitle = false
    @State private var newTitle = ""

    private var audio: [URL] { library.audioURLs(for: transcript) }
    private var reprocessing: Bool { library.reprocessing == transcript.id }
    private var working: Bool { library.working.contains(transcript.id) }
    private var aiAvailable: Bool { LocalAI.availability.isAvailable }

    private var meta: String {
        var parts: [String] = []
        if transcript.title != nil { parts.append(TranscriptStore.dateTitle(for: transcript)) }
        parts.append(Format.duration(transcript.duration))
        if transcript.speakers.count > 1 { parts.append("\(transcript.speakers.count) " + tr("interlocuteurs")) }
        parts.append("\(HomePage.number(Double(LibraryStats.wordCount(transcript.text)))) " + tr("mots"))
        if let app = transcript.app { parts.append(app) }
        if transcript.device == "iphone" { parts.append("iPhone") }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            newTitle = transcript.title ?? ""
                            editingTitle = true
                        } label: {
                            HStack(spacing: 8) {
                                Text(TranscriptStore.title(for: transcript))
                                    .font(UI.sans(20, .medium))
                                    .tracking(-0.3)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Icon(.pencil, size: 13).foregroundStyle(UI.text3)
                            }
                            .foregroundStyle(UI.text)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                        .help(tr("Donner un titre"))
                        Text(meta)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        CopyButton(text: transcript.text, prominent: true)
                        exportMenu
                        PlumeButton(icon: .folder, help: tr("Afficher les fichiers dans le Finder")) { library.reveal(transcript) }
                        PlumeButton(icon: .trash, help: tr("Mettre à la corbeille")) { confirmingDelete = true }
                    }
                }

                if audio.isEmpty {
                    Text(tr("L'enregistrement audio n'a pas été conservé."))
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text3)
                        .padding(.top, 14)
                } else {
                    PlayerBar(player: player, id: transcript.id, urls: audio, length: transcript.duration)
                        .padding(.top, 16)
                }

                HStack(spacing: 8) {
                    if transcript.mode != .dictation, !audio.isEmpty { voices }
                    if !audio.isEmpty {
                        PlumeButton(title: tr("Retranscrire"), icon: .history, help: tr("Refaire la transcription avec le modèle actuel")) {
                            library.retranscribe(transcript)
                        }
                        .disabled(working || reprocessing)
                    }
                    if transcript.mode != .dictation || LibraryStats.wordCount(transcript.text) > 120 {
                        PlumeButton(
                            title: transcript.summary == nil ? tr("Résumer") : tr("Résumer à nouveau"), icon: .sparkles,
                            help: aiAvailable ? tr("Points clés, décisions et actions, par l'IA locale") : LocalAI.availability.reason
                        ) {
                            library.summarize(transcript)
                        }
                        .disabled(working || !aiAvailable)
                    }
                    if working {
                        ProgressView().controlSize(.small)
                        Text(tr("En cours…")).font(UI.sans(13)).foregroundStyle(UI.text2)
                    }
                }
                .padding(.top, 12)

                if let summary = transcript.summary, !summary.isEmpty {
                    summaryCard(summary).padding(.top, 16)
                }

                Rectangle().fill(UI.line).frame(height: 1).padding(.vertical, 18)

                if transcript.speakers.count > 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(transcript.segments) { segment in
                            row(segment)
                        }
                    }
                    .opacity(reprocessing ? 0.35 : 1)
                } else {
                    Text(transcript.text)
                        .font(UI.sans(15))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: 640, alignment: .leading)
                        .opacity(reprocessing ? 0.35 : 1)
                }
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(UI.ease, value: reprocessing)
        }
        .confirmationDialog(tr("Supprimer cette transcription ?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("Mettre à la corbeille"), role: .destructive) {
                Sounds.play(.refuse)
                library.delete(transcript)
            }
            Button(tr("Annuler"), role: .cancel) {}
        } message: {
            Text(tr("Le texte et l'audio partent dans la corbeille du Mac."))
        }
        .alert(
            tr("Renommer l'interlocuteur"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(tr("Nom"), text: $newName)
            Button(tr("Renommer")) {
                if let renaming { library.rename(renaming, to: newName, in: transcript) }
                renaming = nil
            }
            Button(tr("Annuler"), role: .cancel) { renaming = nil }
        } message: {
            Text(tr("Le nouveau nom remplace") + " « \(renaming ?? "") » " + tr("dans toute la transcription."))
        }
        .alert(tr("Titre de la transcription"), isPresented: $editingTitle) {
            TextField(tr("Titre"), text: $newTitle)
            Button(tr("Enregistrer")) { library.retitle(transcript, to: newTitle) }
            Button(tr("Annuler"), role: .cancel) {}
        } message: {
            Text(tr("Laisse vide pour revenir à la date."))
        }
    }

    /// Markdown, texte, sous-titres ou JSON, enregistrés où on veut.
    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button(format.label) { library.export(transcript, as: format) }
                    .disabled(format.needsSegments && transcript.segments.isEmpty)
            }
        } label: {
            Icon(.fileDown, size: 14)
                .foregroundStyle(UI.text)
                .frame(width: 32, height: 30)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Exporter"))
    }

    /// Le résumé écrit par l'IA locale : points clés, décisions, actions.
    private func summaryCard(_ summary: String) -> some View {
        Card(fill: UI.raised) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Icon(.listChecks, size: 14)
                    Text(tr("Résumé")).font(UI.sans(14, .medium))
                    Text(tr("par l'IA locale")).font(UI.sans(12)).foregroundStyle(UI.text3)
                    Spacer()
                    CopyButton(text: summary)
                }
                ForEach(Array(summary.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, line in
                    summaryLine(String(line))
                }
            }
        }
        .frame(maxWidth: 640)
        .transition(.opacity)
    }

    @ViewBuilder
    private func summaryLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            Text(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                .font(UI.sans(13, .semibold))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(UI.text3)
                Text(markdownInline(String(trimmed.dropFirst(2))))
            }
            .font(UI.sans(14))
            .lineSpacing(4)
            .textSelection(.enabled)
        } else {
            Text(markdownInline(trimmed)).font(UI.sans(14)).lineSpacing(4).textSelection(.enabled)
        }
    }

    private func markdownInline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Refaire la séparation des voix, en précisant au besoin combien de personnes parlaient.
    private var voices: some View {
        HStack(spacing: 8) {
            Menu {
                Button(tr("Détection automatique")) { library.reprocess(transcript, speakers: nil) }
                Divider()
                ForEach(1...8, id: \.self) { count in
                    Button(count == 1 ? tr("1 personne") : "\(count) " + tr("personnes")) { library.reprocess(transcript, speakers: count) }
                }
            } label: {
                HStack(spacing: 6) {
                    Icon(.users, size: 13)
                    Text(tr("Refaire la séparation des voix")).font(UI.sans(13, .medium))
                    Icon(.chevronDown, size: 12).foregroundStyle(UI.text2)
                }
                .foregroundStyle(UI.text)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(reprocessing)
            .help(tr("Si les voix sont mal séparées, indique combien de personnes parlaient."))
            if reprocessing {
                ProgressView().controlSize(.small)
                Text(tr("Nouvelle écoute en cours…")).font(UI.sans(13)).foregroundStyle(UI.text2)
            }
        }
    }

    private func color(for speaker: String) -> Color {
        if TranscriptBuilder.isMe(speaker) { return UI.text }
        let index = transcript.speakers.filter { !TranscriptBuilder.isMe($0) }.firstIndex(of: speaker) ?? 0
        return Theme.speakers[index % Theme.speakers.count]
    }

    private func row(_ segment: Segment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    newName = segment.speaker
                    renaming = segment.speaker
                } label: {
                    Text(segment.speaker)
                        .font(UI.sans(13, .medium))
                        .foregroundStyle(color(for: segment.speaker))
                        .lineLimit(1)
                }
                .buttonStyle(PressStyle())
                .help(tr("Renommer cet interlocuteur"))
                Button {
                    player.play(id: transcript.id, urls: audio, from: segment.start)
                } label: {
                    Text(Format.clock(segment.start))
                        .font(UI.mono(11))
                        .foregroundStyle(UI.text3)
                }
                .buttonStyle(PressStyle())
                .help(tr("Écouter à partir d'ici"))
            }
            .frame(width: 118, alignment: .leading)
            Text(segment.text)
                .font(UI.sans(15))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

/// Lecteur de l'enregistrement d'origine : lecture, position, durée.
private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel
    var id: String
    var urls: [URL]
    /// Durée connue de la transcription, affichée tant que l'audio n'est pas ouvert.
    var length: TimeInterval
    @State private var hovering = false

    private var active: Bool { player.isLoaded(id) }
    private var playing: Bool { active && player.isPlaying }
    private var progress: Double {
        guard active, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { player.toggle(id: id, urls: urls) }) {
                Icon(playing ? .pause : .play, size: 14, filled: true)
                    .foregroundStyle(UI.onText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(UI.text))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .keyboardShortcut(.space, modifiers: [])
            .help(tr("Écouter l'enregistrement"))
            .animation(UI.spring, value: playing)

            Text(Format.clock(active ? player.currentTime : 0))
                .font(UI.mono(11.5))
                .foregroundStyle(UI.text2)
                .frame(width: 40, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(UI.active).frame(height: hovering ? 6 : 4)
                    Capsule().fill(UI.text).frame(width: max(4, proxy.size.width * progress), height: hovering ? 6 : 4)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, proxy.size.width * progress - 6))
                        .opacity(hovering || playing ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        player.seek(id: id, urls: urls, fraction: Double(max(0, min(1, value.location.x / proxy.size.width))))
                    }
                )
            }
            .frame(height: 20)
            .onHover { hovering = $0 }
            .animation(UI.quick, value: hovering)

            Text(Format.clock(active ? player.duration : length))
                .font(UI.mono(11.5))
                .foregroundStyle(UI.text2)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
    }
}

// MARK: - Vocabulaire

struct VocabularyPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: tr("Vocabulaire"),
                    subtitle: tr("Les mots que le modèle écrit mal, et ce qu'il faut écrire à la place. Ou des raccourcis : « ma signature » devient ta signature complète.")
                ) {
                    PlumeButton(title: tr("Ajouter"), icon: .plus, kind: .primary) {
                        withAnimation(UI.spring) { settings.addReplacement() }
                    }
                }
                .rise(0)

                Card(padding: 6) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Text(tr("Entendu")).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 14)
                            Text(tr("Écrit")).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .font(UI.sans(12, .medium))
                        .foregroundStyle(UI.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if settings.replacements.isEmpty {
                            Rectangle().fill(UI.line).frame(height: 1)
                            Text(tr("Aucun remplacement pour l'instant."))
                                .font(UI.sans(13))
                                .foregroundStyle(UI.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        ForEach($settings.replacements) { $item in
                            VStack(spacing: 0) {
                                Rectangle().fill(UI.line).frame(height: 1)
                                HStack(spacing: 10) {
                                    TextField(tr("ce que tu dis"), text: $item.original)
                                        .textFieldStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    Icon(.arrowRight, size: 13)
                                        .foregroundStyle(UI.text3)
                                        .frame(width: 14)
                                    // Plusieurs lignes possibles : une adresse, une signature.
                                    TextField(tr("ce qui doit s'écrire"), text: $item.with, axis: .vertical)
                                        .textFieldStyle(.plain)
                                        .lineLimit(1...6)
                                        .frame(maxWidth: .infinity)
                                    Button {
                                        Sounds.play(.toggleOff)
                                        withAnimation(UI.spring) { settings.replacements.removeAll { $0.id == item.id } }
                                    } label: {
                                        Icon(.x, size: 12)
                                            .foregroundStyle(UI.text3)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle())
                                    .help(tr("Supprimer"))
                                }
                                .font(UI.sans(14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            .transition(.opacity.combined(with: .offset(y: -6)))
                        }
                    }
                }
                .rise(1)

                Text(tr("Le remplacement se fait sur des mots entiers, sans tenir compte des majuscules, à la fin de chaque dictée ou réunion. Un retour à la ligne dans « Écrit » (⌥↩) fait un raccourci sur plusieurs lignes."))
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
                    .rise(2)
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Réglages

/// Les groupes de réglages, dans l'ordre de la barre latérale.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case general, shortcuts, dictation, meeting, ai, audio, model, library, access, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("Général")
        case .shortcuts: return tr("Raccourcis")
        case .dictation: return tr("Dictée")
        case .meeting: return tr("Réunion")
        case .ai: return tr("IA locale")
        case .audio: return tr("Micro et sons")
        case .model: return tr("Modèle")
        case .library: return tr("Bibliothèque")
        case .access: return tr("Accès pour une IA")
        case .permissions: return tr("Autorisations")
        case .about: return tr("À propos")
        }
    }

    var glyph: Glyph {
        switch self {
        case .general: return .sliders
        case .shortcuts: return .keyboard
        case .dictation: return .clipboardPaste
        case .meeting: return .users
        case .ai: return .sparkles
        case .audio: return .mic
        case .model: return .audioLines
        case .library: return .folder
        case .access: return .arrowUpRight
        case .permissions: return .circleCheck
        case .about: return .plume
        }
    }
}

/// Les réglages : une barre latérale à gauche, comme l'historique, et le groupe choisi à
/// droite. Il y en a de plus en plus ; en colonne unique on ne s'y retrouvait plus.
struct SettingsPage: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var updates = Updates.shared
    @State private var group: SettingsGroup = .general
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Rectangle().fill(UI.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: group.title).rise(0)
                    content.rise(1)
                }
                .padding(.horizontal, UI.pagePadding)
                .padding(.top, 58)
                .padding(.bottom, UI.dockClearance)
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // Chaque groupe arrive avec sa propre cascade.
            .id(group)
        }
        .onReceive(refresh) { _ in
            settings.refreshPermissions()
            settings.refreshMicrophones()
        }
        .onAppear {
            settings.refreshMicrophones()
            settings.refreshIntegrations()
            settings.refreshAI()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Réglages"))
                .font(UI.sans(24, .medium))
                .tracking(-0.4)
                .padding(.horizontal, 16)
                .padding(.top, 58)
                .padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsGroup.allCases) { item in
                        SettingsGroupRow(
                            group: item, selected: group == item,
                            attention: item == .permissions && settings.permissionsMissing
                        ) {
                            withAnimation(UI.ease) { group = item }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, UI.dockClearance)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch group {
        case .general: general
        case .shortcuts: shortcuts
        case .dictation: dictation
        case .meeting: meeting
        case .ai: ai
        case .audio: audio
        case .model: model
        case .library: library
        case .access: access
        case .permissions: permissions
        case .about: about
        }
    }

    private var general: some View {
        SettingsSection("") {
            SettingRow(tr("Langue"), detail: tr("Celle de la fenêtre, de l'encoche et des transcriptions.")) {
                Picker("", selection: $settings.language) {
                    ForEach(Language.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingRow(tr("Apparence")) {
                Picker("", selection: $settings.appearance) {
                    Text(tr("Sombre")).tag("sombre")
                    Text(tr("Claire")).tag("clair")
                    Text(tr("Comme le système")).tag("systeme")
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingToggle(
                tr("Ouvrir Plume à la connexion"),
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
        }
    }

    private var shortcuts: some View {
        SettingsSection("", footer: tr("Appui bref : démarrer, puis arrêter. Maintenir le raccourci de dictée : parler tant qu'il est tenu. Échap annule une dictée.")) {
            SettingRow(tr("Dicter")) {
                ShortcutRecorder(shortcut: $settings.dictationShortcut, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Enregistrer une réunion"), detail: tr("Le mode réunion s'active aussi en survolant l'encoche.")) {
                ShortcutRecorder(shortcut: $settings.meetingShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Transformer la sélection"), detail: settings.ai.isAvailable
                ? tr("Sélectionne un texte, dicte une consigne (« traduis en anglais », « plus court »), l'IA locale le réécrit. Sans sélection, elle rédige.")
                : (settings.ai.reason ?? "")) {
                ShortcutRecorder(shortcut: $settings.transformShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            .disabled(!settings.ai.isAvailable)
            SettingRow(tr("Recoller la dernière dictée"), detail: tr("Quand le collage a raté, ou pour la réutiliser ailleurs.")) {
                ShortcutRecorder(shortcut: $settings.pasteLastShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Ouvrir Plume")) {
                ShortcutRecorder(shortcut: $settings.openShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
        }
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(tr("Collage")) {
                SettingToggle(tr("Coller dans le champ actif à la fin"), detail: tr("Sinon, le texte est seulement copié. Le presse-papiers est toujours rétabli ensuite."), isOn: $settings.pasteAfterDictation)
                SettingToggle(
                    tr("Adapter l'insertion à ce qui entoure le curseur"),
                    detail: tr("Une espace si le curseur touche un mot, une minuscule si la phrase est commencée, pas de point final si elle continue."),
                    isOn: $settings.smartInsert
                )
                .disabled(!settings.pasteAfterDictation)
                SettingToggle(
                    tr("Écrire au fur et à mesure"),
                    detail: tr("Les mots se tapent dans le champ pendant que tu parles, au lieu d'être collés d'un coup à la fin ; quand le modèle se corrige, Plume efface et retape. La mise au propre par l'IA ne s'applique alors pas ; l'historique garde la version complète."),
                    badge: tr("bêta"),
                    isOn: $settings.streamingPaste
                )
                .disabled(!settings.pasteAfterDictation)
            }
            SettingsSection(tr("Texte")) {
                SettingToggle(tr("Retirer les hésitations et les mots répétés"), isOn: $settings.cleanup)
                SettingToggle(
                    tr("Commandes vocales"),
                    detail: tr("« À la ligne », « nouveau paragraphe », « nouvelle puce », « point d'interrogation », « ouvrez les guillemets », « efface ça », « appuie sur Entrée »."),
                    isOn: $settings.voiceCommands)
            }
            SettingsSection(tr("Pendant la dictée")) {
                SettingToggle(tr("Afficher les mots en direct"), detail: tr("Le texte défile sous l'encoche pendant que tu parles."), isOn: $settings.liveTranscript)
                SettingToggle(
                    tr("Couper le son de l'ordinateur pendant la dictée"),
                    detail: tr("Musique ou vidéo en cours : le son est coupé le temps de parler, puis rétabli."),
                    isOn: $settings.muteWhileDictating)
            }
        }
    }

    private var meeting: some View {
        SettingsSection("") {
            SettingToggle(
                tr("Capter aussi le son de l'ordinateur"),
                detail: tr("Les autres participants (Meet, Zoom, Teams…) sont transcrits même au casque, et chaque interlocuteur est séparé. Sans casque, l'écho des haut-parleurs est retiré du micro."),
                isOn: $settings.systemAudio)
            SettingToggle(
                tr("Proposer d'enregistrer quand un appel démarre"),
                detail: tr("Dès que Zoom, Teams, FaceTime ou Meet (dans le navigateur) ouvre le micro, l'encoche propose la réunion."),
                isOn: $settings.meetingDetection)
            SettingToggle(
                tr("Résumer chaque réunion"), detail: settings.ai.isAvailable
                    ? tr("Points clés, décisions, actions et un titre, dès que la réunion est transcrite.")
                    : (settings.ai.reason ?? ""),
                isOn: $settings.autoSummary
            )
            .disabled(!settings.ai.isAvailable)
        }
    }

    private var ai: some View {
        SettingsSection(
            "",
            footer: settings.ai.isAvailable
                ? tr("Apple Intelligence, sur ce Mac : rien n'est envoyé nulle part. Toujours en option, le texte brut reste dans l'historique.")
                : settings.ai.reason
        ) {
            SettingToggle(
                tr("Mettre les dictées au propre"),
                detail: tr("Ponctuation, faux départs et auto-corrections (« non pardon ») repris par l'IA. Les règles par application ont la priorité."),
                isOn: $settings.polish
            )
            .disabled(!settings.ai.isAvailable)
            SettingRow(tr("Consignes"), detail: tr("Ce que l'IA doit respecter en mettant au propre.")) {
                TextField(tr("tutoie, pas d'émojis, ton direct…"), text: $settings.polishInstructions)
                    .textFieldStyle(.plain)
                    .font(UI.sans(13))
                    .padding(.horizontal, 10)
                    .frame(width: 270, height: 30)
                    .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))
            }
            .disabled(!settings.ai.isAvailable || !settings.polish)
            SettingRow(tr("Transformer la sélection"), detail: tr("Le raccourci se règle dans Raccourcis : sélectionne un texte, dicte une consigne, l'IA le réécrit.")) {
                Keycaps(shortcut: HotkeyManager.describe(settings.transformShortcut))
            }
            .disabled(!settings.ai.isAvailable)
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(
                tr("Micro"),
                footer: settings.chosenMicrophoneMissing
                    ? tr("Le micro choisi n'est pas branché : en attendant, Plume utilise celui du Mac.")
                    : tr("Plume garde ce micro quoi qu'il arrive : connecter des écouteurs ou un casque Bluetooth n'y change rien.")
            ) {
                SettingRow(tr("Micro utilisé")) {
                    Picker("", selection: $settings.microphoneUID) {
                        Text(settings.microphones.first(where: \.isBuiltIn).map { "\($0.name) " + tr("(par défaut)") } ?? tr("Micro du Mac (par défaut)"))
                            .tag("")
                        ForEach(settings.microphones.filter { !$0.isBuiltIn }) { device in
                            Text(device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name).tag(device.uid)
                        }
                        if settings.chosenMicrophoneMissing {
                            Text(tr("Micro choisi (non branché)")).tag(settings.microphoneUID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 270)
                }
            }
            SettingsSection(tr("Sons"), footer: tr("Un son doux au début et à la fin de chaque enregistrement, et une note discrète sur les gestes dans cette fenêtre.")) {
                SettingToggle(tr("Sons de Plume"), isOn: $settings.sounds)
                SettingRow(tr("Pack de sons"), detail: tr("Les sons de début et de fin d'enregistrement.")) {
                    Picker("", selection: $settings.soundPack) {
                        ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    // On fait entendre le pack choisi.
                    .onChange(of: settings.soundPack) { _, _ in Sounds.play(.start) }
                    .disabled(!settings.sounds)
                }
                SettingRow(tr("Volume")) {
                    HStack(spacing: 8) {
                        Icon(.volume, size: 14).foregroundStyle(UI.text2)
                        Slider(value: $settings.soundVolume, in: 0.1...1) { editing in
                            // Au relâchement, le son de début : c'est lui qu'on règle.
                            if !editing { Sounds.play(.start) }
                        }
                        .controlSize(.small)
                        .tint(UI.text)
                        .frame(width: 150)
                        // Un cran sonne à chaque quatorzième de la course, de plus en plus haut.
                        .onChange(of: Int((settings.soundVolume - 0.1) / 0.9 * 14)) { _, notch in
                            Sounds.play(.sliderStep(notch * 8 / 14))
                        }
                        Icon(.volumeHigh, size: 14).foregroundStyle(UI.text2)
                    }
                    .disabled(!settings.sounds)
                }
            }
        }
    }

    private var model: some View {
        SettingsSection(
            "",
            footer: settings.modelMessage
                ?? tr("Tous tournent sur le Neural Engine, téléchargés une fois depuis Hugging Face. Changer de modèle recharge ~600 Mo ; le bouton « Retranscrire » de l'historique permet de comparer sur un même enregistrement.")
        ) {
            SettingRow(tr("Modèle"), detail: settings.model.detail) {
                Picker("", selection: $settings.model) {
                    ForEach(EngineModel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 290)
            }
            if settings.model == .custom {
                SettingRow(
                    tr("Dossier du modèle"),
                    detail: settings.customModelPath.isEmpty
                        ? tr("Aucun dossier choisi : Plume ne peut rien transcrire.")
                        : (settings.customModelPath as NSString).abbreviatingWithTildeInPath
                ) {
                    PlumeButton(title: tr("Choisir…"), icon: .folder) { settings.chooseModelDirectory() }
                }
            }
        }
    }

    private var library: some View {
        SettingsSection(
            "",
            footer: settings.retention == .nothing
                ? tr("Les dictées sont collées puis oubliées : ni texte, ni audio, ni fichier de secours, et les statistiques de l'accueil s'arrêtent. Les réunions, qui n'ont pas d'autre débouché, restent rangées dans l'historique.")
                : nil
        ) {
            SettingRow(tr("Dossier"), detail: (settings.libraryPath as NSString).abbreviatingWithTildeInPath) {
                PlumeButton(title: tr("Modifier…")) { settings.chooseLibrary() }
            }
            SettingRow(tr("Conserver de chaque dictée"), detail: tr("L'audio sert à réécouter et à retranscrire depuis l'historique.")) {
                Picker("", selection: $settings.retention) {
                    ForEach(SettingsModel.Retention.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingRow(tr("Garder l'audio"), detail: tr("Le texte, lui, reste. L'audio plus ancien est supprimé au lancement.")) {
                Picker("", selection: $settings.audioRetentionDays) {
                    Text(tr("Toujours")).tag(0)
                    Text(tr("90 jours")).tag(90)
                    Text(tr("30 jours")).tag(30)
                    Text(tr("7 jours")).tag(7)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .disabled(settings.retention != .textAndAudio)
            SettingRow(tr("Tous les réglages"), detail: tr("Raccourcis, options, vocabulaire et applications dans un fichier, pour un autre Mac.")) {
                HStack(spacing: 6) {
                    PlumeButton(title: tr("Importer…")) { settings.importSettings() }
                    PlumeButton(title: tr("Exporter…"), icon: .fileDown) { settings.exportSettings() }
                }
            }
        }
    }

    private var access: some View {
        SettingsSection(
            "",
            footer: settings.integrationMessage
                ?? tr("Un assistant peut lire tes transcriptions : par le dossier de la bibliothèque, par la commande plume, ou par le serveur MCP de Plume.")
        ) {
            SettingRow(
                tr("Commande plume"),
                detail: !settings.commandInstalled
                    ? "plume last, plume search… dans un terminal."
                    : (settings.commandOnPath
                        ? tr("Installée dans ~/.local/bin.")
                        : tr("Installée dans ~/.local/bin — ajoute ce dossier à ton PATH pour l'appeler par son nom."))
            ) {
                LinkState(done: settings.commandInstalled, action: tr("Installer")) { settings.installCommand() }
            }
            SettingRow(tr("Claude Code"), detail: tr("Déclare le serveur MCP de Plume pour tous tes projets.")) {
                HStack(spacing: 6) {
                    if !settings.claudeCodeConnected {
                        PlumeButton(icon: .copy, help: tr("Copier la commande à lancer soi-même"), sound: .confirm) {
                            Paster.copy(Integrations.claudeCodeCommand)
                        }
                    }
                    if settings.connectingClaudeCode {
                        ProgressView().controlSize(.small)
                    } else {
                        LinkState(done: settings.claudeCodeConnected, action: tr("Connecter")) { settings.connectClaudeCode() }
                    }
                }
            }
            if Integrations.claudeDesktopPresent {
                SettingRow(tr("Claude Desktop"), detail: tr("Ajoute Plume à sa configuration, sans toucher au reste.")) {
                    LinkState(done: settings.claudeDesktopConnected, action: tr("Connecter")) { settings.connectClaudeDesktop() }
                }
            }
            SettingRow(tr("Autre assistant"), detail: tr("La configuration MCP à coller dans son fichier de réglages.")) {
                PlumeButton(title: tr("Copier"), icon: .copy, sound: .confirm) { Paster.copy(Integrations.configuration) }
            }
        }
    }

    private var permissions: some View {
        SettingsSection("") {
            PermissionRow(title: tr("Microphone"), detail: tr("Pour entendre ta voix."), granted: settings.microphoneGranted, action: settings.requestMicrophone)
                .padding(.horizontal, 14).padding(.vertical, 10)
            PermissionRow(title: tr("Accessibilité"), detail: tr("Pour coller le texte dans le champ actif."), granted: settings.accessibilityGranted, action: settings.requestAccessibility)
                .padding(.horizontal, 14).padding(.vertical, 10)
            SettingRow(tr("Enregistrement audio du système"), detail: tr("Demandée à la première réunion, pour capter le son de l'ordinateur.")) {
                PlumeButton(title: tr("Ouvrir les réglages")) { Permissions.openSettings(.audioCapture) }
            }
        }
    }

    private var about: some View {
        SettingsSection("") {
            SettingRow("Plume \(Updates.version)", detail: tr("Dictée et transcription locales : rien ne quitte ce Mac.")) {
                if updates.isAvailable {
                    PlumeButton(title: tr("Rechercher une mise à jour")) { updates.check() }
                }
            }
            if updates.isAvailable {
                SettingToggle(tr("Rechercher les mises à jour automatiquement"), isOn: $updates.automatic)
            }
            SettingRow(tr("Licences"), detail: tr("Modèles, polices, icônes et bibliothèques utilisés par Plume.")) {
                PlumeButton(title: tr("Afficher")) {
                    if let url = Bundle.main.url(forResource: "LICENCES", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

/// Une entrée de la barre latérale des réglages.
private struct SettingsGroupRow: View {
    var group: SettingsGroup
    var selected: Bool
    /// Un point d'alerte : une autorisation manque.
    var attention = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(group.glyph, size: 14)
                    .foregroundStyle(selected ? UI.onText : UI.text2)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? UI.text : UI.hover))
                Text(group.title)
                    .font(UI.sans(13.5, selected ? .medium : .regular))
                    .foregroundStyle(selected ? UI.text : UI.text2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if attention {
                    Circle().fill(Theme.warning).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .fill(selected ? UI.selected : (hovering ? UI.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .onHover {
            hovering = $0
            if $0, !selected { Sounds.hover(.hoverRow) }
        }
        .animation(UI.quick, value: hovering)
        .animation(UI.quick, value: selected)
    }
}

/// État d'un lien avec l'extérieur : un bouton pour l'établir, une coche une fois fait.
private struct LinkState: View {
    var done: Bool
    var action: String
    var perform: () -> Void

    var body: some View {
        if done {
            HStack(spacing: 6) {
                Icon(.circleCheck, size: 15)
                Text(tr("Fait")).font(UI.sans(13, .medium))
            }
            .foregroundStyle(UI.success)
            .frame(height: 30)
            .transition(.scale.combined(with: .opacity))
        } else {
            PlumeButton(title: action, kind: .primary, action: perform)
        }
    }
}

/// Un groupe de réglages : un titre, une carte dont les lignes sont séparées d'un filet.
private struct SettingsSection<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(UI.sans(14, .medium)) }
            Card(padding: 0) {
                // Un filet entre chaque ligne de la section.
                VStack(spacing: 0) {
                    Group(subviews: content()) { rows in
                        ForEach(rows) { row in
                            row
                            if row.id != rows.last?.id {
                                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                            }
                        }
                    }
                }
            }
            if let footer {
                Text(footer).font(UI.sans(13)).foregroundStyle(UI.text2)
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    var title: String
    var detail: String?
    /// Petite étiquette à côté du titre : « bêta » pour ce qui n'est pas encore au point.
    var badge: String?
    @ViewBuilder var control: () -> Control

    init(_ title: String, detail: String? = nil, badge: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.badge = badge
        self.control = control
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title).font(UI.sans(14))
                    if let badge {
                        // En capitales et en mauve : la seule touche de couleur des réglages, pour ce qui
                        // est encore en chantier.
                        Text(badge.uppercased())
                            .font(UI.sans(10, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(UI.beta)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill(UI.beta.opacity(0.16)))
                    }
                }
                if let detail {
                    Text(detail)
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct SettingToggle: View {
    var title: String
    var detail: String?
    var badge: String?
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, detail: String? = nil, badge: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.badge = badge
        _isOn = isOn
    }

    var body: some View {
        SettingRow(title, detail: detail, badge: badge) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(PlumeSwitch())
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Capte un raccourci : une touche avec modificateurs, ou au moins deux modificateurs
/// seuls (⌃⇧).
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var optional = false
    var onRecording: (Bool) -> Void = { _ in }

    @State private var recording = false
    @State private var monitor: Any?
    @State private var heldMask = 0

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? finish(nil) : begin() }) {
                Group {
                    if recording {
                        Text(tr("Tape le raccourci…")).foregroundStyle(UI.text)
                    } else if shortcut.isEmpty {
                        Text(HotkeyManager.describe(shortcut)).foregroundStyle(UI.text2)
                    } else {
                        Keycaps(shortcut: HotkeyManager.describe(shortcut))
                    }
                }
                .font(UI.sans(13, .medium))
                .padding(.horizontal, 10)
                .frame(minWidth: 86)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(recording ? UI.selected : UI.hover))
                .overlay(
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                        .strokeBorder(UI.text.opacity(recording ? 0.6 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .animation(UI.quick, value: recording)
            if optional, !shortcut.isEmpty, !recording {
                Button(action: { shortcut = .none }) {
                    Icon(.circleX, size: 14).foregroundStyle(UI.text3)
                }
                .buttonStyle(PressStyle())
                .help(tr("Retirer ce raccourci"))
            }
        }
        .onDisappear { finish(nil) }
    }

    private func begin() {
        recording = true
        heldMask = 0
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let mask = HotkeyManager.mask(from: event.modifierFlags)
            if event.type == .keyDown {
                if event.keyCode == 53 {  // Échap : on garde l'ancien raccourci
                    finish(nil)
                } else if mask != 0 || (96...122).contains(Int(event.keyCode)) {
                    finish(Shortcut(keyCode: Int(event.keyCode), modifiers: mask))
                }
                return nil
            }
            if mask == 0 {
                // Tout est relâché : un accord d'au moins deux modificateurs est valide.
                if heldMask.nonzeroBitCount >= 2 { finish(Shortcut(keyCode: nil, modifiers: heldMask)) }
                heldMask = 0
            } else {
                heldMask |= mask
            }
            return nil
        }
    }

    private func finish(_ new: Shortcut?) {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecording(false)
        if let new { shortcut = new }
    }
}
