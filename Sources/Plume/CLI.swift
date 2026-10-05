import AppKit
import Foundation
import PlumeKit

/// Ligne de commande : le même binaire que l'app, lancé avec des arguments.
enum CLI {
    static let commands: Set<String> = [
        "transcribe", "last", "list", "show", "search", "path", "mcp", "live", "render", "toggle", "stop", "cancel",
        "diarize", "doctor", "selftest", "simulate-chord", "open", "sounds", "aec", "words", "reprocess", "mictest",
        "snapshot", "tiroir-ouvert", "tiroir-ferme", "cancelled", "restore",
        "format", "export", "summarize", "polish", "transform", "listen", "pause", "paste", "settings", "calls",
        "help", "--help", "-h",
    ]

    /// Descripteur de la vraie sortie standard, après redirection des traces vers stderr.
    nonisolated(unsafe) private static var out = FileHandle.standardOutput

    static func isolateStandardOutput() {
        let saved = dup(STDOUT_FILENO)
        guard saved >= 0 else { return }
        fflush(stdout)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        out = FileHandle(fileDescriptor: saved, closeOnDealloc: false)
    }

    /// Écrit une ligne sur la vraie sortie standard.
    static func emit(_ text: String) {
        out.write((text + "\n").data(using: .utf8)!)
    }

    static func handles(_ args: [String]) -> Bool {
        guard args.count >= 2 else { return false }
        return commands.contains(args[1])
    }

    static let usage = """
        Plume — dictée et transcription locales

          plume last [--mode dictee|reunion|import] [--json]   dernière transcription
          plume list [-n 20] [--mode …] [--json]               transcriptions récentes
          plume show <id> [--json]                             une transcription
          plume search <mots…> [--json]                        recherche plein texte
          plume transcribe <fichier> [--mode …] [--save]       transcrire un fichier audio
          plume export <id> --format md|txt|srt|vtt|json [-o f]  exporter une transcription
          plume summarize <id>                                 résumer une réunion avec l'IA locale
          plume reprocess <id> [--speakers N]                  refaire la séparation des voix
          plume toggle dictee|reunion                          démarrer / arrêter dans l'app ouverte
          plume stop | plume cancel | plume pause              terminer / annuler / mettre en pause
          plume listen [--timeout 180]                         dicter dans l'app, et recevoir le texte ici
          plume paste                                          recoller la dernière dictée
          plume cancelled                                      enregistrements annulés encore récupérables
          plume restore                                        récupérer le dernier enregistrement annulé
          plume open                                           ouvrir la fenêtre de Plume
          plume path                                           dossier de la bibliothèque
          plume settings export|import <fichier.json>          sauvegarder / restaurer tous les réglages
          plume format "texte brut" [--style message]          voir la mise en forme d'une dictée
          plume polish "texte" | plume transform "consigne"    essayer l'IA locale (texte sur l'entrée standard)
          plume doctor                                         état des autorisations et du modèle
          plume mcp                                            serveur MCP (stdio) pour les IA

        Sans argument, lance l'application dans la barre de menus.
        """

