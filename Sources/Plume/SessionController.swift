import AVFoundation
import AppKit
import PlumeKit

/// Chef d'orchestre d'un enregistrement : capture, transcription en direct,
/// traitement final, collage et rangement dans la bibliothèque.
@MainActor
final class SessionController: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Une app de visio vient d'ouvrir le micro : on propose d'enregistrer la réunion.
        case suggestion(String)
        case recording
        case processing(String)
        case done(String)
        case failed(String)
    }

    enum ModelStatus: Equatable {
        case loading(Double?)
        case ready
        case failed(String)
    }

    /// Ce qu'on fait de la dictée une fois transcrite.
    enum Intent: Equatable {
        /// La coller là où est le curseur.
        case dictation
        /// Ne rien coller : le texte attend dans la bibliothèque (`plume listen`, outil MCP).
        case capture
        /// C'est une consigne : l'IA locale l'applique au texte sélectionné.
        case transform
    }

    static let levelCount = 30

    @Published private(set) var phase: Phase = .idle
    /// Dernier état non inactif : la pastille garde son contenu pendant qu'elle disparaît.
    @Published private(set) var displayPhase: Phase = .idle
    @Published private(set) var mode: RecordingMode = .dictation
    @Published private(set) var intent: Intent = .dictation
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var paused = false
    /// Une consigne est dictée pour un texte sélectionné (sinon, pour rédiger à partir de rien).
    @Published private(set) var hasSelection = false
    /// Le micro ne capte rien depuis un moment : micro coupé, mauvais périphérique ?
    @Published private(set) var quietMic = false
    private var lastLoudAt = Date()
    /// Niveaux sonores récents du micro (0…1), du plus ancien au plus récent.
    @Published private(set) var levels = [Float](repeating: 0, count: levelCount)
    /// Vrai quand le son de l'ordinateur porte de la parole (réunion).
    @Published private(set) var systemActive = false
    @Published private(set) var liveCommitted = ""
    @Published private(set) var liveVolatile = ""
    @Published private(set) var modelStatus: ModelStatus = .loading(nil)
    /// Dernier transcript produit, ouvrable depuis la pastille.
    @Published private(set) var lastTranscript: Transcript?

    var onLibraryChanged: (() -> Void)?
    var onPhaseChanged: ((Phase) -> Void)?
    var onModeChanged: ((RecordingMode) -> Void)?

    private let settings = PlumeSettings.shared
    private let engine = SpeechEngine.shared
    private var mic: AudioSource?
    private var system: AudioSource?
    private var micChannel: ChannelRecorder?
    private var systemChannel: ChannelRecorder?
    private var sessionID: String?
    private var startedAt: Date?
    private var pausedAt: Date?
    /// Temps passé en pause depuis le début : il ne compte ni dans la durée ni dans le chronomètre.
    private var pausedTotal: TimeInterval = 0
    private var frontApp: String?
    private var frontBundleID: String?
    /// Écriture au fil de la dictée : l'hypothèse du direct est tapée dans le champ au fur et
    /// à mesure ; quand elle change, on efface ce qui diffère et on retape.
    private var streaming = false
    /// Ce que Plume a tapé dans le champ jusqu'ici.
    private var typed = ""
    /// Ce qui entoure le curseur, lu au premier mot et gardé pour toute la dictée.
    private var streamContext: InsertionContext?
    private var streamPressReturn = false
    private var streamRule: AppRule?
    /// Texte sélectionné au moment où une consigne est dictée.
    private var selection = ""
    private var clock: Timer?
    private var liveTask: Task<Void, Never>?
    private var micLive: LiveTranscriber?
    private var systemLive: LiveTranscriber?
    private var hideTask: Task<Void, Never>?
    private var startedByCurrentPress = false
    private var unloadTask: Task<Void, Never>?
    /// Délai d'inactivité après lequel les modèles sont retirés de la mémoire.
    private static let idleUnloadDelay: TimeInterval =
        ProcessInfo.processInfo.environment["PLUME_IDLE_UNLOAD"].flatMap(TimeInterval.init) ?? 600
    /// Empêche la mise en veille automatique pendant qu'une réunion s'enregistre.
    private var awake: NSObjectProtocol?
    private var systemActiveUntil = Date.distantPast
    /// Le son de l'ordinateur a été coupé pour la dictée : à rétablir.
    private var mutedOutput = false

    private var askedForAccessibility = false
    /// Annulation d'un faux déclenchement (⌃⇧ suivi d'une touche) : pas de son.
    private var silentCancel = false
    /// Mise de côté du dernier enregistrement annulé (audio, puis texte) : une récupération
    /// demandée tout de suite attend qu'elle soit finie.
    private var keepingCancelled: Task<Void, Never>?
    /// Sessions en cours d'enregistrement ou de traitement : la reprise ne doit pas y toucher.
    private var activeSessions = Set<String>()
    /// Imports de fichiers en cours (glisser-déposer, menu).
    private var imports = 0
    private var importing: Bool { imports > 0 }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool {
        if case .processing = phase { return true }
        return phase == .recording
    }

    // MARK: - Modèle

    func loadModel() {
        modelStatus = .loading(nil)
        let model = settings.model
        Task {
            do {
                try await engine.prepare(model: model) { [weak self] phase in
                    Task { @MainActor in
                        guard let self, self.modelStatus != .ready else { return }
                        switch phase {
                        case .downloading(let fraction): self.modelStatus = .loading(fraction)
                        case .compiling: self.modelStatus = .loading(nil)
                        case .ready: self.modelStatus = .ready
                        }
                    }
                }
                modelStatus = .ready
                if phase == .idle { scheduleUnload() }
                recoverInterruptedSessions()
            } catch {
                modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Raccourcis

    func handlePress(_ action: HotkeyAction) {
        if action == .pasteLast {
            pasteLast()
            return
        }
        guard let requested = action.mode else { return }
        switch phase {
        case .recording:
            startedByCurrentPress = false
            if action == .dictation || action == .transform || mode == requested {
                // Le raccourci principal termine toujours l'enregistrement en cours.
                stop()
            } else {
                switchMode(to: requested)
            }
        case .idle, .done, .failed, .suggestion, .processing:
            // Pendant que la dictée précédente se transcrit encore, on peut en lancer une autre :
            // la première finira de se coller en arrière-plan.
            startedByCurrentPress = true
            start(requested, intent: action == .transform ? .transform : .dictation)
        }
    }

    /// Relâchement : si la touche a été tenue, c'était un « parler en maintenant ».
    func handleRelease(_ action: HotkeyAction, held: TimeInterval) {
        defer { startedByCurrentPress = false }
        guard startedByCurrentPress, phase == .recording, mode == .dictation, held >= 0.7,
            action == .dictation || action == .transform
        else { return }
        stop()
    }

    /// Le maintien s'est révélé être un autre raccourci clavier : on jette l'enregistrement.
    func handleCancel(_ action: HotkeyAction) {
        guard startedByCurrentPress, phase == .recording, mode == action.mode else { return }
        silentCancel = true
        startedByCurrentPress = false
        cancel()
    }

    func toggle(_ mode: RecordingMode, intent: Intent = .dictation) {
        if phase == .recording {
            if self.mode == mode { stop() } else { switchMode(to: mode) }
        } else {
            start(mode, intent: intent)
        }
    }

    // MARK: - Démarrage

    func start(_ mode: RecordingMode, intent: Intent = .dictation) {
        guard phase != .recording else { return }
        switch TestHooks.fakeMic == nil ? AVCaptureDevice.authorizationStatus(for: .audio) : .authorized {
        case .notDetermined:
            let asked = Date()
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard granted else {
                        self?.finish(.failed(tr("Micro non autorisé")))
                        return
                    }
                    // Réponse immédiate : on enchaîne. Sinon l'intention est passée, on ne
                    // démarre pas un enregistrement dans le dos de l'utilisateur.
                    if Date().timeIntervalSince(asked) < 20 {
                        self?.start(mode, intent: intent)
                    } else {
                        self?.finish(.done(tr("Micro autorisé")), hideAfter: 2)
                    }
                }
            }
            return
        case .denied, .restricted:
            finish(.failed(tr("Micro non autorisé")))
            Permissions.openSettings(.microphone)
            return
        default:
            break
        }

        hideTask?.cancel()
        // Le modèle a pu être déchargé pendant l'inactivité : on le recharge dès maintenant,
        // pendant que l'utilisateur commence à parler.
        unloadTask?.cancel()
        let engine = self.engine
        let model = settings.model
        Task { try? await engine.prepare(model: model) }

        let now = Date()
        let store = settings.store
        let id = store.makeID(for: now)
        // L'audio est écrit sur disque au fil de l'eau : rien n'est perdu si l'app s'arrête.
        // Une réunion dans son fichier définitif de secours, une dictée dans un fichier à part.
        // Sans historique, une dictée ne laisse aucune trace, pas même celle-là.
        let directory = mode == .meeting || settings.keepHistory ? try? store.ensureDirectory(forID: id) : nil

        let micRecorder = ChannelRecorder(channel: .mic, sessionStart: now)
        if let directory {
            let url = mode == .meeting
                ? directory.appendingPathComponent("\(id)_mic.wav")
                : (try? Recovery.dictationURL(id: id, store: store)) ?? directory.appendingPathComponent("\(id)_dictee.wav")
            if let writer = try? WavWriter(url: url) { micRecorder.attach(writer) }
        }
        micRecorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.pushLevel(level) }
        }
        let capture: AudioSource = TestHooks.fakeMic.map { FileCapture(url: $0) } ?? MicCapture()
        capture.onSamples = { micRecorder.append($0) }
        // Micro perdu en route : on termine proprement avec ce qui a été capté.
        (capture as? MicCapture)?.onFailure = { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        do {
            try capture.start()
        } catch {
            micRecorder.writer?.close()
            finish(.failed(tr("Micro indisponible")))
            return
        }
        mic = capture
        micChannel = micRecorder
        if let microphone = capture as? MicCapture { Log.write("micro : « \(microphone.deviceName) »") }

        self.mode = mode
        self.intent = intent
        startedAt = now
        pausedAt = nil
        pausedTotal = 0
        paused = false
        if mode == .meeting { startSystemCapture(id: id, directory: directory, sessionStart: now) }

        sessionID = id
        activeSessions.insert(id)
        let front = NSWorkspace.shared.frontmostApplication
        frontApp = front?.localizedName == "loginwindow" ? nil : front?.localizedName
        frontBundleID = front?.bundleIdentifier
        selection = ""
        hasSelection = false
        streaming = intent == .dictation && mode == .dictation && settings.streamingPaste && settings.pasteAfterDictation
        typed = ""
        streamContext = nil
        streamPressReturn = false
        streamRule = streaming ? AppRuleStore.rule(for: frontBundleID, in: AppRuleStore.load()) : nil
        if intent == .transform {
            // La sélection est lue tout de suite, pendant que l'app d'origine est encore devant.
            Task { [weak self] in
                let text = await Paster.selectedText()
                await MainActor.run {
                    self?.selection = text
                    self?.hasSelection = !text.isEmpty
                }
            }
        }
        elapsed = 0
        quietMic = false
        lastLoudAt = now
        levels = [Float](repeating: 0, count: Self.levelCount)
        liveCommitted = ""
        liveVolatile = ""
        systemActive = false
        setPhase(.recording)
        Sounds.play(.start)
        if mode == .meeting {
            keepAwake(true)
        } else if settings.muteWhileDictating, intent != .capture {
            // Après le son de départ, pour qu'on l'entende.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.phase == .recording, self.mode == .dictation else { return }
                self.muteOutput(true)
            }
        }
        if polishWanted(for: frontBundleID) || intent == .transform { LocalAI.prewarm() }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt, !self.paused else { return }
                self.elapsed = Date().timeIntervalSince(startedAt) - self.pausedTotal
                self.systemActive = Date() < self.systemActiveUntil
                // Quinze secondes sans le moindre son : on le signale plutôt que de laisser
                // croire que tout s'enregistre.
                let quiet = self.elapsed > 15 && Date().timeIntervalSince(self.lastLoudAt) > 15
                if quiet != self.quietMic { self.quietMic = quiet }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        startLive()
    }

    private func pushLevel(_ rms: Float) {
        // Échelle logarithmique : -55 dB → 0, -12 dB → 1.
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (db + 55) / 43))
        levels.removeFirst()
        levels.append(normalized)
        if normalized > 0.12 { lastLoudAt = Date() }
    }

    /// Capte le son de l'ordinateur sur un second canal (mode réunion).
    private func startSystemCapture(id: String, directory: URL?, sessionStart: Date) {
        guard settings.systemAudioInMeeting, system == nil else { return }
        let recorder = ChannelRecorder(channel: .system, sessionStart: sessionStart)
        if let directory, let writer = try? WavWriter(url: directory.appendingPathComponent("\(id)_sys.wav")) {
            recorder.attach(writer)
        }
        recorder.onLevel = { [weak self] level in
            guard level > 0.006 else { return }
            DispatchQueue.main.async { self?.systemActiveUntil = Date().addingTimeInterval(0.6) }
        }
        let tap: AudioSource = TestHooks.fakeSystem.map { FileCapture(url: $0) } ?? SystemAudioCapture()
        tap.onSamples = { recorder.append($0) }
        // Si la capture échoue ou n'est pas autorisée, le canal reste vide et la réunion
        // continue avec le micro seul.
        try? tap.start()
        system = tap
        systemChannel = recorder
        if settings.liveTranscript {
            systemLive = LiveTranscriber(engine: engine, buffer: recorder.buffer)
        }
    }

    private func keepAwake(_ on: Bool) {
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Enregistrement d'une réunion")
        } else if !on, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
    }

    /// Coupe (ou rétablit) le son de l'ordinateur le temps d'une dictée.
    private func muteOutput(_ on: Bool) {
        if on, !mutedOutput, SystemVolume.mute(true) {
            mutedOutput = true
        } else if !on, mutedOutput {
            SystemVolume.mute(false)
            mutedOutput = false
        }
    }

    /// Passe de la dictée à la réunion (ou l'inverse) sans interrompre l'enregistrement.
    func switchMode(to newMode: RecordingMode) {
        guard phase == .recording, newMode != mode, newMode != .imported,
            let micChannel, let sessionID, let startedAt
        else { return }
        if newMode == .meeting {
            // Le fichier de secours change de nom : c'est désormais celui d'une réunion,
            // début compris.
            let directory = try? settings.store.ensureDirectory(forID: sessionID)
            if let old = micChannel.writer?.url, old.lastPathComponent.hasSuffix("_dictee.wav") {
                micChannel.writer?.close()
                try? FileManager.default.removeItem(at: old)
            }
            if let directory, let writer = try? WavWriter(url: directory.appendingPathComponent("\(sessionID)_mic.wav")) {
                micChannel.attach(writer)
            }
            startSystemCapture(id: sessionID, directory: directory, sessionStart: startedAt)
            keepAwake(true)
            muteOutput(false)
            intent = .dictation
            // Une réunion ne se colle nulle part : ce qui a été tapé reste, le flux s'arrête là.
            streaming = false
        } else {
            system?.stop()
            system = nil
            systemLive = nil
            systemChannel?.writer?.close()
            if let url = systemChannel?.writer?.url { try? FileManager.default.removeItem(at: url) }
            systemChannel = nil
            systemActive = false
            keepAwake(false)
        }
        mode = newMode
        Sounds.play(newMode == .meeting ? .meetingOn : .meetingOff)
        TestHooks.log("mode : \(newMode)")
        onModeChanged?(newMode)
    }

    // MARK: - Pause

    /// Suspend la capture : le micro se ferme (le voyant orange s'éteint), le chronomètre
    /// s'arrête. À la reprise, le silence manquant est comblé pour garder les horodatages.
    func togglePause() {
        guard phase == .recording else { return }
        if paused {
            try? mic?.start()
            if let system { try? system.start() }
            if let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
            pausedAt = nil
            paused = false
            lastLoudAt = Date()
            Sounds.play(.meetingOn)
        } else {
            mic?.stop()
            system?.stop()
            pausedAt = Date()
            paused = true
            levels = [Float](repeating: 0, count: Self.levelCount)
            Sounds.play(.meetingOff)
        }
        TestHooks.log(paused ? "pause" : "reprise")
    }

    private func startLive() {
        guard settings.liveTranscript || streaming, let micChannel else { return }
        let engine = self.engine
        let model = settings.model
        micLive = LiveTranscriber(engine: engine, buffer: micChannel.buffer, eager: streaming)
        let interval: UInt64 = streaming ? 200_000_000 : 400_000_000
        liveTask = Task { [weak self] in
            try? await engine.prepare(model: model)
            while !Task.isCancelled {
                // Relus à chaque passe : le canal système peut apparaître en cours de route.
                guard let self, let micLive = self.micLive else { return }
                let systemLive = self.systemLive
                if let state = await micLive.tick(), !Task.isCancelled {
                    self.showLive(state)
                }
                if let systemLive, let state = await systemLive.tick(), !Task.isCancelled,
                    !state.volatile.isEmpty
                {
                    self.showLive(state)
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func showLive(_ state: LiveTranscriber.State) {
        guard phase == .recording else { return }
        TestHooks.log("direct : …\(state.committed.suffix(40)) ▸ \(state.volatile)")
        liveCommitted = state.committed
        // Le modèle clôt toujours la fenêtre par un point : on ne l'affiche pas tant que ça bouge.
        var volatile = state.volatile
        while let last = volatile.last, ".…".contains(last) { volatile.removeLast() }
        liveVolatile = volatile
        if streaming { stream(state, final: false) }
    }

    /// Met le champ au niveau de ce que le direct entend : le texte validé, plus la fenêtre en
    /// cours sans son dernier mot (le moins sûr). Le tout est mis en forme comme le serait une
    /// dictée entière, puis seule la différence avec ce qui est déjà tapé est effacée et retapée.
    @discardableResult
    private func stream(_ state: LiveTranscriber.State, final: Bool) -> Bool {
        guard streaming else { return false }
        var volatile = state.volatile
        if !final {
            var words = volatile.split(separator: " ")
            if !words.isEmpty { words.removeLast() }
            volatile = words.joined(separator: " ")
        }
        let hypothesis = [state.committed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
        let options = DictationOptions(settings: settings, style: streamRule?.style ?? .standard)
        let result = Pipeline.format(hypothesis, options: options, final: final)
        streamPressReturn = result.pressReturn
        var target = result.text
        if !target.isEmpty, settings.smartInsert {
            if streamContext == nil { streamContext = TestHooks.noPaste ? .empty : (Paster.insertionContext() ?? .empty) }
            if let context = streamContext { target = SmartInsert.adapt(target, context: context) }
        }
        guard target != typed else { return true }
        let common = typed.commonPrefix(with: target).count
        let erase = typed.count - common
        let add = String(target.dropFirst(common))
        TestHooks.log("flux : -\(erase) +« \(add) »")
        if !TestHooks.noPaste {
            Paster.erase(erase)
            Paster.type(add)
        }
        typed = target
        return true
    }

    // MARK: - Arrêt

    private func teardownCapture() {
        mic?.stop()
        system?.stop()
        mic = nil
        system = nil
        clock?.invalidate()
        clock = nil
        liveTask?.cancel()
        liveTask = nil
        micLive = nil
        systemLive = nil
        micChannel?.writer?.close()
        systemChannel?.writer?.close()
        keepAwake(false)
        muteOutput(false)
        paused = false
    }

    private func removeTemporaryAudio(_ recorders: ChannelRecorder?...) {
        for recorder in recorders {
            if let url = recorder?.writer?.url { try? FileManager.default.removeItem(at: url) }
        }
    }

    func cancel() {
        guard phase == .recording else { return }
        let end = paused ? (pausedAt ?? Date()) : Date()
        let duration = startedAt.map { end.timeIntervalSince($0) - pausedTotal } ?? 0
        // Un faux déclenchement ou un appui de moins d'une seconde n'a rien à garder.
        let keep = !silentCancel && settings.cancelledRetentionHours > 0 && duration >= 1
        let recording = sessionID.map {
            CancelledRecording(
                id: $0, createdAt: startedAt ?? Date(), mode: mode, duration: duration, app: frontApp)
        }
        let channels = (mic: micChannel, system: systemChannel)
        teardownCapture()
        micChannel = nil
        systemChannel = nil
        if !silentCancel { Sounds.play(.cancel) }
        silentCancel = false
        guard keep, let recording, let micRecorder = channels.mic else {
            removeTemporaryAudio(channels.mic, channels.system)
            if let sessionID { activeSessions.remove(sessionID) }
            setPhase(.idle)
            return
        }
        keepCancelled(recording, mic: micRecorder, system: channels.system)
        setPhase(.idle)
    }

    /// Range un enregistrement annulé parmi les récupérables. Les fichiers de secours restent
    /// en place tant qu'il n'est pas écrit : si l'app s'arrête entre-temps, rien n'est perdu.
    private func keepCancelled(_ recording: CancelledRecording, mic: ChannelRecorder, system: ChannelRecorder?) {
        let settings = self.settings
        let engine = self.engine
        let previous = keepingCancelled
        keepingCancelled = Task { [weak self] in
            await previous?.value
            let store = settings.cancelled
            // Une heure de réunion pèse quelques centaines de Mo : copiée et encodée hors du fil principal.
            let (kept, samples) = await Task.detached(priority: .utility) { () -> (Bool, [Float]) in
                let samples = mic.buffer.all()
                let systemAudio = system.map { (samples: $0.buffer.all(), offset: $0.offset) }
                return ((try? store.keep(recording, mic: samples, system: systemAudio)) != nil, samples)
            }.value
            guard let self else { return }
            if kept { self.removeTemporaryAudio(mic, system) }
            self.activeSessions.remove(recording.id)
            guard kept else {
                Log.write("annulation : audio non conservé (\(recording.id))")
                return
            }
            Log.write("annulation : enregistrement gardé de côté (\(recording.id))")
            // Une dictée est transcrite tout de suite : on voit ce qu'elle contenait, et la
            // récupérer est instantané. Une réunion attend qu'on la demande.
            if recording.mode == .dictation {
                try? await engine.prepare(model: settings.model)
                if let result = try? await Pipeline.dictation(
                    samples: samples, engine: engine, options: DictationOptions(settings: settings))
                {
                    var updated = recording
                    updated.audioFiles = store.load(id: recording.id)?.audioFiles ?? []
                    updated.text = result.text
                    updated.rawText = result.raw
                    store.update(updated)
                }
            }
            self.purgeCancelled()
            self.onLibraryChanged?()
        }
    }

    /// Jette les enregistrements annulés plus vieux que le délai choisi.
    func purgeCancelled() {
        let hours = settings.cancelledRetentionHours
        let store = settings.cancelled
        let cutoff = hours > 0 ? Date().addingTimeInterval(-Double(hours) * 3600) : .distantFuture
        Task.detached(priority: .utility) {
            let count = store.purge(cancelledBefore: cutoff)
            if count > 0 { Log.write("annulés : \(count) enregistrement(s) expiré(s) supprimé(s)") }
        }
    }

    /// Récupère un enregistrement annulé (le dernier, par défaut) : transcrit s'il ne l'est pas
    /// déjà, rangé dans l'historique, et pour une dictée collée là où est le curseur.
    /// - Parameters:
    ///   - paste: faux depuis la fenêtre de Plume, où le texte est seulement copié.
    ///   - completion: la transcription obtenue, ou `nil` en cas d'échec.
    func restoreCancelled(id: String? = nil, paste: Bool = true, completion: ((Transcript?) -> Void)? = nil) {
        guard phase != .recording else { return }
        hideTask?.cancel()
        setPhase(.processing(tr("Récupération")))
        imports += 1
        unloadTask?.cancel()
        let settings = self.settings
        let engine = self.engine
        Task {
            defer {
                imports -= 1
                if phase == .idle { scheduleUnload() }
            }
            await keepingCancelled?.value
            let store = settings.cancelled
            guard let recording = id.flatMap(store.load) ?? store.list().first else {
                finish(.failed(tr("Rien à récupérer")), hideAfter: 1.8)
                completion?(nil)
                return
            }
            // Le mode sert à l'encoche (bouton « Ouvrir » d'une réunion) ; une dictée lancée
            // entre-temps garde le sien.
            if phase != .recording { mode = recording.mode }
            // Sans historique, une dictée récupérée est rendue sans être rangée.
            let save = recording.mode != .dictation || settings.keepHistory
            do {
                let transcript = try await store.restore(recording, save: save, settings: settings, engine: engine)
                Log.write("annulation : enregistrement récupéré (\(transcript.id))")
                lastTranscript = transcript
                onLibraryChanged?()
                completion?(transcript)
                if transcript.mode == .meeting {
                    Sounds.play(.ready)
                    finish(.done(tr("Réunion récupérée")), hideAfter: 6)
                } else if paste, settings.pasteAfterDictation, !TestHooks.noPaste,
                    Paster.paste(transcript.text, restoreClipboard: settings.restoreClipboard)
                {
                    finish(.done(tr("Récupéré")), hideAfter: 1.5)
                } else {
                    if !TestHooks.noPaste { Paster.copy(transcript.text) }
                    finish(.done(tr("Récupéré · ⌘V pour coller")), hideAfter: 2.5)
                }
            } catch CancelledStore.Failure.nothingHeard {
                finish(.failed(tr("Rien entendu")), hideAfter: 1.8)
                completion?(nil)
            } catch {
                Log.write("récupération impossible (\(recording.id)) : \(error.localizedDescription)")
                finish(.failed(tr("Récupération impossible")), hideAfter: 3)
                completion?(nil)
            }
        }
    }

    func stop() {
        guard phase == .recording, let micChannel, let sessionID, let startedAt else { return }
        // Le temps de parole : l'horloge s'arrête pendant les pauses.
        let end = paused ? (pausedAt ?? Date()) : Date()
        let duration = end.timeIntervalSince(startedAt) - pausedTotal
        // Appui accidentel : rien à transcrire.
        guard duration >= 0.4 else {
            teardownCapture()
            removeTemporaryAudio(self.micChannel, systemChannel)
            activeSessions.remove(sessionID)
            self.micChannel = nil
            systemChannel = nil
            setPhase(.idle)
            return
        }
        setPhase(.processing(tr("Transcription")))
        let mode = self.mode
        let intent = self.intent
        let systemChannel = self.systemChannel
        let app = frontApp
        let bundleID = frontBundleID
        let stoppedAt = Date()
        // Le direct survit au démontage : il lui reste la fin de la dictée à écrire.
        let live = streaming ? micLive : nil
        // Les propriétés sont libérées tout de suite : une nouvelle dictée peut démarrer pendant
        // que celle-ci se transcrit. La capture, elle, reste ouverte un court instant : la
        // dernière syllabe est souvent encore en route quand on relâche le raccourci.
        let captures: (mic: AudioSource?, system: AudioSource?, clock: Timer?, live: Task<Void, Never>?) = (mic, system, clock, liveTask)
        mic = nil
        system = nil
        clock = nil
        liveTask = nil
        micLive = nil
        systemLive = nil
        self.micChannel = nil
        self.systemChannel = nil
        keepAwake(false)
        muteOutput(false)
        paused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            captures.mic?.stop()
            captures.system?.stop()
            captures.clock?.invalidate()
            captures.live?.cancel()
            micChannel.writer?.close()
            systemChannel?.writer?.close()
            Sounds.play(.stop)
            Task {
                if mode == .dictation {
                    await finishDictation(
                        id: sessionID, date: startedAt, duration: duration, samples: micChannel.buffer.all(),
                        app: app, bundleID: bundleID, intent: intent, stoppedAt: stoppedAt,
                        safety: micChannel.writer?.url, live: live)
                } else {
                    await finishMeeting(
                        id: sessionID, date: startedAt, duration: duration, mic: micChannel, system: systemChannel)
                }
            }
        }
    }

    /// Fermeture de l'app en plein enregistrement : les fichiers audio de secours restent en
    /// place et seront transcrits au prochain lancement.
    func shutdown() {
        guard phase == .recording else { return }
        teardownCapture()
    }

    /// Termine les enregistrements restés sans transcript (arrêt brutal, modèle indisponible).
    func recoverInterruptedSessions() {
        let settings = self.settings
        let active = activeSessions
        Task {
            let pending = await Task.detached { Recovery.pending(in: settings.store, excluding: active) }.value
            guard !pending.isEmpty else { return }
            imports += 1
            unloadTask?.cancel()
            defer {
                imports -= 1
                if phase == .idle { scheduleUnload() }
            }
            for item in pending {
                do {
                    if let transcript = try await Recovery.recover(item) {
                        Log.write("enregistrement repris : \(transcript.id)")
                        lastTranscript = transcript
                        onLibraryChanged?()
                    }
                } catch {
                    Log.write("reprise impossible (\(item.id)) : \(error.localizedDescription)")
                }
            }
        }
    }

    /// La mise au propre par l'IA s'applique selon la règle de l'app, sinon le réglage général.
    private func polishWanted(for bundleID: String?) -> Bool {
        let rule = AppRuleStore.rule(for: bundleID, in: AppRuleStore.load())
        return rule?.polish ?? settings.polish
    }

    private func finishDictation(
        id: String, date: Date, duration: Double, samples: [Float], app: String?, bundleID: String?,
        intent: Intent, stoppedAt: Date, safety: URL?, live: LiveTranscriber? = nil
    ) async {
        defer { activeSessions.remove(id) }
        let rule = AppRuleStore.rule(for: bundleID, in: AppRuleStore.load())
        do {
            try await engine.prepare(model: settings.model)
            modelStatus = .ready
            if let live {
                // Écrit au fil de la dictée : la fin est tapée tout de suite, puis l'historique
                // reçoit la version complète, retranscrite d'un bloc.
                let last = await live.finish()
                stream(last, final: true)
                if !TestHooks.noPaste, !typed.isEmpty, streamPressReturn || rule?.pressReturn == true { Paster.pressReturn() }
                finish(.done(typed.isEmpty ? tr("Rien entendu") : tr("Écrit")), hideAfter: 1.0)
            }
            let options = DictationOptions(
                settings: settings, style: intent == .dictation ? rule?.style ?? .standard : .standard)
            let result = try await Pipeline.dictation(samples: samples, engine: engine, options: options)
            guard !result.text.isEmpty else {
                if let safety { try? FileManager.default.removeItem(at: safety) }
                if live == nil { finish(.failed(tr("Rien entendu")), hideAfter: 1.5) }
                return
            }
            TestHooks.log("dictée : \(result.text)")
            var text = result.text
            var raw = result.raw

            if intent == .transform {
                // La dictée était une consigne : l'IA locale l'applique à la sélection.
                guard LocalAI.availability.isAvailable else {
                    finish(.failed(LocalAI.availability.reason ?? tr("IA locale indisponible")), hideAfter: 4)
                    if let safety { try? FileManager.default.removeItem(at: safety) }
                    return
                }
                report(.processing(selection.isEmpty ? tr("Rédaction") : tr("Réécriture")))
                raw = selection.isEmpty ? "Consigne : \(text)" : "Consigne : \(text)\n\nTexte d'origine :\n\(selection)"
                text = try await LocalAI.transform(selection, instruction: text)
                TestHooks.log("transformation : \(text)")
            } else if live == nil, intent == .dictation, rule?.polish ?? settings.polish, LocalAI.availability.isAvailable {
                report(.processing(tr("Mise au propre")))
                let instructions = (rule?.instructions).flatMap { $0.isEmpty ? nil : $0 } ?? settings.polishInstructions
                if let polished = try? await LocalAI.polish(text, instructions: instructions) {
                    text = TextStyle.apply(options.style, to: TextCleanup.capitalizeFirst(polished))
                    TestHooks.log("mise au propre : \(text)")
                }
            }

            let pressReturn = intent == .dictation && (result.pressReturn || rule?.pressReturn == true)
            if live != nil {
                // Déjà écrit au fil de l'eau : rien à coller.
            } else if intent == .capture {
                finish(.done(tr("Transcrit")), hideAfter: 1.0)
            } else if TestHooks.noPaste {
                finish(.done(tr("Collé")), hideAfter: 1.0)
            } else if Date().timeIntervalSince(stoppedAt) > 8 {
                // Après une longue attente (modèle en cours de téléchargement), le curseur n'est
                // sans doute plus au même endroit : on copie sans coller.
                Paster.copy(text)
                finish(.done(tr("Copié · ⌘V pour coller")), hideAfter: 3)
            } else if settings.pasteAfterDictation {
                var toPaste = text
                if settings.smartInsert, intent == .dictation, let context = Paster.insertionContext() {
                    toPaste = SmartInsert.adapt(text, context: context)
                }
                let pasted = Paster.paste(toPaste, restoreClipboard: settings.restoreClipboard, typing: rule?.typeText == true)
                if pasted, pressReturn { Paster.pressReturn() }
                finish(.done(pasted ? tr("Collé") : tr("Copié · ⌘V pour coller")), hideAfter: pasted ? 1.0 : 2.5)
                if !pasted, !askedForAccessibility {
                    // Sans l'autorisation Accessibilité, impossible de coller : on la demande une fois.
                    askedForAccessibility = true
                    Paster.requestTrust()
                }
            } else {
                Paster.copy(text)
                finish(.done(tr("Copié")), hideAfter: 1.0)
            }

            let draft = Transcript(
                id: id, createdAt: date, mode: .dictation, duration: duration, engine: await engine.modelName,
                text: text, rawText: raw, app: app)
            // Le texte attendu par `plume listen` ou l'outil MCP part tout de suite.
            if intent == .capture { Remote.deliver(draft) }
            let settings = self.settings
            let engine = self.engine
            if !settings.keepHistory {
                // Rien n'est rangé : le texte vit le temps d'être collé (et recollé au besoin).
                lastTranscript = draft
                if let safety { try? FileManager.default.removeItem(at: safety) }
                if TestHooks.fakeMic == nil {
                    Task.detached(priority: .utility) { await VoiceprintStore.learn(from: samples, engine: engine) }
                }
                return
            }
            // Le rangement ne doit pas retarder le collage.
            let saved: Transcript? = await Task.detached(priority: .utility) {
                var transcript = draft
                let store = settings.store
                if settings.keepAudio, let directory = try? store.ensureDirectory(forID: id) {
                    let name = "\(id)_mic.m4a"
                    if (try? AudioIO.writeM4A(samples, to: directory.appendingPathComponent(name))) != nil {
                        transcript.audioFiles = [name]
                    }
                }
                guard (try? store.save(transcript)) != nil else { return nil }
                // Le transcript est écrit : le fichier de secours n'a plus de raison d'être.
                if let safety { try? FileManager.default.removeItem(at: safety) }
                if TestHooks.fakeMic == nil {
                    await VoiceprintStore.learn(from: samples, engine: engine)
                }
                return transcript
            }.value
            if let saved {
                lastTranscript = saved
                onLibraryChanged?()
            }
        } catch {
            // L'audio reste de côté dans son fichier de secours : il sera transcrit dès que le
            // modèle sera disponible.
            if safety == nil {
                let store = settings.store
                await Task.detached {
                    if let url = try? Recovery.dictationURL(id: id, store: store) { Recovery.stash(samples, at: url) }
                }.value
            }
            let reason = (error as? LocalAI.Failure)?.errorDescription
            finish(.failed(reason ?? tr("Transcription impossible · audio conservé")), hideAfter: 3.5)
            Log.write("erreur : \(error.localizedDescription)")
        }
    }

    private func finishMeeting(
        id: String, date: Date, duration: Double, mic: ChannelRecorder, system: ChannelRecorder?
    ) async {
        let temporary = [mic.writer?.url, system?.writer?.url].compactMap { $0 }
        defer { activeSessions.remove(id) }
        do {
            try await engine.prepare(model: settings.model)
            modelStatus = .ready
            var channels = [ChannelAudio(channel: .mic, samples: mic.buffer.all(), offset: mic.offset)]
            if let system {
                channels.append(ChannelAudio(channel: .system, samples: system.buffer.all(), offset: system.offset))
            }
            let result = try await Pipeline.conversation(
                channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true
            ) { [weak self] stage in
                Task { @MainActor in
                    guard let self, case .processing = self.phase else { return }
                    let label: String
                    switch stage {
                    case .cleaningEcho: label = tr("Nettoyage de l'écho")
                    case .transcribing: label = tr("Transcription")
                    case .separatingSpeakers: label = tr("Séparation des voix")
                    }
                    self.setPhase(.processing(label))
                }
            }
            guard !result.segments.isEmpty else {
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                finish(.failed(tr("Rien entendu")), hideAfter: 1.5)
                return
            }

            let draft = Transcript(
                id: id, createdAt: date, mode: .meeting, duration: duration, engine: await engine.modelName,
                text: result.text, rawText: result.rawText, segments: result.segments, speakers: result.speakers)
            let settings = self.settings
            let recorded = channels
            let saved: Transcript? = await Task.detached(priority: .utility) {
                var transcript = draft
                let store = settings.store
                if settings.keepAudio, let directory = try? store.ensureDirectory(forID: id) {
                    for audio in recorded where !AudioLevel.isSilent(audio.samples) {
                        let name = "\(id)_\(audio.channel == .mic ? "mic" : "sys").m4a"
                        // Silence initial égal au décalage du canal : l'audio reste calé sur les horodatages.
                        let lead = [Float](repeating: 0, count: Int(audio.offset * Double(SpeechEngine.sampleRate)))
                        if (try? AudioIO.writeM4A(lead + audio.samples, to: directory.appendingPathComponent(name))) != nil {
                            transcript.audioFiles.append(name)
                        }
                    }
                }
                // Les WAV n'étaient qu'un filet de sécurité pendant l'enregistrement.
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                return (try? store.save(transcript)) != nil ? transcript : nil
            }.value
            guard let saved else {
                finish(.failed(tr("Enregistrement impossible")))
                return
            }
            lastTranscript = saved
            onLibraryChanged?()
            Sounds.play(.ready)
            finish(.done(tr("Réunion enregistrée")), hideAfter: 6)
            if settings.autoSummary, LocalAI.availability.isAvailable {
                summarize(saved)
            }
        } catch {
            // Les fichiers audio de la réunion restent en place pour une reprise ultérieure.
            finish(.failed(tr("Transcription impossible · audio conservé")), hideAfter: 3.5)
            Log.write("erreur : \(error.localizedDescription)")
        }
    }

    // MARK: - IA locale

    /// Transcriptions dont le résumé est en cours d'écriture.
    @Published private(set) var summarizing = Set<String>()

    /// Résume une réunion avec l'IA locale, puis range le résumé et le titre dans la bibliothèque.
    func summarize(_ transcript: Transcript) {
        guard !summarizing.contains(transcript.id) else { return }
        summarizing.insert(transcript.id)
        let store = settings.store
        Task {
            do {
                let summary = try await LocalAI.summarize(transcript)
                if var updated = store.load(id: transcript.id) {
                    updated.summary = summary.markdown
                    if updated.title == nil { updated.title = summary.title }
                    try store.save(updated)
                    if lastTranscript?.id == updated.id { lastTranscript = updated }
                }
                onLibraryChanged?()
            } catch {
                Log.write("résumé impossible (\(transcript.id)) : \(error.localizedDescription)")
            }
            summarizing.remove(transcript.id)
        }
    }

    // MARK: - Recoller

    /// Recolle la dernière dictée là où est le curseur : utile quand le collage a raté ou que
    /// le champ a changé entre-temps.
    func pasteLast() {
        guard phase != .recording else { return }
        let last = lastTranscript?.mode == .dictation ? lastTranscript : settings.store.latest(mode: .dictation)
        guard let last, !last.text.isEmpty else {
            finish(.failed(tr("Aucune dictée")), hideAfter: 1.5)
            return
        }
        let pasted = TestHooks.noPaste || Paster.paste(last.text, restoreClipboard: settings.restoreClipboard)
        finish(.done(pasted ? tr("Recollé") : tr("Copié · ⌘V pour coller")), hideAfter: pasted ? 1.2 : 2.5)
    }

    // MARK: - Réunion détectée

    /// Une app de visio vient d'ouvrir le micro : l'île propose d'enregistrer.
    func suggestMeeting(app: String) {
        guard phase == .idle, settings.meetingDetection else { return }
        TestHooks.log("appel détecté : \(app)")
        finish(.suggestion(app), hideAfter: 20)
    }

    func acceptSuggestion() {
        guard case .suggestion = phase else { return }
        hideTask?.cancel()
        setPhase(.idle)
        start(.meeting)
    }

    // MARK: - États

    private func setPhase(_ phase: Phase) {
        TestHooks.log("état : \(phase)")
        self.phase = phase
        if phase != .idle { displayPhase = phase }
        if phase == .idle { scheduleUnload() } else { unloadTask?.cancel() }
        onPhaseChanged?(phase)
    }

    /// Après dix minutes sans enregistrement, on rend la mémoire des modèles.
    func scheduleUnload() {
        unloadTask?.cancel()
        let engine = self.engine
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleUnloadDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .idle, !self.importing else { return }
            await engine.unload()
            TestHooks.log("modèles déchargés")
        }
    }

    /// Un état intermédiaire (« Mise au propre »…), sauf si une nouvelle dictée a déjà commencé.
    private func report(_ phase: Phase) {
        guard self.phase != .recording else { return }
        setPhase(phase)
    }

    /// Affiche un état final puis revient au repos. Une dictée déjà recommencée garde l'écran.
    private func finish(_ phase: Phase, hideAfter delay: TimeInterval = 2.2) {
        guard self.phase != .recording else {
            TestHooks.log("état (en arrière-plan) : \(phase)")
            return
        }
        setPhase(phase)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == phase else { return }
            self.setPhase(.idle)
        }
    }

    func dismiss() {
        switch phase {
        case .done, .failed, .suggestion:
            hideTask?.cancel()
            setPhase(.idle)
        default:
            break
        }
    }

    /// États factices pour le rendu hors écran des maquettes de l'interface.
    func debugSet(
        phase: Phase, mode: RecordingMode = .dictation, intent: Intent = .dictation, elapsed: TimeInterval = 0,
        paused: Bool = false, quietMic: Bool = false, levels: [Float]? = nil, committed: String = "", volatile: String = "",
        systemActive: Bool = false, transcript: Transcript? = nil
    ) {
        self.phase = phase
        displayPhase = phase
        self.mode = mode
        self.intent = intent
        self.elapsed = elapsed
        self.paused = paused
        self.quietMic = quietMic
        hasSelection = intent == .transform
        if let levels { self.levels = levels }
        liveCommitted = committed
        liveVolatile = volatile
        self.systemActive = systemActive
        lastTranscript = transcript
        modelStatus = .ready
    }

    /// Transcrit un fichier audio choisi par l'utilisateur ou déposé dans le dossier iCloud.
    func importFile(
        _ url: URL, mode: RecordingMode = .imported, device: String = "mac", date: Date = Date()
    ) async -> Transcript? {
        imports += 1
        unloadTask?.cancel()
        defer {
            imports -= 1
            if phase == .idle { scheduleUnload() }
        }
        guard let transcript = try? await Importer.importAudio(at: url, mode: mode, device: device, date: date)
        else { return nil }
        lastTranscript = transcript
        onLibraryChanged?()
        return transcript
    }
}
