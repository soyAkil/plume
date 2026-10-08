import AVFoundation
import AppKit
import PlumeKit

/// Conductor of a recording: capture, live transcription,
/// final processing, pasting and storing in the library.
@MainActor
final class SessionController: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// A video call app just opened the microphone: we offer to record the meeting.
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

    /// What we do with the dictation once transcribed.
    enum Intent: Equatable {
        /// Paste it where the cursor is.
        case dictation
        /// Paste nothing: the text waits in the library (`plume listen`, MCP tool).
        case capture
        /// It's an instruction: the local AI applies it to the selected text.
        case transform
    }

    static let levelCount = 30

    @Published private(set) var phase: Phase = .idle
    /// Last non-idle state: the pill keeps its content while it fades out.
    @Published private(set) var displayPhase: Phase = .idle
    @Published private(set) var mode: RecordingMode = .dictation
    @Published private(set) var intent: Intent = .dictation
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var paused = false
    /// An instruction is being dictated for a selected text (otherwise, to write from scratch).
    @Published private(set) var hasSelection = false
    /// The microphone has captured nothing for a while: microphone muted, wrong device?
    @Published private(set) var quietMic = false
    private var lastLoudAt = Date()
    /// Recent microphone levels (0…1), from oldest to newest.
    @Published private(set) var levels = [Float](repeating: 0, count: levelCount)
    /// True when the computer's sound carries speech (meeting).
    @Published private(set) var systemActive = false
    @Published private(set) var liveCommitted = ""
    @Published private(set) var liveVolatile = ""
    @Published private(set) var modelStatus: ModelStatus = .loading(nil)
    /// Last transcript produced, openable from the pill.
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
    /// Time spent paused since the start: it counts neither in the duration nor in the timer.
    private var pausedTotal: TimeInterval = 0
    private var frontApp: String?
    private var frontBundleID: String?
    /// Writing as the dictation goes: the live hypothesis is typed into the field as it
    /// comes; when it changes, what differs is erased and retyped.
    private var streaming = false
    /// What Plume has typed into the field so far.
    private var typed = ""
    /// What surrounds the cursor, read at the first word and kept for the whole dictation.
    private var streamContext: InsertionContext?
    private var streamPressReturn = false
    private var streamRule: AppRule?
    /// Text selected at the moment an instruction is dictated.
    private var selection = ""
    private var clock: Timer?
    private var liveTask: Task<Void, Never>?
    private var micLive: LiveTranscriber?
    private var systemLive: LiveTranscriber?
    private var hideTask: Task<Void, Never>?
    private var startedByCurrentPress = false
    private var unloadTask: Task<Void, Never>?
    /// Idle delay after which the models are released from memory.
    private static let idleUnloadDelay: TimeInterval =
        ProcessInfo.processInfo.environment["PLUME_IDLE_UNLOAD"].flatMap(TimeInterval.init) ?? 600
    /// Prevents automatic sleep while a meeting is being recorded.
    private var awake: NSObjectProtocol?
    private var systemActiveUntil = Date.distantPast
    /// The computer's sound was muted for the dictation: to be restored.
    private var mutedOutput = false

    private var askedForAccessibility = false
    /// Cancellation of a false trigger (⌃⇧ followed by a key): no sound.
    private var silentCancel = false
    /// Setting aside the last cancelled recording (audio, then text): a restore
    /// requested right away waits until it's done.
    private var keepingCancelled: Task<Void, Never>?
    /// Sessions being recorded or processed: recovery must not touch them.
    private var activeSessions = Set<String>()
    /// File imports in progress (drag and drop, menu).
    private var imports = 0
    private var importing: Bool { imports > 0 }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool {
        if case .processing = phase { return true }
        return phase == .recording
    }

    // MARK: - Model

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

    // MARK: - Shortcuts

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
                // The main shortcut always finishes the recording in progress.
                stop()
            } else {
                switchMode(to: requested)
            }
        case .idle, .done, .failed, .suggestion, .processing:
            // While the previous dictation is still being transcribed, another one can be started:
            // the first will finish pasting in the background.
            startedByCurrentPress = true
            start(requested, intent: action == .transform ? .transform : .dictation)
        }
    }

    /// Release: if the key was held, it was a "hold to talk".
    func handleRelease(_ action: HotkeyAction, held: TimeInterval) {
        defer { startedByCurrentPress = false }
        guard startedByCurrentPress, phase == .recording, mode == .dictation, held >= 0.7,
            action == .dictation || action == .transform
        else { return }
        stop()
    }

    /// The hold turned out to be another keyboard shortcut: discard the recording.
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

    // MARK: - Start

    func start(_ mode: RecordingMode, intent: Intent = .dictation) {
        guard phase != .recording else { return }
        switch TestHooks.fakeMic == nil ? AVCaptureDevice.authorizationStatus(for: .audio) : .authorized {
        case .notDetermined:
            let asked = Date()
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard granted else {
                        self?.finish(.failed(tr("Microphone not allowed")))
                        return
                    }
                    // Immediate answer: carry on. Otherwise the intent has passed, we don't
                    // start a recording behind the user's back.
                    if Date().timeIntervalSince(asked) < 20 {
                        self?.start(mode, intent: intent)
                    } else {
                        self?.finish(.done(tr("Microphone allowed")), hideAfter: 2)
                    }
                }
            }
            return
        case .denied, .restricted:
            finish(.failed(tr("Microphone not allowed")))
            Permissions.openSettings(.microphone)
            return
        default:
            break
        }

        hideTask?.cancel()
        // The model may have been unloaded during idle time: reload it right now,
        // while the user starts to speak.
        unloadTask?.cancel()
        let engine = self.engine
        let model = settings.model
        Task { try? await engine.prepare(model: model) }

        let now = Date()
        let store = settings.store
        let id = store.makeID(for: now)
        // Audio is written to disk as it goes: nothing is lost if the app stops.
        // A meeting in its final backup file, a dictation in a separate file.
        // Without history, a dictation leaves no trace, not even that one.
        let directory = mode == .meeting || settings.keepHistory ? try? store.ensureDirectory(forID: id) : nil

        let micRecorder = ChannelRecorder(channel: .mic, sessionStart: now)
        if let directory {
            let url = mode == .meeting
                ? directory.appendingPathComponent("\(id)_mic.wav")
                : (try? Recovery.dictationURL(id: id, store: store)) ?? directory.appendingPathComponent(id + Recovery.dictationSuffix)
            if let writer = try? WavWriter(url: url, recordsOffset: mode == .meeting) { micRecorder.attach(writer) }
        }
        micRecorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.pushLevel(level) }
        }
        let capture: AudioSource = TestHooks.fakeMic.map { FileCapture(url: $0) } ?? MicCapture()
        capture.onSamples = { micRecorder.append($0) }
        // Microphone lost along the way: finish cleanly with what was captured.
        (capture as? MicCapture)?.onFailure = { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        do {
            try capture.start()
        } catch {
            micRecorder.writer?.close()
            finish(.failed(tr("Microphone unavailable")))
            return
        }
        mic = capture
        micChannel = micRecorder
        if let microphone = capture as? MicCapture { Log.write("microphone: “\(microphone.deviceName)”") }

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
            // The selection is read right away, while the original app is still in front.
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
            // After the start sound, so that it can be heard.
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
                // Fifteen seconds without any sound: we flag it rather than let
                // people think everything is being recorded.
                let quiet = self.elapsed > 15 && Date().timeIntervalSince(self.lastLoudAt) > 15
                if quiet != self.quietMic { self.quietMic = quiet }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        startLive()
    }

    private func pushLevel(_ rms: Float) {
        // Logarithmic scale: -55 dB → 0, -12 dB → 1.
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (db + 55) / 43))
        levels.removeFirst()
        levels.append(normalized)
        if normalized > 0.12 { lastLoudAt = Date() }
    }

    /// Captures the computer's sound on a second channel (meeting mode).
    private func startSystemCapture(id: String, directory: URL?, sessionStart: Date) {
        guard settings.systemAudioInMeeting, system == nil else { return }
        let recorder = ChannelRecorder(channel: .system, sessionStart: sessionStart)
        if let directory,
            let writer = try? WavWriter(url: directory.appendingPathComponent("\(id)_sys.wav"), recordsOffset: true)
        {
            recorder.attach(writer)
        }
        recorder.onLevel = { [weak self] level in
            guard level > 0.006 else { return }
            DispatchQueue.main.async { self?.systemActiveUntil = Date().addingTimeInterval(0.6) }
        }
        let tap: AudioSource = TestHooks.fakeSystem.map { FileCapture(url: $0) } ?? SystemAudioCapture()
        tap.onSamples = { recorder.append($0) }
        // If the capture fails or isn't allowed, the channel stays empty and the meeting
        // continues with the microphone alone.
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
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Recording a meeting")
        } else if !on, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
    }

    /// Mutes (or restores) the computer's sound for the length of a dictation.
    private func muteOutput(_ on: Bool) {
        if on, !mutedOutput, SystemVolume.mute(true) {
            mutedOutput = true
        } else if !on, mutedOutput {
            SystemVolume.mute(false)
            mutedOutput = false
        }
    }

    /// Switches from dictation to meeting (or the reverse) without interrupting the recording.
    func switchMode(to newMode: RecordingMode) {
        guard phase == .recording, newMode != mode, newMode != .imported,
            let micChannel, let sessionID, let startedAt
        else { return }
        if newMode == .meeting {
            // The backup file changes name: it is now a meeting's,
            // start included.
            let directory = try? settings.store.ensureDirectory(forID: sessionID)
            if let old = micChannel.writer?.url, Recovery.isDictationBackup(old.lastPathComponent) {
                micChannel.writer?.close()
                try? FileManager.default.removeItem(at: old)
            }
            if let directory,
                let writer = try? WavWriter(
                    url: directory.appendingPathComponent("\(sessionID)_mic.wav"), recordsOffset: true)
            {
                micChannel.attach(writer)
            }
            startSystemCapture(id: sessionID, directory: directory, sessionStart: startedAt)
            keepAwake(true)
            muteOutput(false)
            intent = .dictation
            // A meeting is pasted nowhere: what was typed stays, the stream stops there.
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
        TestHooks.log("mode: \(newMode)")
        onModeChanged?(newMode)
    }

    // MARK: - Pause

    /// Suspends the capture: the microphone closes (the orange indicator goes off), the timer
    /// stops. On resume, the missing silence is filled in to keep the timestamps.
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
        TestHooks.log(paused ? "pause" : "resume")
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
                // Re-read on every pass: the system channel can appear along the way.
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
        TestHooks.log("live: …\(state.committed.suffix(40)) ▸ \(state.volatile)")
        liveCommitted = state.committed
        // The model always closes the window with a period: we don't show it while it's still moving.
        var volatile = state.volatile
        while let last = volatile.last, ".…".contains(last) { volatile.removeLast() }
        liveVolatile = volatile
        if streaming { stream(state, final: false) }
    }

    /// Brings the field up to what the live transcription hears: the validated text, plus the current
    /// window without its last word (the least certain). The whole is formatted as an entire
    /// dictation would be, then only the difference with what is already typed is erased and retyped.
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
        TestHooks.log("stream: -\(erase) +“\(add)”")
        if !TestHooks.noPaste {
            Paster.erase(erase)
            Paster.type(add)
        }
        typed = target
        return true
    }

    // MARK: - Stop

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
        // A false trigger or a press of under a second has nothing to keep.
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

    /// Files a cancelled recording among the recoverable ones. The backup files stay
    /// in place until it is written: if the app stops in the meantime, nothing is lost.
    private func keepCancelled(_ recording: CancelledRecording, mic: ChannelRecorder, system: ChannelRecorder?) {
        let settings = self.settings
        let engine = self.engine
        let previous = keepingCancelled
        keepingCancelled = Task { [weak self] in
            await previous?.value
            let store = settings.cancelled
            // An hour of meeting weighs a few hundred MB: copied and encoded off the main thread.
            let (kept, samples) = await Task.detached(priority: .utility) { () -> (Bool, [Float]) in
                let samples = mic.buffer.all()
                let systemAudio = system.map { (samples: $0.buffer.all(), offset: $0.offset) }
                return ((try? store.keep(recording, mic: samples, system: systemAudio)) != nil, samples)
            }.value
            guard let self else { return }
            if kept { self.removeTemporaryAudio(mic, system) }
            self.activeSessions.remove(recording.id)
            guard kept else {
                Log.write("cancel: audio not kept (\(recording.id))")
                return
            }
            Log.write("cancel: recording set aside (\(recording.id))")
            // A dictation is transcribed right away: you see what it contained, and
            // restoring it is instant. A meeting waits until you ask for it.
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

    /// Discards cancelled recordings older than the chosen delay.
    func purgeCancelled() {
        let hours = settings.cancelledRetentionHours
        let store = settings.cancelled
        let cutoff = hours > 0 ? Date().addingTimeInterval(-Double(hours) * 3600) : .distantFuture
        Task.detached(priority: .utility) {
            let count = store.purge(cancelledBefore: cutoff)
            if count > 0 { Log.write("cancelled: \(count) expired recording(s) deleted") }
        }
    }

    /// Restores a cancelled recording (the last one, by default): transcribed if it isn't
    /// already, stored in history, and for a dictation pasted where the cursor is.
    /// - Parameters:
    ///   - paste: false from the Plume window, where the text is only copied.
    ///   - completion: the transcript obtained, or `nil` on failure.
    func restoreCancelled(id: String? = nil, paste: Bool = true, completion: ((Transcript?) -> Void)? = nil) {
        guard phase != .recording else { return }
        hideTask?.cancel()
        setPhase(.processing(tr("Restoring")))
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
                finish(.failed(tr("Nothing to restore")), hideAfter: 1.8)
                completion?(nil)
                return
            }
            // The mode serves the notch ("Open" button of a meeting); a dictation started
            // in the meantime keeps its own.
            if phase != .recording { mode = recording.mode }
            // Without history, a restored dictation is returned without being stored.
            let save = recording.mode != .dictation || settings.keepHistory
            do {
                let transcript = try await store.restore(recording, save: save, settings: settings, engine: engine)
                Log.write("cancel: recording restored (\(transcript.id))")
                lastTranscript = transcript
                onLibraryChanged?()
                completion?(transcript)
                if transcript.mode == .meeting {
                    Sounds.play(.ready)
                    finish(.done(tr("Meeting restored")), hideAfter: 6)
                } else if paste, settings.pasteAfterDictation, !TestHooks.noPaste,
                    Paster.paste(transcript.text, restoreClipboard: settings.restoreClipboard)
                {
                    finish(.done(tr("Restored")), hideAfter: 1.5)
                } else {
                    if !TestHooks.noPaste { Paster.copy(transcript.text) }
                    finish(.done(tr("Restored · ⌘V to paste")), hideAfter: 2.5)
                }
            } catch CancelledStore.Failure.nothingHeard {
                finish(.failed(tr("Nothing heard")), hideAfter: 1.8)
                completion?(nil)
            } catch {
                Log.write("restore failed (\(recording.id)): \(error.localizedDescription)")
                finish(.failed(tr("Couldn't restore")), hideAfter: 3)
                completion?(nil)
            }
        }
    }

    func stop() {
        guard phase == .recording, let micChannel, let sessionID, let startedAt else { return }
        // Speaking time: the clock stops during pauses.
        let end = paused ? (pausedAt ?? Date()) : Date()
        let duration = end.timeIntervalSince(startedAt) - pausedTotal
        // Accidental press: nothing to transcribe.
        guard duration >= 0.4 else {
            teardownCapture()
            removeTemporaryAudio(self.micChannel, systemChannel)
            activeSessions.remove(sessionID)
            self.micChannel = nil
            systemChannel = nil
            setPhase(.idle)
            return
        }
        setPhase(.processing(tr("Transcript")))
        let mode = self.mode
        let intent = self.intent
        let systemChannel = self.systemChannel
        let app = frontApp
        let bundleID = frontBundleID
        let stoppedAt = Date()
        // The live transcription survives the teardown: it still has the end of the dictation to write.
        let live = streaming ? micLive : nil
        // Properties are released right away: a new dictation can start while
        // this one is being transcribed. The capture, though, stays open a short moment: the
        // last syllable is often still on its way when the shortcut is released.
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

    /// App closing in the middle of a recording: the backup audio files stay in
    /// place and will be transcribed at the next launch.
    func shutdown() {
        guard phase == .recording else { return }
        teardownCapture()
    }

    /// Finishes recordings left without a transcript (hard stop, model unavailable).
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
                        Log.write("recording resumed: \(transcript.id)")
                        lastTranscript = transcript
                        onLibraryChanged?()
                    }
                } catch {
                    Log.write("resume failed (\(item.id)): \(error.localizedDescription)")
                }
            }
        }
    }

    /// AI clean-up applies according to the app's rule, otherwise the general setting.
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
                // Written as the dictation goes: the end is typed right away, then the history
                // receives the full version, transcribed again in one go.
                let last = await live.finish()
                stream(last, final: true)
                if !TestHooks.noPaste, !typed.isEmpty, streamPressReturn || rule?.pressReturn == true { Paster.pressReturn() }
                finish(.done(typed.isEmpty ? tr("Nothing heard") : tr("Written")), hideAfter: 1.0)
            }
            let options = DictationOptions(
                settings: settings, style: intent == .dictation ? rule?.style ?? .standard : .standard)
            let result = try await Pipeline.dictation(samples: samples, engine: engine, options: options)
            guard !result.text.isEmpty else {
                if let safety { try? FileManager.default.removeItem(at: safety) }
                if live == nil { finish(.failed(tr("Nothing heard")), hideAfter: 1.5) }
                return
            }
            TestHooks.log("dictation: \(result.text)")
            var text = result.text
            var raw = result.raw

            if intent == .transform {
                // The dictation was an instruction: the local AI applies it to the selection.
                guard LocalAI.availability.isAvailable else {
                    finish(.failed(LocalAI.availability.reason ?? tr("Local AI unavailable")), hideAfter: 4)
                    if let safety { try? FileManager.default.removeItem(at: safety) }
                    return
                }
                report(.processing(selection.isEmpty ? tr("Writing") : tr("Rewriting")))
                raw = selection.isEmpty ? "Consigne : \(text)" : "Consigne : \(text)\n\nTexte d'origine :\n\(selection)"
                text = try await LocalAI.transform(selection, instruction: text)
                TestHooks.log("transform: \(text)")
            } else if live == nil, intent == .dictation, rule?.polish ?? settings.polish, LocalAI.availability.isAvailable {
                report(.processing(tr("Cleaning up")))
                let instructions = (rule?.instructions).flatMap { $0.isEmpty ? nil : $0 } ?? settings.polishInstructions
                if let polished = try? await LocalAI.polish(text, instructions: instructions) {
                    text = TextStyle.apply(options.style, to: TextCleanup.capitalizeFirst(polished))
                    TestHooks.log("polish: \(text)")
                }
            }

            let pressReturn = intent == .dictation && (result.pressReturn || rule?.pressReturn == true)
            if live != nil {
                // Already written as it went: nothing to paste.
            } else if intent == .capture {
                finish(.done(tr("Transcribed")), hideAfter: 1.0)
            } else if TestHooks.noPaste {
                finish(.done(tr("Pasted")), hideAfter: 1.0)
            } else if Date().timeIntervalSince(stoppedAt) > 8 {
                // After a long wait (model being downloaded), the cursor is probably
                // no longer in the same place: copy without pasting.
                Paster.copy(text)
                finish(.done(tr("Copied · ⌘V to paste")), hideAfter: 3)
            } else if settings.pasteAfterDictation {
                var toPaste = text
                if settings.smartInsert, intent == .dictation, let context = Paster.insertionContext() {
                    toPaste = SmartInsert.adapt(text, context: context)
                }
                let pasted = Paster.paste(toPaste, restoreClipboard: settings.restoreClipboard, typing: rule?.typeText == true)
                if pasted, pressReturn { Paster.pressReturn() }
                finish(.done(pasted ? tr("Pasted") : tr("Copied · ⌘V to paste")), hideAfter: pasted ? 1.0 : 2.5)
                if !pasted, !askedForAccessibility {
                    // Without the Accessibility permission, pasting is impossible: ask for it once.
                    askedForAccessibility = true
                    Paster.requestTrust()
                }
            } else {
                Paster.copy(text)
                finish(.done(tr("Copied")), hideAfter: 1.0)
            }

            let draft = Transcript(
                id: id, createdAt: date, mode: .dictation, duration: duration, engine: await engine.modelName,
                text: text, rawText: raw, app: app)
            // The text awaited by `plume listen` or the MCP tool goes out right away.
            if intent == .capture { Remote.deliver(draft) }
            let settings = self.settings
            let engine = self.engine
            if !settings.keepHistory {
                // Nothing is stored: the text lives long enough to be pasted (and pasted again if needed).
                lastTranscript = draft
                if let safety { try? FileManager.default.removeItem(at: safety) }
                if TestHooks.fakeMic == nil {
                    Task.detached(priority: .utility) { await VoiceprintStore.learn(from: samples, engine: engine) }
                }
                return
            }
            // Storing must not delay the paste.
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
                // The transcript is written: the backup file no longer has a reason to exist.
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
            // The audio stays aside in its backup file: it will be transcribed as soon as the
            // model is available.
            if safety == nil {
                let store = settings.store
                await Task.detached {
                    if let url = try? Recovery.dictationURL(id: id, store: store) { Recovery.stash(samples, at: url) }
                }.value
            }
            let reason = (error as? LocalAI.Failure)?.errorDescription
            finish(.failed(reason ?? tr("Transcription failed · audio kept")), hideAfter: 3.5)
            Log.write("error: \(error.localizedDescription)")
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
                    case .cleaningEcho: label = tr("Removing echo")
                    case .transcribing: label = tr("Transcript")
                    case .separatingSpeakers: label = tr("Separating speakers")
                    }
                    self.setPhase(.processing(label))
                }
            }
            guard !result.segments.isEmpty else {
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                finish(.failed(tr("Nothing heard")), hideAfter: 1.5)
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
                    for (label, audio) in ChannelAudio.tracksToKeep(recorded) {
                        let name = "\(id)_\(label).m4a"
                        if (try? AudioIO.writeM4A(audio.paddedSamples, to: directory.appendingPathComponent(name))) != nil {
                            transcript.audioFiles.append(name)
                        }
                    }
                }
                // The WAVs were only a safety net during the recording.
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                return (try? store.save(transcript)) != nil ? transcript : nil
            }.value
            guard let saved else {
                finish(.failed(tr("Could not save")))
                return
            }
            lastTranscript = saved
            onLibraryChanged?()
            Sounds.play(.ready)
            finish(.done(tr("Meeting saved")), hideAfter: 6)
            if settings.autoSummary, LocalAI.availability.isAvailable {
                summarize(saved)
            }
        } catch {
            // The meeting's audio files stay in place for a later recovery.
            finish(.failed(tr("Transcription failed · audio kept")), hideAfter: 3.5)
            Log.write("error: \(error.localizedDescription)")
        }
    }

    // MARK: - Local AI

    /// Transcriptions whose summary is being written.
    @Published private(set) var summarizing = Set<String>()

    /// Summarizes a meeting with the local AI, then stores the summary and title in the library.
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
                Log.write("summary failed (\(transcript.id)): \(error.localizedDescription)")
            }
            summarizing.remove(transcript.id)
        }
    }

    // MARK: - Paste again

    /// Pastes the last dictation again where the cursor is: useful when the paste failed or
    /// the field changed in the meantime.
    func pasteLast() {
        guard phase != .recording else { return }
        let last = lastTranscript?.mode == .dictation ? lastTranscript : settings.store.latest(mode: .dictation)
        guard let last, !last.text.isEmpty else {
            finish(.failed(tr("No dictation")), hideAfter: 1.5)
            return
        }
        let pasted = TestHooks.noPaste || Paster.paste(last.text, restoreClipboard: settings.restoreClipboard)
        finish(.done(pasted ? tr("Pasted again") : tr("Copied · ⌘V to paste")), hideAfter: pasted ? 1.2 : 2.5)
    }

    // MARK: - Meeting detected

    /// A video call app just opened the microphone: the island offers to record.
    func suggestMeeting(app: String) {
        guard phase == .idle, settings.meetingDetection else { return }
        TestHooks.log("call detected: \(app)")
        finish(.suggestion(app), hideAfter: 20)
    }

    func acceptSuggestion() {
        guard case .suggestion = phase else { return }
        hideTask?.cancel()
        setPhase(.idle)
        start(.meeting)
    }

    // MARK: - States

    private func setPhase(_ phase: Phase) {
        TestHooks.log("state: \(phase)")
        self.phase = phase
        if phase != .idle { displayPhase = phase }
        if phase == .idle { scheduleUnload() } else { unloadTask?.cancel() }
        onPhaseChanged?(phase)
    }

    /// After ten minutes without a recording, the models' memory is released.
    func scheduleUnload() {
        unloadTask?.cancel()
        let engine = self.engine
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleUnloadDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .idle, !self.importing else { return }
            await engine.unload()
            TestHooks.log("models unloaded")
        }
    }

    /// An intermediate state ("Cleaning up"…), unless a new dictation has already started.
    private func report(_ phase: Phase) {
        guard self.phase != .recording else { return }
        setPhase(phase)
    }

    /// Shows a final state then returns to rest. A dictation already restarted keeps the screen.
    private func finish(_ phase: Phase, hideAfter delay: TimeInterval = 2.2) {
        guard self.phase != .recording else {
            TestHooks.log("state (background): \(phase)")
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

    /// Fake states for off-screen rendering of the interface mockups.
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

    /// Transcribes an audio file chosen by the user or dropped into the iCloud folder.
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