    static func run(_ args: [String]) async -> Int32 {
        let command = args[1]
        var rest = Array(args.dropFirst(2))
        let json = take(flag: "--json", from: &rest)
        let mode = take(option: "--mode", from: &rest).flatMap(RecordingMode.init(slug:))
        let settings = PlumeSettings.shared
        let store = settings.store

        switch command {
        case "help", "--help", "-h":
            emit(usage)
            return 0

        case "path":
            emit(settings.libraryURL.path)
            return 0

        case "cancelled":
            let recordings = settings.cancelled.list()
            if recordings.isEmpty { printError("Aucun enregistrement annulé.") }
            for recording in recordings {
                emit("\(recording.id)  \(recording.mode.slug)  \(Format.clock(recording.duration))  \(recording.preview ?? "")")
            }
            return 0

        case "restore":
            Remote.send("restore")
            return 0

        case "last":
            guard let t = store.latest(mode: mode) else {
                printError("Aucune transcription.")
                return 1
            }
            output(t, json: json)
            return 0

        case "list":
            let limit = take(option: "-n", from: &rest).flatMap(Int.init) ?? 20
            let items = store.list(limit: limit, mode: mode)
            if json {
                printJSON(items.map(Summary.init))
            } else {
                for t in items {
                    emit("\(t.id)  \(pad(t.mode.label, 8)) \(pad(Format.duration(t.duration), 12)) \(t.preview)")
                }
            }
            return 0

        case "show":
            guard let id = rest.first, let t = store.load(id: id) else {
                printError("Transcription introuvable.")
                return 1
            }
            output(t, json: json)
            return 0

        case "search":
            let items = store.search(rest.joined(separator: " "))
            if json {
                printJSON(items.map(Summary.init))
            } else {
                for t in items {
                    emit("\(t.id)  \(pad(t.mode.label, 8)) \(t.preview)")
                }
            }
            return 0

        case "transcribe":
            let save = take(flag: "--save", from: &rest)
            if let systemPath = take(option: "--system", from: &rest), let micPath = rest.first {
                // Réunion à deux canaux à partir de deux fichiers : le micro, et le son de l'ordinateur.
                let keepEcho = take(flag: "--no-echo-cancel", from: &rest)
                do {
                    let engine = SpeechEngine.shared
                    try await engine.prepare(model: settings.model)
                    let channels = [
                        ChannelAudio(channel: .mic, samples: try AudioIO.loadSamples(URL(fileURLWithPath: micPath))),
                        ChannelAudio(channel: .system, samples: try AudioIO.loadSamples(URL(fileURLWithPath: systemPath))),
                    ]
                    let result = try await Pipeline.conversation(
                        channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true,
                        cancelEcho: !keepEcho)
                    emit(TranscriptStore.dialogue(result.segments))
                    return 0
                } catch {
                    printError("Échec : \(error.localizedDescription)")
                    return 1
                }
            }
            guard let path = rest.first else {
                printError("Usage : plume transcribe <fichier> [--mode dictee|reunion|import] [--save]")
                return 2
            }
            do {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let t = try await Importer.importAudio(
                    at: url, mode: mode ?? .imported, device: "mac", save: save)
                output(t, json: json)
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "live":
            guard let path = rest.first else { return 2 }
            return await simulateLive(path: path)

        case "toggle":
            let target = rest.first.flatMap(RecordingMode.init(slug:)) ?? .dictation
            Remote.send(target == .meeting ? "toggle-reunion" : "toggle-dictee")
            return 0

        case "stop", "cancel", "open", "pause", "snapshot", "tiroir-ouvert", "tiroir-ferme":
            Remote.send(command)
            return 0

        case "paste":
            Remote.send("paste-last")
            return 0


        case "listen":
            // Dictée sans collage : l'app enregistre, le texte revient ici. Pour un script ou
            // un agent qui veut « entendre » l'utilisateur.
            let timeout = take(option: "--timeout", from: &rest).flatMap(Double.init) ?? 180
            guard let text = await Listener.listen(store: store, timeout: timeout) else {
                printError("Aucune dictée reçue (l'app est-elle lancée ?).")
                return 1
            }
            emit(text)
            return 0

        case "format":
            // Diagnostic : la mise en forme d'un texte brut (nettoyage, commandes vocales, vocabulaire, style).
            let style = take(option: "--style", from: &rest).flatMap(DictationStyle.init(rawValue:)) ?? .standard
            let text = rest.isEmpty ? readStandardInput() : rest.joined(separator: " ")
            let result = Pipeline.format(text, options: DictationOptions(settings: settings, style: style))
            emit(result.text + (result.pressReturn ? "\n⏎" : ""))
            return 0

        case "export":
            let name = take(option: "--format", from: &rest) ?? "md"
            let output = take(option: "-o", from: &rest)
            guard let format = ExportFormat(rawValue: name) else {
                printError("Formats : md, txt, srt, vtt, json.")
                return 2
            }
            guard let id = rest.first, let t = store.load(id: id) else {
                printError("Transcription introuvable.")
                return 1
            }
            let rendered = Exporter.render(t, as: format)
            if let output {
                do {
                    try rendered.write(toFile: (output as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
                } catch {
                    printError("Échec : \(error.localizedDescription)")
                    return 1
                }
            } else {
                emit(rendered)
            }
            return 0

        case "summarize":
            guard let id = rest.first, let t = store.load(id: id) else {
                printError("Transcription introuvable.")
                return 1
            }
            do {
                let summary = try await LocalAI.summarize(t)
                var updated = t
                updated.summary = summary.markdown
                if updated.title == nil { updated.title = summary.title }
                if !take(flag: "--no-save", from: &rest) { try store.save(updated) }
                emit("# \(summary.title)\n\n\(summary.markdown)")
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "polish":
            let instructions = take(option: "--instructions", from: &rest) ?? settings.polishInstructions
            let text = rest.isEmpty ? readStandardInput() : rest.joined(separator: " ")
            do {
                emit(try await LocalAI.polish(text, instructions: instructions))
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "transform":
            // plume transform "traduis en anglais" < texte.txt
            guard let instruction = rest.first else {
                printError("Usage : plume transform \"consigne\" < texte")
                return 2
            }
            let selection = isatty(STDIN_FILENO) == 0 ? readStandardInput() : ""
            do {
                emit(try await LocalAI.transform(selection, instruction: instruction))
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "settings":
            guard rest.count >= 2 else {
                printError("Usage : plume settings export|import <fichier.json>")
                return 2
            }
            let url = URL(fileURLWithPath: (rest[1] as NSString).expandingTildeInPath)
            do {
                switch rest[0] {
                case "export":
                    try SettingsBackup.export(to: url)
                    emit("Réglages enregistrés dans \(url.path)")
                case "import":
                    try SettingsBackup.import(from: url)
                    emit("Réglages restaurés. Relance Plume pour qu'ils soient tous pris en compte.")
                default:
                    printError("Usage : plume settings export|import <fichier.json>")
                    return 2
                }
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "calls":
            // Diagnostic : les apps qui lisent le micro en ce moment, et celles que Plume reconnaît.
            let processes = MeetingDetector.processesUsingInput()
            if processes.isEmpty { emit("Aucune autre app n'utilise le micro.") }
            for process in processes {
                let known = MeetingDetector.apps[process.bundleID].map { " → \($0.name), proposé après \(Int($0.delay)) s" } ?? ""
                emit("\(process.bundleID) (pid \(process.pid))\(known)")
            }
            return 0

        case "simulate-chord":
            // Essai des raccourcis : simule l'accord ⌃⇧ (ou ⌃⇧⌘ avec « reunion ») tenu N millisecondes.
            let meeting = rest.contains("reunion")
            let hold = rest.compactMap(Int.init).first ?? 120
            simulateChord(command: meeting, holdMilliseconds: hold)
            return 0

        case "mictest":
            // Diagnostic : ouvre le micro choisi deux secondes et compte ce qui arrive. Rien n'est gardé.
            let capture = MicCapture()
            let lock = NSLock()
            var count = 0
            var peak: Float = 0
            capture.onSamples = { samples in
                lock.lock()
                count += samples.count
                peak = max(peak, AudioLevel.rms(samples[...]))
                lock.unlock()
            }
            do { try capture.start() } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            capture.stop()
            let (received, level) = lock.withLock { (count, peak) }
            emit(String(format: "%@ : %.2f s reçues en 2 s, niveau maximal %.4f", capture.deviceName, Double(received) / 16000, level))
            return 0

        case "reprocess":
            // Refait la séparation des voix d'une transcription à partir de son audio conservé.
            let count = take(option: "--speakers", from: &rest).flatMap(Int.init)
            guard let id = rest.first, let transcript = store.load(id: id) else {
                printError("Transcription introuvable.")
                return 1
            }
            do {
                let updated = try await Pipeline.reprocess(transcript, speakerCount: count)
                emit("\(updated.id) : \(updated.speakers.count) voix, \(updated.segments.count) tours de parole")
                return 0
            } catch {
                printError("Échec : \(error.localizedDescription)")
                return 1
            }

        case "words":
            // Diagnostic : mots horodatés et voix attribuée, sur une plage de temps.
            let from = take(option: "--from", from: &rest).flatMap(Double.init) ?? 0
            let to = take(option: "--to", from: &rest).flatMap(Double.init) ?? 60
            guard let path = rest.first, let samples = try? AudioIO.loadSamples(URL(fileURLWithPath: path)) else { return 2 }
            do {
                let engine = SpeechEngine.shared
                try await engine.prepare(model: settings.model)
                let output = try await engine.transcribe(samples)
                let diarization = try await engine.diarize(samples)
                for turn in diarization.turns where turn.end >= from && turn.start <= to {
                    emit(String(format: "TOUR %7.2f → %7.2f  %@", turn.start, turn.end, turn.speaker))
                }
                var previousEnd = 0.0
                for word in output.words where word.end >= from && word.start <= to {
                    let speaker = TranscriptBuilder.speaker(at: (word.start + word.end) / 2, in: diarization.turns) ?? "?"
                    emit(String(format: "%7.2f %7.2f  +%.2f  %@  %@", word.start, word.end, word.start - previousEnd, speaker, word.text))
                    previousEnd = word.end
                }
                return 0
            } catch {
                return 1
            }

        case "aec":
            // Diagnostic : annulation d'écho d'un fichier micro avec le son système en référence.
            guard rest.count >= 3,
                let mic = try? AudioIO.loadSamples(URL(fileURLWithPath: rest[0])),
                var reference = try? AudioIO.loadSamples(URL(fileURLWithPath: rest[1]))
            else { return 2 }
            if reference.count < mic.count { reference += [Float](repeating: 0, count: mic.count - reference.count) }
            reference = Array(reference.prefix(mic.count))
            emit(String(format: "vraisemblance d'écho : %.2f", Pipeline.echoLikelihood(mic: mic, reference: reference)))
            guard let cleaned = try? await SpeechEngine.shared.cancelEcho(mic: mic, reference: reference) else { return 1 }
            Recovery.stash(cleaned, at: URL(fileURLWithPath: rest[2]))
            return 0

        case "sounds":
            guard let directory = rest.first else { return 2 }
            Sounds.export(to: URL(fileURLWithPath: directory, isDirectory: true))
            return 0

        case "selftest":
            // Demande à l'app ouverte de vérifier la capture du son système (résultat dans le journal).
            Remote.send(rest.first == "mic" ? "selftest-mic" : "selftest-system-audio")
            return 0

        case "doctor":
            await Doctor.run()
            return 0

        case "diarize":
            // Diagnostic : tours de parole et ressemblance des voix détectées dans un fichier.
            let raw = take(flag: "--raw", from: &rest)
            let quiet = take(flag: "--summary", from: &rest)
            guard let path = rest.first, let samples = try? AudioIO.loadSamples(URL(fileURLWithPath: path)),
                let output = try? await SpeechEngine.shared.diarize(samples, mergeSimilar: !raw)
            else { return 1 }
            var talk: [String: Double] = [:]
            for turn in output.turns {
                talk[turn.speaker, default: 0] += turn.end - turn.start
                if !quiet { emit(String(format: "%6.2f → %6.2f  %@", turn.start, turn.end, turn.speaker)) }
            }
            for (speaker, seconds) in talk.sorted(by: { $0.key < $1.key }) {
                emit(String(format: "%@ : %.0f s de parole", speaker, seconds))
            }
            let ids = output.embeddings.keys.sorted()
            for (i, a) in ids.enumerated() {
                for b in ids[(i + 1)...] {
                    let similarity = Voiceprint.cosine(output.embeddings[a] ?? [], output.embeddings[b] ?? [])
                    emit(String(format: "ressemblance %@ / %@ : %.3f", a, b, similarity))
                }
            }
            return 0

        case "render":
            guard let directory = rest.first else { return 2 }
            await UIRender.run(directory: directory, demo: rest.contains("--demo"))
            return 0

        case "mcp":
            await MCPServer(store: store).run()
            return 0

        default:
            emit(usage)
            return 2
        }
    }

    /// Rejoue un fichier comme s'il arrivait du micro, pour vérifier la transcription en direct.
    private static func simulateLive(path: String) async -> Int32 {
        do {
            let engine = SpeechEngine.shared
            try await engine.prepare(model: PlumeSettings.shared.model)
            let samples = try AudioIO.loadSamples(URL(fileURLWithPath: path))
            let buffer = SampleBuffer()
            let live = LiveTranscriber(engine: engine, buffer: buffer)
            let step = SpeechEngine.sampleRate * 7 / 10
            var offset = 0
            var busy = 0.0
            while offset < samples.count {
                let end = min(offset + step, samples.count)
                buffer.append(Array(samples[offset..<end]))
                offset = end
                let t0 = Date()
                if let state = await live.tick() {
                    busy += Date().timeIntervalSince(t0)
                    let at = Format.clock(Double(offset) / Double(SpeechEngine.sampleRate))
                    emit("[\(at)] …\(state.committed.suffix(70)) ▸ \(state.volatile)")
                }
            }
            let total = Double(samples.count) / Double(SpeechEngine.sampleRate)
            emit(String(format: "\ncalcul : %.1f s pour %.0f s d'audio (%.1f %% du temps réel)", busy, total, busy / total * 100))
            emit("\nTEXTE EN DIRECT :\n\(await live.state.full)")
            return 0
        } catch {
            printError("Échec : \(error.localizedDescription)")
            return 1
        }
    }

    private static func simulateChord(command: Bool, holdMilliseconds: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            event.type = .flagsChanged
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(15_000)
        }
        var flags: CGEventFlags = [.maskControl]
        post(59, down: true, flags: flags)  // contrôle gauche
        flags.insert(.maskShift)
        post(56, down: true, flags: flags)  // majuscule gauche
        if command {
            flags.insert(.maskCommand)
            post(55, down: true, flags: flags)  // commande gauche
        }
        usleep(UInt32(holdMilliseconds) * 1000)
        if command {
            flags.remove(.maskCommand)
            post(55, down: false, flags: flags)
        }
        flags.remove(.maskShift)
        post(56, down: false, flags: flags)
        post(59, down: false, flags: [])
    }

    // MARK: - Sortie

    struct Summary: Codable {
        var id: String
        var date: Date
        var mode: String
        var duree_s: Int
        var interlocuteurs: [String]
        var apercu: String

        init(_ t: Transcript) {
            id = t.id
            date = t.createdAt
            mode = t.mode.slug
            duree_s = Int(t.duration.rounded())
            interlocuteurs = t.speakers
            apercu = t.preview
        }
    }

    private static func output(_ t: Transcript, json: Bool) {
        if json {
            printJSON(t)
        } else {
            emit(TranscriptStore.markdown(for: t))
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            emit(text)
        }
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }

    private static func readStandardInput() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private static func take(flag: String, from args: inout [String]) -> Bool {
        guard let index = args.firstIndex(of: flag) else { return false }
        args.remove(at: index)
        return true
    }

    private static func take(option: String, from args: inout [String]) -> String? {
        guard let index = args.firstIndex(of: option), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        args.removeSubrange(index...index + 1)
        return value
    }
}

/// Fait dicter l'utilisateur dans l'app ouverte et attend que le texte arrive dans la
/// bibliothèque : le « micro » des scripts et des agents (`plume listen`, outil MCP `listen`).
enum Listener {
    /// Boîte aux lettres remplie par la notification de résultat.
    private final class Mailbox: @unchecked Sendable {
        private let lock = NSLock()
        private var text: String?
        func put(_ value: String) { lock.withLock { text = value } }
        func take() -> String? { lock.withLock { text } }
    }

    static func listen(store: TranscriptStore, timeout: TimeInterval) async -> String? {
        let mailbox = Mailbox()
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Remote.resultNotification, object: nil, queue: nil
        ) { note in
            guard let path = note.object as? String, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(atPath: path)
            mailbox.put(text)
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        let before = store.latest(mode: .dictation)?.id
        let started = Date()
        Remote.send("toggle-capture")
        while Date().timeIntervalSince(started) < timeout {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let text = mailbox.take() { return text }
            // Filet : une dictée nouvelle dans la bibliothèque, commencée après notre demande.
            if let latest = store.latest(mode: .dictation), latest.id != before,
                latest.createdAt >= started.addingTimeInterval(-2)
            {
                return latest.text
            }
        }
        return nil
    }
}
