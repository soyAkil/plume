import AppKit
import PlumeKit
import SwiftUI

// MARK: - History

struct HistoryPage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var library: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 324)
            Rectangle().fill(UI.line).frame(width: 1)
            ZStack {
                if library.filter == .cancelled {
                    if let recording = library.selectedCancelled {
                        CancelledDetail(recording: recording, app: app, library: library, player: library.player)
                            .id(recording.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    } else {
                        cancelledEmptyState.transition(.opacity)
                    }
                } else if let transcript = library.selected {
                    TranscriptDetail(transcript: transcript, library: library, player: library.player)
                        .id(transcript.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    emptyState.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(UI.ease, value: library.selection)
            .animation(UI.ease, value: library.cancelledSelection)
            .animation(UI.ease, value: library.filter)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(showingCancelled ? tr("Cancelled") : tr("History")).font(UI.sans(24, .medium)).tracking(-0.4)
                    Spacer()
                    if library.importing > 0 {
                        ProgressView().controlSize(.small).transition(.opacity)
                    }
                    PlumeButton(
                        icon: .undo, kind: showingCancelled ? .primary : .secondary,
                        help: showingCancelled ? tr("Back to the history") : tr("Cancelled recordings, still restorable")
                    ) {
                        Sounds.play(.tab)
                        withAnimation(UI.spring) { library.filter = showingCancelled ? .all : .cancelled }
                    }
                    PlumeButton(icon: .plus, help: tr("Transcribe an audio file")) { app.chooseFiles() }
                }
                HStack(spacing: 7) {
                    Icon(.search, size: 14).foregroundStyle(UI.text2)
                    TextField(tr("Search"), text: $library.query)
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
                if showingCancelled {
                    cancelledList
                } else {
                    transcriptList
                }
            }
        }
    }

    private var showingCancelled: Bool { library.filter == .cancelled }

    private var cancelledList: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(library.cancelledSections, id: \.title) { section in
                Text(section.title)
                    .font(UI.sans(12, .medium))
                    .foregroundStyle(UI.text2)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 3)
                ForEach(section.items) { recording in
                    CancelledRow(recording: recording, selected: library.cancelledSelection == recording.id) {
                        library.cancelledSelection = recording.id
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, UI.dockClearance)
    }

    private var transcriptList: some View {
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

    private var cancelledEmptyState: some View {
        VStack(spacing: 9) {
            Icon(.undo, size: 28).foregroundStyle(UI.text3)
            Text(tr("No cancelled recordings")).font(UI.sans(15, .medium))
            Text(
                app.settings.cancelledRetentionHours > 0
                    ? tr("A cancelled recording stays here for a while, so you can get it back.")
                    : tr("Cancelled recordings aren't kept: change it in Settings › Library.")
            )
            .font(UI.sans(13))
            .foregroundStyle(UI.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Icon(library.query.isEmpty ? .audioLines : .search, size: 28)
                .foregroundStyle(UI.text3)
            Text(library.query.isEmpty ? tr("No transcriptions") : tr("No results"))
                .font(UI.sans(15, .medium))
            if library.query.isEmpty {
                Text(tr("Dictate something, or drop an audio file into this window."))
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// History filters; the active tab's background slides from one to the other.
private struct FilterBar: View {
    @Binding var selection: HistoryFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.tabs) { filter in
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

/// A cancelled recording in the list: looks like a transcription, set back.
private struct CancelledRow: View {
    var recording: CancelledRecording
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Icon(recording.mode == .meeting ? .users : .mic, size: 13)
                    .foregroundStyle(selected ? UI.onText : UI.text3)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? UI.text : UI.hover))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Self.time.string(from: recording.createdAt))
                            .font(UI.mono(12))
                            .foregroundStyle(UI.text)
                        Text(recording.mode.label)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                        Spacer(minLength: 4)
                        Text(Format.clock(recording.duration))
                            .font(UI.mono(11))
                            .foregroundStyle(UI.text3)
                    }
                    Text(recording.preview ?? (recording.text == nil ? tr("Not transcribed yet") : tr("Nothing heard")))
                        .font(UI.sans(13))
                        .foregroundStyle(recording.preview == nil ? UI.text3 : UI.text2)
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

/// A cancelled recording: listen to it, restore it into history, or throw it away for good.
private struct CancelledDetail: View {
    var recording: CancelledRecording
    @ObservedObject var app: AppModel
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: AudioPlayerModel
    @State private var confirmingDelete = false

    private var audio: [URL] { PlumeSettings.shared.cancelled.audioURLs(for: recording) }
    private var restoring: Bool { library.restoring == recording.id }

    private var title: String {
        recording.mode == .meeting ? tr("Cancelled meeting") : tr("Cancelled dictation")
    }

    private var meta: String {
        let date = DateFormatter()
        date.locale = L10n.current.locale
        date.dateStyle = .medium
        date.timeStyle = .short
        var parts = [date.string(from: recording.createdAt), Format.duration(recording.duration)]
        if let app = recording.app { parts.append(app) }
        return parts.joined(separator: "  ·  ")
    }

    /// "Deleted automatically in 3 days".
    private var expiry: String? {
        let hours = app.settings.cancelledRetentionHours
        guard hours > 0 else { return nil }
        let end = recording.cancelledAt.addingTimeInterval(Double(hours) * 3600)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.current.locale
        formatter.unitsStyle = .full
        return tr("Deleted automatically") + " " + formatter.localizedString(for: end, relativeTo: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(UI.sans(20, .medium))
                            .tracking(-0.3)
                        Text(meta)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        if let text = recording.text, !text.isEmpty { CopyButton(text: text) }
                        PlumeButton(icon: .trash, help: tr("Delete for good")) { confirmingDelete = true }
                        PlumeButton(title: tr("Restore"), icon: .undo, kind: .primary, help: tr("Put it in the history, as if it had never been cancelled")) {
                            app.restoreCancelled(recording)
                        }
                        .disabled(restoring || library.restoring != nil)
                    }
                }

                if !audio.isEmpty {
                    PlayerBar(player: player, id: "annule-" + recording.id, urls: audio, length: recording.duration)
                        .padding(.top, 16)
                }

                HStack(spacing: 8) {
                    if restoring {
                        ProgressView().controlSize(.small)
                        Text(recording.mode == .meeting ? tr("Transcribing and separating voices…") : tr("Working…"))
                            .font(UI.sans(13)).foregroundStyle(UI.text2)
                    } else if let expiry {
                        Text(expiry).font(UI.sans(13)).foregroundStyle(UI.text3)
                    }
                }
                .padding(.top, 12)

                Rectangle().fill(UI.line).frame(height: 1).padding(.vertical, 18)

                if let text = recording.text, !text.isEmpty {
                    Text(text)
                        .font(UI.sans(15))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: 640, alignment: .leading)
                } else {
                    Text(
                        recording.mode == .meeting
                            ? tr("A cancelled meeting is only transcribed if you restore it. You can listen to it first.")
                            : (recording.text == nil ? tr("Not transcribed yet.") : tr("Nothing intelligible in this recording."))
                    )
                    .font(UI.sans(14))
                    .foregroundStyle(UI.text2)
                    .frame(maxWidth: 640, alignment: .leading)
                }
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(tr("Delete this recording?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("Delete"), role: .destructive) {
                Sounds.play(.refuse)
                library.deleteCancelled(recording)
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("It can't be restored afterwards."))
        }
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
        if transcript.speakers.count > 1 { parts.append("\(transcript.speakers.count) " + tr("speakers")) }
        parts.append("\(HomePage.number(Double(LibraryStats.wordCount(transcript.text)))) " + tr("words"))
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
                        .help(tr("Give a title"))
                        Text(meta)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        CopyButton(text: transcript.text, prominent: true)
                        exportMenu
                        PlumeButton(icon: .folder, help: tr("Show files in Finder")) { library.reveal(transcript) }
                        PlumeButton(icon: .trash, help: tr("Move to Trash")) { confirmingDelete = true }
                    }
                }

                if audio.isEmpty {
                    Text(tr("The audio recording was not kept."))
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
                        PlumeButton(title: tr("Transcribe again"), icon: .history, help: tr("Transcribe again with the current model")) {
                            library.retranscribe(transcript)
                        }
                        .disabled(working || reprocessing)
                    }
                    if transcript.mode != .dictation || LibraryStats.wordCount(transcript.text) > 120 {
                        PlumeButton(
                            title: transcript.summary == nil ? tr("Summarize") : tr("Summarize again"), icon: .sparkles,
                            help: aiAvailable ? tr("Key points, decisions and actions, by the local AI") : LocalAI.availability.reason
                        ) {
                            library.summarize(transcript)
                        }
                        .disabled(working || !aiAvailable)
                    }
                    if working {
                        ProgressView().controlSize(.small)
                        Text(tr("Working…")).font(UI.sans(13)).foregroundStyle(UI.text2)
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
        .confirmationDialog(tr("Delete this transcript?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("Move to Trash"), role: .destructive) {
                Sounds.play(.refuse)
                library.delete(transcript)
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("The text and the audio go to the Mac's Trash."))
        }
        .alert(
            tr("Rename the speaker"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(tr("Name"), text: $newName)
            Button(tr("Rename")) {
                if let renaming { library.rename(renaming, to: newName, in: transcript) }
                renaming = nil
            }
            Button(tr("Cancel"), role: .cancel) { renaming = nil }
        } message: {
            Text(String(format: tr("The new name replaces “%@” throughout the transcript."), renaming ?? ""))
        }
        .alert(tr("Transcript title"), isPresented: $editingTitle) {
            TextField(tr("Title"), text: $newTitle)
            Button(tr("Record")) { library.retitle(transcript, to: newTitle) }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Leave empty to go back to the date."))
        }
    }

    /// Markdown, text, subtitles or JSON, saved wherever you like.
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
        .help(tr("Export"))
    }

    /// The summary written by the local AI: key points, decisions, actions.
    private func summaryCard(_ summary: String) -> some View {
        Card(fill: UI.raised) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Icon(.listChecks, size: 14)
                    Text(tr("Summary")).font(UI.sans(14, .medium))
                    Text(tr("by the local AI")).font(UI.sans(12)).foregroundStyle(UI.text3)
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

    /// Redo the diarization, saying how many people were speaking if needed.
    private var voices: some View {
        HStack(spacing: 8) {
            Menu {
                Button(tr("Automatic detection")) { library.reprocess(transcript, speakers: nil) }
                Divider()
                ForEach(1...8, id: \.self) { count in
                    Button(count == 1 ? tr("1 person") : "\(count) " + tr("people")) { library.reprocess(transcript, speakers: count) }
                }
            } label: {
                HStack(spacing: 6) {
                    Icon(.users, size: 13)
                    Text(tr("Redo speaker separation")).font(UI.sans(13, .medium))
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
            .help(tr("If the voices are poorly separated, say how many people were talking."))
            if reprocessing {
                ProgressView().controlSize(.small)
                Text(tr("Listening again…")).font(UI.sans(13)).foregroundStyle(UI.text2)
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
                .help(tr("Rename this speaker"))
                Button {
                    player.play(id: transcript.id, urls: audio, from: segment.start)
                } label: {
                    Text(Format.clock(segment.start))
                        .font(UI.mono(11))
                        .foregroundStyle(UI.text3)
                }
                .buttonStyle(PressStyle())
                .help(tr("Listen from here"))
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

/// Player for the original recording: playback, position, duration.
private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel
    var id: String
    var urls: [URL]
    /// Known duration of the transcription, shown until the audio is opened.
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
            .help(tr("Listen to the recording"))
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

// MARK: - Vocabulary

struct VocabularyPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: tr("Vocabulary"),
                    subtitle: tr("Words the model gets wrong, and what to write instead. Or snippets: “my signature” becomes your full signature.")
                ) {
                    PlumeButton(title: tr("Add"), icon: .plus, kind: .primary) {
                        withAnimation(UI.spring) { settings.addReplacement() }
                    }
                }
                .rise(0)

                Card(padding: 6) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Text(tr("Heard")).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 14)
                            Text(tr("Written")).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .font(UI.sans(12, .medium))
                        .foregroundStyle(UI.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if settings.replacements.isEmpty {
                            Rectangle().fill(UI.line).frame(height: 1)
                            Text(tr("No replacements yet."))
                                .font(UI.sans(13))
                                .foregroundStyle(UI.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        ForEach($settings.replacements) { $item in
                            VStack(spacing: 0) {
                                Rectangle().fill(UI.line).frame(height: 1)
                                HStack(spacing: 10) {
                                    TextField(tr("what you say"), text: $item.original)
                                        .textFieldStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    Icon(.arrowRight, size: 13)
                                        .foregroundStyle(UI.text3)
                                        .frame(width: 14)
                                    // Several lines allowed: an address, a signature.
                                    TextField(tr("what should be written"), text: $item.with, axis: .vertical)
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
                                    .help(tr("Delete"))
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

                Text(tr("Replacements apply to whole words, regardless of case, at the end of each dictation or meeting. A line break in “Written” (⌥↩) makes a multi-line snippet."))
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

// MARK: - Settings

/// The settings groups, in sidebar order.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case general, shortcuts, dictation, meeting, ai, audio, model, library, access, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("General")
        case .shortcuts: return tr("Shortcuts")
        case .dictation: return tr("Dictation")
        case .meeting: return tr("Meeting")
        case .ai: return tr("Local AI")
        case .audio: return tr("Microphone & sounds")
        case .model: return tr("Model")
        case .library: return tr("Library")
        case .access: return tr("Access for an AI")
        case .permissions: return tr("Permissions")
        case .about: return tr("About")
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

/// Settings: a sidebar on the left, like history, and the chosen group on the
/// right. There are more and more of them; in a single column it was hard to find anything.
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
            // Each group arrives with its own cascade.
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
            Text(tr("Settings"))
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
            SettingRow(tr("Language"), detail: tr("For the window, the notch and the transcripts.")) {
                Picker("", selection: $settings.language) {
                    ForEach(Language.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingRow(tr("Appearance")) {
                Picker("", selection: $settings.appearance) {
                    Text(tr("Dark")).tag("dark")
                    Text(tr("Light")).tag("light")
                    Text(tr("Match system")).tag("system")
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingToggle(
                tr("Open Plume at login"),
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
        }
    }

    private var shortcuts: some View {
        SettingsSection("", footer: tr("Short press: start, then stop. Hold the dictation shortcut: talk for as long as you hold it.")) {
            SettingRow(tr("Dictate")) {
                ShortcutRecorder(shortcut: $settings.dictationShortcut, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Record a meeting"), detail: tr("Meeting mode can also be switched on by hovering the notch.")) {
                ShortcutRecorder(shortcut: $settings.meetingShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Game chat"), detail: tr("Press, speak, press again: in Minecraft the chat opens, the text is pasted and sent. Elsewhere, a plain dictation.")) {
                ShortcutRecorder(shortcut: $settings.gameChatShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Transform the selection"), detail: settings.ai.isAvailable
                ? tr("Select text, say an instruction (“translate to French”, “shorter”), and the local AI rewrites it. With nothing selected, it writes.")
                : (settings.ai.reason ?? "")) {
                ShortcutRecorder(shortcut: $settings.transformShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            .disabled(!settings.ai.isAvailable)
            SettingRow(
                tr("Cancel the dictation"),
                detail: tr("Only caught during a dictation: the rest of the time, the key does its usual job. One key or a combination, Esc included.")
            ) {
                ShortcutRecorder(shortcut: $settings.cancelShortcut, optional: true, keyOnly: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Restore the last cancelled recording"), detail: tr("Transcribes and pastes it, as if it had never been cancelled.")) {
                ShortcutRecorder(shortcut: $settings.restoreShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Paste the last dictation again"), detail: tr("When the paste failed, or to reuse it elsewhere.")) {
                ShortcutRecorder(shortcut: $settings.pasteLastShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
            SettingRow(tr("Open Plume")) {
                ShortcutRecorder(shortcut: $settings.openShortcut, optional: true, onRecording: settings.onRecordingShortcut)
            }
        }
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(tr("Pasting")) {
                SettingToggle(tr("Paste into the active field when done"), detail: tr("Otherwise the text is only copied. The clipboard is always restored afterwards."), isOn: $settings.pasteAfterDictation)
                SettingToggle(
                    tr("Fit the text to what surrounds the cursor"),
                    detail: tr("A space if the cursor touches a word, lowercase if the sentence has begun, no final period if it continues."),
                    isOn: $settings.smartInsert
                )
                .disabled(!settings.pasteAfterDictation)
                SettingToggle(
                    tr("Write as you speak"),
                    detail: tr("Words are typed into the field while you talk, instead of being pasted all at once at the end; when the model corrects itself, Plume erases and retypes. The AI clean-up does not apply then; the history keeps the complete version."),
                    badge: tr("beta"),
                    isOn: $settings.streamingPaste
                )
                .disabled(!settings.pasteAfterDictation)
            }
            SettingsSection(tr("Text")) {
                SettingToggle(tr("Remove hesitations and repeated words"), isOn: $settings.cleanup)
                SettingToggle(
                    tr("Voice commands"),
                    detail: tr("“New line”, “new paragraph”, “bullet point”, “question mark”, “open quote”, “scratch that”, “press enter”."),
                    isOn: $settings.voiceCommands)
            }
            SettingsSection(tr("While dictating")) {
                SettingToggle(tr("Show words as you speak"), detail: tr("The text scrolls under the notch while you speak."), isOn: $settings.liveTranscript)
                SettingToggle(
                    tr("Mute the computer while dictating"),
                    detail: tr("Music or video playing: the sound is muted while you talk, then restored."),
                    isOn: $settings.muteWhileDictating)
            }
        }
    }

    private var meeting: some View {
        SettingsSection("") {
            SettingToggle(
                tr("Also capture the computer's audio"),
                detail: tr("The other participants (Meet, Zoom, Teams…) are transcribed even with headphones, and each speaker is separated. Without headphones, the speakers' echo is removed from the microphone."),
                isOn: $settings.systemAudio)
            SettingToggle(
                tr("Offer to record when a call starts"),
                detail: tr("As soon as Zoom, Teams, FaceTime or Meet (in the browser) opens the microphone, the notch offers to record the meeting."),
                isOn: $settings.meetingDetection)
            SettingToggle(
                tr("Summarize every meeting"), detail: settings.ai.isAvailable
                    ? tr("Key points, decisions, actions and a title, as soon as the meeting is transcribed.")
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
                ? tr("Apple Intelligence, on this Mac: nothing is sent anywhere. Always optional; the raw text stays in the history.")
                : settings.ai.reason
        ) {
            SettingToggle(
                tr("Clean up dictations"),
                detail: tr("Punctuation, false starts and self-corrections (“no, sorry”) fixed by the AI. Per-app rules take precedence."),
                isOn: $settings.polish
            )
            .disabled(!settings.ai.isAvailable)
            SettingRow(tr("Instructions"), detail: tr("What the AI must respect when cleaning up.")) {
                TextField(tr("informal tone, no emojis, be direct…"), text: $settings.polishInstructions)
                    .textFieldStyle(.plain)
                    .font(UI.sans(13))
                    .padding(.horizontal, 10)
                    .frame(width: 270, height: 30)
                    .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))
            }
            .disabled(!settings.ai.isAvailable || !settings.polish)
            SettingRow(tr("Transform the selection"), detail: tr("The shortcut is set under Shortcuts: select text, say an instruction, the AI rewrites it.")) {
                Keycaps(shortcut: HotkeyManager.describe(settings.transformShortcut))
            }
            .disabled(!settings.ai.isAvailable)
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(
                tr("Microphone"),
                footer: settings.chosenMicrophoneMissing
                    ? tr("The chosen microphone is not connected: meanwhile, Plume uses the Mac's.")
                    : tr("Plume keeps this microphone no matter what: connecting earbuds or a Bluetooth headset changes nothing.")
            ) {
                SettingRow(tr("Microphone in use")) {
                    Picker("", selection: $settings.microphoneUID) {
                        Text(settings.microphones.first(where: \.isBuiltIn).map { "\($0.name) " + tr("(default)") } ?? tr("Mac microphone (default)"))
                            .tag("")
                        ForEach(settings.microphones.filter { !$0.isBuiltIn }) { device in
                            Text(device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name).tag(device.uid)
                        }
                        if settings.chosenMicrophoneMissing {
                            Text(tr("Chosen microphone (not connected)")).tag(settings.microphoneUID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 270)
                }
            }
            SettingsSection(tr("Sounds"), footer: tr("A soft sound at the start and end of each recording, and a quiet note on gestures in this window.")) {
                SettingToggle(tr("Plume sounds"), isOn: $settings.sounds)
                SettingRow(tr("Sound pack"), detail: tr("The sounds at the start and end of each recording.")) {
                    Picker("", selection: $settings.soundPack) {
                        ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    // Play the chosen pack.
                    .onChange(of: settings.soundPack) { _, _ in Sounds.play(.start) }
                    .disabled(!settings.sounds)
                }
                SettingRow(tr("Volume")) {
                    HStack(spacing: 8) {
                        Icon(.volume, size: 14).foregroundStyle(UI.text2)
                        Slider(value: $settings.soundVolume, in: 0.1...1) { editing in
                            // On release, the start sound: that is the one being adjusted.
                            if !editing { Sounds.play(.start) }
                        }
                        .controlSize(.small)
                        .tint(UI.text)
                        .frame(width: 150)
                        // A tick sounds at every fourteenth of the travel, higher and higher.
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
                ?? tr("All run on the Neural Engine, downloaded once from Hugging Face. Switching models reloads ~600 MB; the history's “Transcribe again” button lets you compare on the same recording.")
        ) {
            SettingRow(tr("Model"), detail: settings.model.detail) {
                Picker("", selection: $settings.model) {
                    ForEach(EngineModel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 290)
            }
            if settings.model == .custom {
                SettingRow(
                    tr("Model folder"),
                    detail: settings.customModelPath.isEmpty
                        ? tr("No folder chosen: Plume cannot transcribe anything.")
                        : (settings.customModelPath as NSString).abbreviatingWithTildeInPath
                ) {
                    PlumeButton(title: tr("Choose…"), icon: .folder) { settings.chooseModelDirectory() }
                }
            }
        }
    }

    private var library: some View {
        SettingsSection(
            "",
            footer: settings.retention == .nothing
                ? tr("Dictations are pasted, then forgotten: no text, no audio, no safety file, and the home statistics stop. Meetings, which have nowhere else to go, are still filed in the history.")
                : nil
        ) {
            SettingRow(tr("Folder"), detail: (settings.libraryPath as NSString).abbreviatingWithTildeInPath) {
                PlumeButton(title: tr("Change…")) { settings.chooseLibrary() }
            }
            SettingRow(tr("Keep from each dictation"), detail: tr("Audio lets you listen again and re-transcribe from the history.")) {
                Picker("", selection: $settings.retention) {
                    ForEach(SettingsModel.Retention.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingRow(tr("Keep audio"), detail: tr("The text stays. Older audio is deleted at launch.")) {
                Picker("", selection: $settings.audioRetentionDays) {
                    Text(tr("Always")).tag(0)
                    Text(tr("90 days")).tag(90)
                    Text(tr("30 days")).tag(30)
                    Text(tr("7 days")).tag(7)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .disabled(settings.retention != .textAndAudio)
            SettingRow(
                tr("Keep cancelled recordings"),
                detail: tr("A dictation or meeting cancelled by mistake can be restored from the history, the menu or a shortcut. After this delay, it is deleted.")
            ) {
                Picker("", selection: $settings.cancelledRetentionHours) {
                    Text(tr("Don't keep")).tag(0)
                    Text(tr("1 hour")).tag(1)
                    Text(tr("24 hours")).tag(24)
                    Text(tr("7 days")).tag(24 * 7)
                    Text(tr("30 days")).tag(24 * 30)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingRow(tr("All settings"), detail: tr("Shortcuts, options, vocabulary and applications in one file, for another Mac.")) {
                HStack(spacing: 6) {
                    PlumeButton(title: tr("Import…")) { settings.importSettings() }
                    PlumeButton(title: tr("Export…"), icon: .fileDown) { settings.exportSettings() }
                }
            }
        }
    }

    private var access: some View {
        SettingsSection(
            "",
            footer: settings.integrationMessage
                ?? tr("An assistant can read your transcripts: through the library folder, the plume command, or Plume's MCP server.")
        ) {
            SettingRow(
                tr("plume command"),
                detail: !settings.commandInstalled
                    ? tr("plume last, plume search… in a terminal.")
                    : (settings.commandOnPath
                        ? tr("Installed in ~/.local/bin.")
                        : tr("Installed in ~/.local/bin — add that folder to your PATH to call it by name."))
            ) {
                LinkState(done: settings.commandInstalled, action: tr("Install")) { settings.installCommand() }
            }
            SettingRow(tr("Claude Code"), detail: tr("Registers Plume's MCP server for all your projects.")) {
                HStack(spacing: 6) {
                    if !settings.claudeCodeConnected {
                        PlumeButton(icon: .copy, help: tr("Copy the command to run yourself"), sound: .confirm) {
                            Paster.copy(Integrations.claudeCodeCommand)
                        }
                    }
                    if settings.connectingClaudeCode {
                        ProgressView().controlSize(.small)
                    } else {
                        LinkState(done: settings.claudeCodeConnected, action: tr("Connect")) { settings.connectClaudeCode() }
                    }
                }
            }
            if Integrations.claudeDesktopPresent {
                SettingRow(tr("Claude Desktop"), detail: tr("Adds Plume to its configuration, leaving the rest untouched.")) {
                    LinkState(done: settings.claudeDesktopConnected, action: tr("Connect")) { settings.connectClaudeDesktop() }
                }
            }
            SettingRow(tr("Another assistant"), detail: tr("The MCP configuration to paste into its settings file.")) {
                PlumeButton(title: tr("Copy"), icon: .copy, sound: .confirm) { Paster.copy(Integrations.configuration) }
            }
        }
    }

    private var permissions: some View {
        SettingsSection("") {
            PermissionRow(title: tr("Microphone access"), detail: tr("To hear your voice."), granted: settings.microphoneGranted, action: settings.requestMicrophone)
                .padding(.horizontal, 14).padding(.vertical, 10)
            PermissionRow(title: tr("Accessibility"), detail: tr("To paste the text into the active field."), granted: settings.accessibilityGranted, action: settings.requestAccessibility)
                .padding(.horizontal, 14).padding(.vertical, 10)
            SettingRow(tr("System audio recording"), detail: tr("Asked at the first meeting, to capture the computer's audio.")) {
                PlumeButton(title: tr("Open settings")) { Permissions.openSettings(.audioCapture) }
            }
        }
    }

    private var about: some View {
        SettingsSection("") {
            SettingRow("Plume \(Updates.version)", detail: tr("Local dictation and transcription: nothing leaves this Mac.")) {
                if updates.isAvailable {
                    PlumeButton(title: tr("Check for updates")) { updates.check() }
                }
            }
            if updates.isAvailable {
                SettingToggle(tr("Check for updates automatically"), isOn: $updates.automatic)
            }
            SettingRow(tr("Licenses"), detail: tr("Models, fonts, icons and libraries used by Plume.")) {
                PlumeButton(title: tr("Show")) {
                    if let url = Bundle.main.url(forResource: "LICENSES", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

/// An entry of the settings sidebar.
private struct SettingsGroupRow: View {
    var group: SettingsGroup
    var selected: Bool
    /// An alert dot: a permission is missing.
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

/// State of a link with the outside: a button to set it up, a check mark once done.
private struct LinkState: View {
    var done: Bool
    var action: String
    var perform: () -> Void

    var body: some View {
        if done {
            HStack(spacing: 6) {
                Icon(.circleCheck, size: 15)
                Text(tr("Done")).font(UI.sans(13, .medium))
            }
            .foregroundStyle(UI.success)
            .frame(height: 30)
            .transition(.scale.combined(with: .opacity))
        } else {
            PlumeButton(title: action, kind: .primary, action: perform)
        }
    }
}

/// A settings group: a title, a card whose rows are separated by a thin rule.
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
                // A thin rule between each row of the section.
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
    /// Small label next to the title: "beta" for what is not quite ready yet.
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
                        // In capitals and mauve: the only touch of color in settings, for what
                        // is still a work in progress.
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

/// Captures a shortcut: a key with modifiers, or at least two modifiers
/// alone (⌃⇧).
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var optional = false
    /// A key, alone or with modifiers, Escape included; no chord of modifiers alone.
    /// To cancel the capture, click the button again.
    var keyOnly = false
    var onRecording: (Bool) -> Void = { _ in }

    @State private var recording = false
    @State private var monitor: Any?
    @State private var heldMask = 0

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? finish(nil) : begin() }) {
                Group {
                    if recording {
                        Text(tr("Press the shortcut…")).foregroundStyle(UI.text)
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
                .help(tr("Remove this shortcut"))
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
                if keyOnly, event.keyCode == 53 {  // Escape, alone or not, is a key like any other
                    finish(Shortcut(keyCode: 53, modifiers: mask))
                } else if event.keyCode == 53 {  // Escape: keep the old shortcut
                    finish(nil)
                } else if mask != 0 || (96...122).contains(Int(event.keyCode)) {
                    finish(Shortcut(keyCode: Int(event.keyCode), modifiers: mask))
                }
                return nil
            }
            if mask == 0 {
                // Everything is released: a chord of at least two modifiers is valid.
                if !keyOnly, heldMask.nonzeroBitCount >= 2 { finish(Shortcut(keyCode: nil, modifiers: heldMask)) }
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
