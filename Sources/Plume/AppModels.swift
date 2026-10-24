import AVFoundation
import AppKit
import PlumeKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case home, history, vocabulary, apps, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return tr("Home")
        case .history: return tr("History")
        case .vocabulary: return tr("Vocabulary")
        case .apps: return tr("Applications")
        case .settings: return tr("Settings")
        }
    }

    var glyph: Glyph {
        switch self {
        case .home: return .home
        case .history: return .history
        case .vocabulary: return .book
        case .apps: return .appWindow
        case .settings: return .sliders
        }
    }
}

/// State shared by the whole Plume window.
@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .home {
        // Each page opens on its own note, like the portfolio sections.
        didSet { if page != oldValue { Sounds.play(.page(Page.allCases.firstIndex(of: page) ?? 0)) } }
    }
    @Published private(set) var stats = LibraryStats()
    /// The three latest transcriptions, for home.
    @Published private(set) var recent: [Transcript] = []
    /// The "Dictate" button: the window steps aside and recording starts.
    var onStartFromWindow: () -> Void = {}

    let session: SessionController
    let library = LibraryModel()
    let settings = SettingsModel()

    init(session: SessionController) {
        self.session = session
    }

    /// Reloads the library and recomputes the home figures.
    func refresh() {
        library.reload()
        let store = PlumeSettings.shared.store
        Task {
            let (computed, latest) = await Task.detached(priority: .utility) {
                (LibraryStats(transcripts: store.list()), store.list(limit: 3))
            }.value
            stats = computed
            recent = latest
        }
    }

    /// Immediate variant, for off-screen rendering of the mockups.
    func refreshNow() {
        library.reload()
        stats = LibraryStats(transcripts: PlumeSettings.shared.store.list())
        recent = PlumeSettings.shared.store.list(limit: 3)
    }

    func open(_ transcript: Transcript) {
        page = .history
        library.select(transcript)
    }

    /// Restores a cancelled recording from history, then opens it.
    func restoreCancelled(_ recording: CancelledRecording) {
        guard library.restoring == nil else { return }
        library.restoring = recording.id
        library.player.stop()
        session.restoreCancelled(id: recording.id, paste: false) { [weak self] transcript in
            guard let self else { return }
            self.library.restoring = nil
            if let transcript, PlumeSettings.shared.store.load(id: transcript.id) != nil {
                self.open(transcript)
            } else {
                self.library.reload()
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        let audio = urls.filter(Importer.isAudio)
        guard !audio.isEmpty else { return }
        page = .history
        library.importing += audio.count
        Task {
            var last: Transcript?
            for url in audio {
                if let transcript = await session.importFile(url) { last = transcript }
                library.importing -= 1
            }
            refresh()
            if let last { library.select(last) }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = tr("Transcribe")
        panel.message = tr("Choose one or more audio files to transcribe.")
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictation, meeting, imported
    /// Cancelled recordings that can still be restored: opened by their own button, not
    /// by the filter bar.
    case cancelled

    /// The filter bar tabs.
    static let tabs: [HistoryFilter] = [.all, .dictation, .meeting, .imported]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("All")
        case .dictation: return tr("Dictations")
        case .meeting: return tr("Meetings")
        case .imported: return tr("Imports")
        case .cancelled: return tr("Cancelled")
        }
    }

    var mode: RecordingMode? {
        switch self {
        case .all, .cancelled: return nil
        case .dictation: return .dictation
        case .meeting: return .meeting
        case .imported: return .imported
        }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var transcripts: [Transcript] = []
    @Published var selection: String?
    @Published var query = "" {
        didSet { if query != oldValue { reload() } }
    }
    @Published var filter: HistoryFilter = .all {
        didSet { if filter != oldValue { reload() } }
    }
    /// Number of files being transcribed.
    @Published var importing = 0
    /// Cancelled recordings that can still be restored (`.cancelled` filter).
    @Published var cancelled: [CancelledRecording] = []
    @Published var cancelledSelection: String?
    /// Cancelled recording being restored.
    @Published var restoring: String?
    /// Transcription whose diarization is being redone.
    @Published var reprocessing: String?

    let player = AudioPlayerModel()
    private var store: TranscriptStore { PlumeSettings.shared.store }

    var selected: Transcript? {
        transcripts.first { $0.id == selection }
    }

    var selectedCancelled: CancelledRecording? {
        cancelled.first { $0.id == cancelledSelection }
    }

    func reload() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if filter == .cancelled {
            var items = PlumeSettings.shared.cancelled.list()
            if !trimmed.isEmpty {
                items = items.filter { ($0.text ?? "").localizedCaseInsensitiveContains(trimmed) || ($0.app ?? "").localizedCaseInsensitiveContains(trimmed) }
            }
            cancelled = items
            if cancelledSelection == nil || !items.contains(where: { $0.id == cancelledSelection }) {
                cancelledSelection = items.first?.id
            }
            return
        }
        var items = trimmed.isEmpty ? store.list(limit: 800) : store.search(trimmed, limit: 300)
        if let mode = filter.mode { items = items.filter { $0.mode == mode } }
        transcripts = items
        if selection == nil || !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
    }

    func select(_ transcript: Transcript) {
        if !query.isEmpty { query = "" }
        if filter != .all { filter = .all }
        reload()
        selection = transcript.id
    }

    func delete(_ transcript: Transcript) {
        player.stop()
        try? store.delete(id: transcript.id)
        selection = nil
        reload()
    }

    /// Permanently deletes a cancelled recording.
    func deleteCancelled(_ recording: CancelledRecording) {
        player.stop()
        PlumeSettings.shared.cancelled.delete(id: recording.id)
        cancelledSelection = nil
        reload()
    }

    /// Sections by recording day, like history.
    var cancelledSections: [(title: String, items: [CancelledRecording])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: cancelled) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            (Self.dayTitle(day), (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    func rename(_ speaker: String, to name: String, in transcript: Transcript) {
        _ = try? store.renameSpeaker(id: transcript.id, from: speaker, to: name)
        reload()
    }

    /// Gives (or removes) a title on a transcription.
    func retitle(_ transcript: Transcript, to title: String) {
        guard var updated = store.load(id: transcript.id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? nil : trimmed
        try? store.save(updated)
        reload()
    }

    /// Transcriptions being re-transcribed or re-summarized.
    @Published var working = Set<String>()

    /// Transcribes the kept audio again with the current model (model changed, first result failed).
    func retranscribe(_ transcript: Transcript) {
        guard !working.contains(transcript.id), let url = audioURLs(for: transcript).first else { return }
        working.insert(transcript.id)
        player.stop()
        let settings = PlumeSettings.shared
        Task {
            do {
                let engine = SpeechEngine.shared
                try await engine.prepare(model: settings.model)
                let samples = try AudioIO.loadSamples(url)
                guard var updated = store.load(id: transcript.id) else { return }
                if transcript.mode == .dictation {
                    let result = try await Pipeline.dictation(
                        samples: samples, engine: engine, options: DictationOptions(settings: settings))
                    updated.text = result.text
                    updated.rawText = result.raw
                } else {
                    _ = try await Pipeline.reprocess(transcript, speakerCount: nil)
                    updated = store.load(id: transcript.id) ?? updated
                }
                updated.engine = await engine.modelName
                try store.save(updated)
            } catch {
                Log.write("new transcription failed: \(error.localizedDescription)")
            }
            working.remove(transcript.id)
            reload()
        }
    }

    /// Summarizes with the local AI (key points, decisions, actions) and suggests a title.
    func summarize(_ transcript: Transcript) {
        guard !working.contains(transcript.id) else { return }
        working.insert(transcript.id)
        Task {
            do {
                let summary = try await LocalAI.summarize(transcript)
                if var updated = store.load(id: transcript.id) {
                    updated.summary = summary.markdown
                    if updated.title == nil { updated.title = summary.title }
                    try store.save(updated)
                }
            } catch {
                Log.write("summary failed: \(error.localizedDescription)")
            }
            working.remove(transcript.id)
            reload()
        }
    }

    /// Saves the transcription in the chosen format, where the user decides.
    func export(_ transcript: Transcript, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.fileName(for: transcript, format: format)
        panel.canCreateDirectories = true
        panel.prompt = tr("Export")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Exporter.render(transcript, as: format).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Listens to the kept audio again to redo the diarization, possibly with a
    /// forced number of people.
    func reprocess(_ transcript: Transcript, speakers: Int?) {
        guard reprocessing == nil else { return }
        reprocessing = transcript.id
        player.stop()
        Task {
            do {
                _ = try await Pipeline.reprocess(transcript, speakerCount: speakers)
            } catch {
                Log.write("new speaker separation failed: \(error.localizedDescription)")
            }
            reprocessing = nil
            reload()
        }
    }

    func audioURLs(for transcript: Transcript) -> [URL] {
        store.audioURLs(for: transcript).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func reveal(_ transcript: Transcript) {
        let audio = audioURLs(for: transcript)
        NSWorkspace.shared.activateFileViewerSelecting([store.markdownURL(for: transcript)] + audio)
    }

    /// Sections by day, from the most recent to the oldest.
    var sections: [(title: String, items: [Transcript])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: transcripts) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            (Self.dayTitle(day), groups[day] ?? [])
        }
    }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return tr("Today") }
        if calendar.isDateInYesterday(day) { return tr("Yesterday") }
        let text = dayFormatter.string(from: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Playback of a transcription's original recording (microphone and system audio
/// played together for a meeting).
@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published private(set) var loadedID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var players: [AVAudioPlayer] = []
    private var ticker: Timer?

    func isLoaded(_ id: String) -> Bool { loadedID == id }

    /// Opens a transcription's audio. Called only when the user wants to listen: browsing
    /// history must not wake the audio system.
    func load(id: String, urls: [URL]) {
        guard loadedID != id else { return }
        stop()
        players = urls.compactMap { try? AVAudioPlayer(contentsOf: $0) }
        duration = players.map(\.duration).max() ?? 0
        currentTime = 0
        loadedID = players.isEmpty ? nil : id
    }

    func toggle(id: String, urls: [URL]) {
        load(id: id, urls: urls)
        isPlaying ? pause() : play()
    }

    func play(id: String, urls: [URL], from time: TimeInterval) {
        load(id: id, urls: urls)
        play(from: time)
    }

    func seek(id: String, urls: [URL], fraction: Double) {
        load(id: id, urls: urls)
        seek(to: fraction * duration)
    }

    func play(from time: TimeInterval? = nil) {
        guard !players.isEmpty else { return }
        if let time { seek(to: time) }
        if currentTime >= duration - 0.05 { seek(to: 0) }
        let start = (players.first?.deviceCurrentTime ?? 0) + 0.03
        for player in players where player.currentTime < player.duration - 0.05 {
            player.play(atTime: start)
        }
        isPlaying = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        players.forEach { $0.pause() }
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        for player in players {
            player.currentTime = min(clamped, max(0, player.duration - 0.02))
        }
        currentTime = clamped
    }

    func stop() {
        pause()
        players.forEach { $0.stop() }
        players = []
        loadedID = nil
        currentTime = 0
        duration = 0
    }

    private func tick() {
        guard isPlaying else { return }
        let longest = players.max { $0.duration < $1.duration }
        if let longest, longest.isPlaying {
            currentTime = longest.currentTime
        } else if !players.contains(where: \.isPlaying) {
            // End of the recording.
            pause()
            currentTime = duration
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    private let settings = PlumeSettings.shared
    var onShortcutsChanged: () -> Void = {}
    var onModelChanged: () -> Void = {}
    var onRecordingShortcut: (Bool) -> Void = { _ in }
    var onAppearanceChanged: () -> Void = {}
    var onRulesChanged: () -> Void = {}
    var onLanguageChanged: () -> Void = {}

    /// Interface language; the window is fully redrawn when it changes.
    @Published var language: Language {
        didSet {
            settings.language = language
            L10n.current = language
            onLanguageChanged()
        }
    }

    @Published var dictationShortcut: Shortcut { didSet { settings.dictationShortcut = dictationShortcut; onShortcutsChanged() } }
    @Published var meetingShortcut: Shortcut { didSet { settings.meetingShortcut = meetingShortcut; onShortcutsChanged() } }
    @Published var openShortcut: Shortcut { didSet { settings.openShortcut = openShortcut; onShortcutsChanged() } }
    @Published var pasteLastShortcut: Shortcut { didSet { settings.pasteLastShortcut = pasteLastShortcut; onShortcutsChanged() } }
    @Published var transformShortcut: Shortcut { didSet { settings.transformShortcut = transformShortcut; onShortcutsChanged() } }
    @Published var cancelShortcut: Shortcut { didSet { settings.cancelShortcut = cancelShortcut; onShortcutsChanged() } }
    @Published var restoreShortcut: Shortcut { didSet { settings.restoreShortcut = restoreShortcut; onShortcutsChanged() } }
    @Published var gameChatShortcut: Shortcut { didSet { settings.gameChatShortcut = gameChatShortcut; onShortcutsChanged() } }
    /// Hours during which a cancelled recording stays restorable (0: never kept).
    @Published var cancelledRetentionHours: Int {
        didSet {
            settings.cancelledRetentionHours = cancelledRetentionHours
            onCancelledRetentionChanged()
        }
    }
    var onCancelledRetentionChanged: () -> Void = {}
    @Published var liveTranscript: Bool { didSet { settings.liveTranscript = liveTranscript } }
    @Published var modeSwitchAtStart: Bool { didSet { settings.modeSwitchAtStart = modeSwitchAtStart } }
    @Published var pasteAfterDictation: Bool { didSet { settings.pasteAfterDictation = pasteAfterDictation } }
    @Published var restoreClipboard: Bool { didSet { settings.restoreClipboard = restoreClipboard } }
    @Published var cleanup: Bool { didSet { settings.cleanup = cleanup } }
    @Published var voiceCommands: Bool { didSet { settings.voiceCommands = voiceCommands } }
    @Published var smartInsert: Bool { didSet { settings.smartInsert = smartInsert } }
    @Published var streamingPaste: Bool { didSet { settings.streamingPaste = streamingPaste } }
    @Published var muteWhileDictating: Bool { didSet { settings.muteWhileDictating = muteWhileDictating } }
    @Published var meetingDetection: Bool { didSet { settings.meetingDetection = meetingDetection } }
    @Published var polish: Bool { didSet { settings.polish = polish } }
    @Published var polishInstructions: String { didSet { settings.polishInstructions = polishInstructions } }
    @Published var autoSummary: Bool { didSet { settings.autoSummary = autoSummary } }
    @Published var audioRetentionDays: Int { didSet { settings.audioRetentionDays = audioRetentionDays } }
    @Published var sounds: Bool { didSet { settings.sounds = sounds } }
    @Published var soundVolume: Double { didSet { settings.soundVolume = soundVolume } }
    @Published var soundPack: SoundPack { didSet { settings.soundPack = soundPack.rawValue } }
    @Published var systemAudio: Bool { didSet { settings.systemAudioInMeeting = systemAudio } }
    @Published var keepAudio: Bool { didSet { settings.keepAudio = keepAudio } }
    @Published var keepHistory: Bool { didSet { settings.keepHistory = keepHistory } }
    @Published var model: EngineModel { didSet { settings.model = model; onModelChanged() } }
    /// Custom model folder (empty string: none).
    @Published var customModelPath: String
    /// What is wrong with the chosen model folder, if anything.
    @Published var modelMessage: String?
    @Published var appearance: String { didSet { settings.appearance = appearance; onAppearanceChanged() } }
    /// Chosen microphone: device identifier, or empty string for the Mac's built-in microphone.
    @Published var microphoneUID: String { didSet { settings.microphoneUID = microphoneUID.isEmpty ? nil : microphoneUID } }
    @Published private(set) var microphones: [InputDevice] = AudioDevices.inputs()
    @Published var replacements: [Replacement] { didSet { ReplacementStore.save(replacements) } }
    @Published var rules: [AppRule] { didSet { AppRuleStore.save(rules); onRulesChanged() } }
    /// The local AI: available, or why not.
    @Published private(set) var ai = LocalAI.availability
    @Published var libraryPath: String
    @Published var launchAtLogin: Bool
    @Published var microphoneGranted = Permissions.microphoneGranted
    @Published var accessibilityGranted = Paster.isTrusted
    // Links with the terminal and the assistants.
    @Published private(set) var commandInstalled = Integrations.commandInstalled
    @Published private(set) var commandOnPath = true
    @Published private(set) var claudeCodeConnected = Integrations.claudeCodeConnected
    @Published private(set) var claudeDesktopConnected = Integrations.claudeDesktopConnected
    @Published private(set) var connectingClaudeCode = false
    /// Last incident of a connection, shown under the section.
    @Published var integrationMessage: String?

    init() {
        dictationShortcut = settings.dictationShortcut
        meetingShortcut = settings.meetingShortcut
        openShortcut = settings.openShortcut
        pasteLastShortcut = settings.pasteLastShortcut
        transformShortcut = settings.transformShortcut
        cancelShortcut = settings.cancelShortcut
        restoreShortcut = settings.restoreShortcut
        gameChatShortcut = settings.gameChatShortcut
        cancelledRetentionHours = settings.cancelledRetentionHours
        liveTranscript = settings.liveTranscript
        modeSwitchAtStart = settings.modeSwitchAtStart
        pasteAfterDictation = settings.pasteAfterDictation
        restoreClipboard = settings.restoreClipboard
        cleanup = settings.cleanup
        voiceCommands = settings.voiceCommands
        smartInsert = settings.smartInsert
        streamingPaste = settings.streamingPaste
        muteWhileDictating = settings.muteWhileDictating
        meetingDetection = settings.meetingDetection
        polish = settings.polish
        polishInstructions = settings.polishInstructions
        autoSummary = settings.autoSummary
        audioRetentionDays = settings.audioRetentionDays
        rules = AppRuleStore.load()
        sounds = settings.sounds
        soundVolume = settings.soundVolume
        soundPack = SoundPack(rawValue: settings.soundPack) ?? .standard
        systemAudio = settings.systemAudioInMeeting
        keepAudio = settings.keepAudio
        keepHistory = settings.keepHistory
        model = settings.model
        customModelPath = settings.customModelURL?.path ?? ""
        language = settings.language
        appearance = settings.appearance
        microphoneUID = settings.microphoneUID ?? ""
        libraryPath = settings.libraryURL.path
        replacements = ReplacementStore.load()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// What Plume keeps of a dictation: everything, the text, or nothing.
    enum Retention: String, CaseIterable, Identifiable {
        case textAndAudio, textOnly, nothing

        var id: String { rawValue }

        var label: String {
            switch self {
            case .textAndAudio: return tr("Text and audio")
            case .textOnly: return tr("Text only")
            case .nothing: return tr("Nothing")
            }
        }
    }

    var retention: Retention {
        get { !keepHistory ? .nothing : (keepAudio ? .textAndAudio : .textOnly) }
        set {
            keepHistory = newValue != .nothing
            keepAudio = newValue == .textAndAudio
        }
    }

    // MARK: Model

    /// Chooses the folder of a Parakeet-format model, and switches to it if it is complete.
    func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = tr("Use this model")
        panel.message = tr("Choose the folder that contains Preprocessor, Encoder, Decoder, JointDecision (.mlmodelc) and parakeet_vocab.json.")
        if let current = settings.customModelURL { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let missing = SpeechEngine.missingCustomFiles(in: url)
        guard missing.isEmpty else {
            modelMessage = String(format: tr("Missing from this folder: %@."), missing.joined(separator: ", "))
            return
        }
        modelMessage = nil
        settings.customModelURL = url
        customModelPath = url.path
        if model == .custom { onModelChanged() } else { model = .custom }
    }

    var permissionsMissing: Bool { !microphoneGranted || !accessibilityGranted }

    /// Reloads the list of connected microphones.
    func refreshMicrophones() {
        let devices = AudioDevices.inputs()
        if devices != microphones { microphones = devices }
    }

    /// The chosen microphone is not connected right now (headphones off, for example).
    var chosenMicrophoneMissing: Bool {
        !microphoneUID.isEmpty && !microphones.contains { $0.uid == microphoneUID }
    }

    func refreshPermissions() {
        let microphone = Permissions.microphoneGranted
        let accessibility = Paster.isTrusted
        if microphone != microphoneGranted { microphoneGranted = microphone }
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
    }

    func requestMicrophone() {
        if Permissions.microphoneUndetermined {
            Permissions.requestMicrophone { [weak self] _ in self?.refreshPermissions() }
        } else {
            Permissions.openSettings(.microphone)
        }
    }

    func requestAccessibility() {
        Paster.requestTrust()
        Permissions.openSettings(.accessibility)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Choose")
        panel.directoryURL = settings.libraryURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.libraryURL = url
            libraryPath = url.path
        }
    }

    func addReplacement() {
        replacements.append(Replacement(original: "", with: ""))
    }

    func refreshAI() {
        let now = LocalAI.availability
        if now != ai { ai = now }
    }

    // MARK: Applications

    /// Chooses an app in the Finder and creates a rule for it (one per app).
    func addRule() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("Add")
        panel.message = tr("Choose the applications that get their own dictation rule.")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !rules.contains(where: { $0.bundleID == id })
            else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            rules.append(AppRule(bundleID: id, name: name, style: Self.suggestedStyle(for: id)))
        }
    }

    /// The "all other applications" rule, created if needed.
    func addDefaultRule() {
        guard !rules.contains(where: { $0.bundleID == "*" }) else { return }
        rules.append(AppRule(bundleID: "*", name: tr("All other applications")))
    }

    /// Messaging apps get the "message" style right away.
    static func suggestedStyle(for bundleID: String) -> DictationStyle {
        let messaging = ["slack", "messages", "whatsapp", "telegram", "discord", "ichat", "signal", "teams", "messenger"]
        return messaging.contains(where: { bundleID.lowercased().contains($0) }) ? .message : .standard
    }

    /// The app's icon, if it is installed.
    func icon(for rule: AppRule) -> NSImage? {
        guard rule.bundleID != "*", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Settings backup

    /// Writes all settings (shortcuts, options, vocabulary, applications) to a file,
    /// to carry them over to another Mac.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tr("Plume Settings.json")
        panel.prompt = tr("Record")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export(to: url)
            integrationMessage = nil
        } catch {
            integrationMessage = tr("The settings could not be saved:") + " \(error.localizedDescription)"
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = tr("Import file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.import(from: url)
            reloadFromSettings()
            onShortcutsChanged()
            onRulesChanged()
        } catch {
            integrationMessage = tr("This file could not be read:") + " \(error.localizedDescription)"
        }
    }

    /// Reloads the settings from disk, after an import.
    private func reloadFromSettings() {
        dictationShortcut = settings.dictationShortcut
        meetingShortcut = settings.meetingShortcut
        openShortcut = settings.openShortcut
        pasteLastShortcut = settings.pasteLastShortcut
        transformShortcut = settings.transformShortcut
        cancelShortcut = settings.cancelShortcut
        restoreShortcut = settings.restoreShortcut
        gameChatShortcut = settings.gameChatShortcut
        cancelledRetentionHours = settings.cancelledRetentionHours
        liveTranscript = settings.liveTranscript
        modeSwitchAtStart = settings.modeSwitchAtStart
        pasteAfterDictation = settings.pasteAfterDictation
        restoreClipboard = settings.restoreClipboard
        cleanup = settings.cleanup
        voiceCommands = settings.voiceCommands
        smartInsert = settings.smartInsert
        streamingPaste = settings.streamingPaste
        muteWhileDictating = settings.muteWhileDictating
        meetingDetection = settings.meetingDetection
        polish = settings.polish
        polishInstructions = settings.polishInstructions
        autoSummary = settings.autoSummary
        audioRetentionDays = settings.audioRetentionDays
        sounds = settings.sounds
        soundVolume = settings.soundVolume
        soundPack = SoundPack(rawValue: settings.soundPack) ?? .standard
        systemAudio = settings.systemAudioInMeeting
        keepAudio = settings.keepAudio
        keepHistory = settings.keepHistory
        model = settings.model
        language = settings.language
        appearance = settings.appearance
        replacements = ReplacementStore.load()
        rules = AppRuleStore.load()
    }

    // MARK: Terminal and assistants

    func refreshIntegrations() {
        commandInstalled = Integrations.commandInstalled
        claudeCodeConnected = Integrations.claudeCodeConnected
        claudeDesktopConnected = Integrations.claudeDesktopConnected
        guard commandInstalled else { return }
        Task { commandOnPath = await Integrations.commandOnPath() }
    }

    func installCommand() {
        do {
            try Integrations.installCommand()
            integrationMessage = nil
        } catch {
            integrationMessage = tr("The command could not be installed:") + " \(error.localizedDescription)"
        }
        refreshIntegrations()
    }

    func connectClaudeCode() {
        guard !connectingClaudeCode else { return }
        connectingClaudeCode = true
        Task {
            integrationMessage = await Integrations.connectClaudeCode()
            connectingClaudeCode = false
            refreshIntegrations()
        }
    }

    func connectClaudeDesktop() {
        do {
            try Integrations.connectClaudeDesktop()
            integrationMessage = tr("Claude Desktop will see Plume the next time it launches.")
        } catch {
            integrationMessage = tr("Claude Desktop's configuration could not be changed.")
        }
        refreshIntegrations()
    }
}
