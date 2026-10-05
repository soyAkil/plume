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
        case .home: return tr("Accueil")
        case .history: return tr("Historique")
        case .vocabulary: return tr("Vocabulaire")
        case .apps: return tr("Applications")
        case .settings: return tr("Réglages")
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

/// État partagé par toute la fenêtre de Plume.
@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .home {
        // Chaque page s'ouvre sur sa propre note, comme les sections du portfolio.
        didSet { if page != oldValue { Sounds.play(.page(Page.allCases.firstIndex(of: page) ?? 0)) } }
    }
    @Published private(set) var stats = LibraryStats()
    /// Les trois dernières transcriptions, pour l'accueil.
    @Published private(set) var recent: [Transcript] = []
    /// Le bouton « Commencer une transcription » : la fenêtre se range, l'enregistrement part.
    var onStartFromWindow: () -> Void = {}

    let session: SessionController
    let library = LibraryModel()
    let settings = SettingsModel()

    init(session: SessionController) {
        self.session = session
    }

    /// Relit la bibliothèque et recalcule les chiffres de l'accueil.
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

    /// Variante immédiate, pour le rendu hors écran des maquettes.
    func refreshNow() {
        library.reload()
        stats = LibraryStats(transcripts: PlumeSettings.shared.store.list())
        recent = PlumeSettings.shared.store.list(limit: 3)
    }

    func open(_ transcript: Transcript) {
        page = .history
        library.select(transcript)
    }

    /// Récupère un enregistrement annulé depuis l'historique, puis l'ouvre.
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
        panel.prompt = tr("Transcrire")
        panel.message = tr("Choisis un ou plusieurs fichiers audio à transcrire.")
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictation, meeting, imported
    /// Les enregistrements annulés encore récupérables : ouverts par leur propre bouton, pas
    /// par la barre de filtres.
    case cancelled

    /// Les onglets de la barre de filtres.
    static let tabs: [HistoryFilter] = [.all, .dictation, .meeting, .imported]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Tout")
        case .dictation: return tr("Dictées")
        case .meeting: return tr("Réunions")
        case .imported: return tr("Imports")
        case .cancelled: return tr("Annulés")
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
    /// Nombre de fichiers en cours de transcription.
    @Published var importing = 0
    /// Enregistrements annulés encore récupérables (filtre `.cancelled`).
    @Published var cancelled: [CancelledRecording] = []
    @Published var cancelledSelection: String?
    /// Enregistrement annulé en cours de récupération.
    @Published var restoring: String?
    /// Transcription dont la séparation des voix est en train d'être refaite.
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

    /// Supprime pour de bon un enregistrement annulé.
    func deleteCancelled(_ recording: CancelledRecording) {
        player.stop()
        PlumeSettings.shared.cancelled.delete(id: recording.id)
        cancelledSelection = nil
        reload()
    }

    /// Sections par jour d'enregistrement, comme l'historique.
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

    /// Donne (ou retire) un titre à une transcription.
    func retitle(_ transcript: Transcript, to title: String) {
        guard var updated = store.load(id: transcript.id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? nil : trimmed
        try? store.save(updated)
        reload()
    }

    /// Transcriptions dont on refait la transcription ou le résumé.
    @Published var working = Set<String>()

    /// Retranscrit l'audio conservé avec le modèle actuel (modèle changé, premier résultat raté).
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
                Log.write("nouvelle transcription impossible : \(error.localizedDescription)")
            }
            working.remove(transcript.id)
            reload()
        }
    }

    /// Résume avec l'IA locale (points clés, décisions, actions) et propose un titre.
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
                Log.write("résumé impossible : \(error.localizedDescription)")
            }
            working.remove(transcript.id)
            reload()
        }
    }

    /// Enregistre la transcription dans le format choisi, là où l'utilisateur le décide.
    func export(_ transcript: Transcript, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.fileName(for: transcript, format: format)
        panel.canCreateDirectories = true
        panel.prompt = tr("Exporter")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Exporter.render(transcript, as: format).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Réécoute l'audio conservé pour refaire la séparation des voix, éventuellement avec un
    /// nombre de personnes imposé.
    func reprocess(_ transcript: Transcript, speakers: Int?) {
        guard reprocessing == nil else { return }
        reprocessing = transcript.id
        player.stop()
        Task {
            do {
                _ = try await Pipeline.reprocess(transcript, speakerCount: speakers)
            } catch {
                Log.write("nouvelle séparation des voix impossible : \(error.localizedDescription)")
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

    /// Sections par jour, de la plus récente à la plus ancienne.
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
        if calendar.isDateInToday(day) { return tr("Aujourd'hui") }
        if calendar.isDateInYesterday(day) { return tr("Hier") }
        let text = dayFormatter.string(from: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Lecture de l'enregistrement d'origine d'une transcription (micro et son de l'ordinateur
/// joués ensemble pour une réunion).
@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published private(set) var loadedID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var players: [AVAudioPlayer] = []
    private var ticker: Timer?

    func isLoaded(_ id: String) -> Bool { loadedID == id }

    /// Ouvre l'audio d'une transcription. Appelé seulement quand on veut écouter : parcourir
    /// l'historique ne doit pas solliciter le système audio.
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
            // Fin de l'enregistrement.
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

    /// Langue de l'interface ; la fenêtre se redessine entièrement quand elle change.
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
    /// Heures pendant lesquelles un enregistrement annulé reste récupérable (0 : jamais gardé).
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
    /// Dossier du modèle personnalisé (chaîne vide : aucun).
    @Published var customModelPath: String
    /// Ce qui cloche avec le dossier de modèle choisi, le cas échéant.
    @Published var modelMessage: String?
    @Published var appearance: String { didSet { settings.appearance = appearance; onAppearanceChanged() } }
    /// Micro choisi : identifiant du périphérique, ou chaîne vide pour le micro intégré du Mac.
    @Published var microphoneUID: String { didSet { settings.microphoneUID = microphoneUID.isEmpty ? nil : microphoneUID } }
    @Published private(set) var microphones: [InputDevice] = AudioDevices.inputs()
    @Published var replacements: [Replacement] { didSet { ReplacementStore.save(replacements) } }
    @Published var rules: [AppRule] { didSet { AppRuleStore.save(rules); onRulesChanged() } }
    /// L'IA locale : disponible, ou pourquoi pas.
    @Published private(set) var ai = LocalAI.availability
    @Published var libraryPath: String
    @Published var launchAtLogin: Bool
    @Published var microphoneGranted = Permissions.microphoneGranted
    @Published var accessibilityGranted = Paster.isTrusted
    // Liens avec le terminal et les assistants.
    @Published private(set) var commandInstalled = Integrations.commandInstalled
    @Published private(set) var commandOnPath = true
    @Published private(set) var claudeCodeConnected = Integrations.claudeCodeConnected
    @Published private(set) var claudeDesktopConnected = Integrations.claudeDesktopConnected
    @Published private(set) var connectingClaudeCode = false
    /// Dernier incident d'une connexion, affiché sous la section.
    @Published var integrationMessage: String?

    init() {
        dictationShortcut = settings.dictationShortcut
        meetingShortcut = settings.meetingShortcut
        openShortcut = settings.openShortcut
        pasteLastShortcut = settings.pasteLastShortcut
        transformShortcut = settings.transformShortcut
        cancelShortcut = settings.cancelShortcut
        restoreShortcut = settings.restoreShortcut
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

    /// Ce que Plume garde d'une dictée : tout, le texte, ou rien.
    enum Retention: String, CaseIterable, Identifiable {
        case textAndAudio, textOnly, nothing

        var id: String { rawValue }

        var label: String {
            switch self {
            case .textAndAudio: return tr("Le texte et l'audio")
            case .textOnly: return tr("Le texte seulement")
            case .nothing: return tr("Rien")
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

    // MARK: Modèle

    /// Choisit le dossier d'un modèle au format Parakeet, et passe dessus s'il est complet.
    func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = tr("Utiliser ce modèle")
        panel.message = tr("Choisis le dossier qui contient Preprocessor, Encoder, Decoder, JointDecision (.mlmodelc) et parakeet_vocab.json.")
        if let current = settings.customModelURL { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let missing = SpeechEngine.missingCustomFiles(in: url)
        guard missing.isEmpty else {
            modelMessage = "Il manque \(missing.joined(separator: ", ")) dans ce dossier."
            return
        }
        modelMessage = nil
        settings.customModelURL = url
        customModelPath = url.path
        if model == .custom { onModelChanged() } else { model = .custom }
    }

    var permissionsMissing: Bool { !microphoneGranted || !accessibilityGranted }

    /// Relit la liste des micros branchés.
    func refreshMicrophones() {
        let devices = AudioDevices.inputs()
        if devices != microphones { microphones = devices }
    }

    /// Le micro choisi n'est pas branché en ce moment (écouteurs éteints, par exemple).
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
            Log.write("ouverture à la connexion impossible : \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Choisir")
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

    /// Choisit une app dans le Finder et lui crée une règle (une seule par app).
    func addRule() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("Ajouter")
        panel.message = tr("Choisis les applications qui ont leur propre réglage de dictée.")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !rules.contains(where: { $0.bundleID == id })
            else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            rules.append(AppRule(bundleID: id, name: name, style: Self.suggestedStyle(for: id)))
        }
    }

    /// La règle « toutes les autres applications », créée au besoin.
    func addDefaultRule() {
        guard !rules.contains(where: { $0.bundleID == "*" }) else { return }
        rules.append(AppRule(bundleID: "*", name: tr("Toutes les autres applications")))
    }

    /// Les messageries ont tout de suite le style « message ».
    static func suggestedStyle(for bundleID: String) -> DictationStyle {
        let messaging = ["slack", "messages", "whatsapp", "telegram", "discord", "ichat", "signal", "teams", "messenger"]
        return messaging.contains(where: { bundleID.lowercased().contains($0) }) ? .message : .standard
    }

    /// L'icône de l'app, si elle est installée.
    func icon(for rule: AppRule) -> NSImage? {
        guard rule.bundleID != "*", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Sauvegarde des réglages

    /// Écrit tous les réglages (raccourcis, options, vocabulaire, applications) dans un fichier,
    /// pour les retrouver sur un autre Mac.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tr("Réglages Plume.json")
        panel.prompt = tr("Enregistrer")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export(to: url)
            integrationMessage = nil
        } catch {
            integrationMessage = "Les réglages n'ont pas pu être enregistrés : \(error.localizedDescription)"
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = tr("Importer")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.import(from: url)
            reloadFromSettings()
            onShortcutsChanged()
            onRulesChanged()
        } catch {
            integrationMessage = "Ce fichier n'a pas pu être lu : \(error.localizedDescription)"
        }
    }

    /// Relit les réglages depuis le disque, après un import.
    private func reloadFromSettings() {
        dictationShortcut = settings.dictationShortcut
        meetingShortcut = settings.meetingShortcut
        openShortcut = settings.openShortcut
        pasteLastShortcut = settings.pasteLastShortcut
        transformShortcut = settings.transformShortcut
        cancelShortcut = settings.cancelShortcut
        restoreShortcut = settings.restoreShortcut
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

    // MARK: Terminal et assistants

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
            integrationMessage = "La commande n'a pas pu être installée : \(error.localizedDescription)"
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
            integrationMessage = tr("Claude Desktop verra Plume à son prochain lancement.")
        } catch {
            integrationMessage = tr("La configuration de Claude Desktop n'a pas pu être modifiée.")
        }
        refreshIntegrations()
    }
}
