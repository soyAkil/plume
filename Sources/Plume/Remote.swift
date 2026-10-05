import AVFoundation
import Foundation
import PlumeKit

/// Pilotage de l'app en cours d'exécution depuis la ligne de commande
/// (`plume toggle dictee`, `plume stop`…), utile pour Raycast, Raccourcis ou un Stream Deck.
enum Remote {
    /// Canal de commande. La variable `PLUME_CHANNEL` en ouvre un autre, pour piloter une
    /// instance d'essai sans toucher à l'app installée.
    static let notification = Notification.Name(
        "studio.brigode.plume.command" + (ProcessInfo.processInfo.environment["PLUME_CHANNEL"].map { "." + $0 } ?? ""))

    static func send(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: command, userInfo: nil, deliverImmediately: true)
    }

    /// Canal de retour : le texte d'une dictée demandée par `plume listen` ou l'outil MCP.
    static let resultNotification = Notification.Name(notification.rawValue + ".result")

    /// Remet le texte d'une capture à qui l'attend : écrit dans un fichier temporaire (une
    /// notification ne porte pas un long texte), dont le chemin est notifié. Le destinataire
    /// supprime le fichier une fois lu.
    static func deliver(_ transcript: Transcript) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plume-capture-\(transcript.id).txt")
        guard (try? transcript.text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        DistributedNotificationCenter.default().postNotificationName(
            resultNotification, object: url.path, userInfo: nil, deliverImmediately: true)
    }

    /// Diagnostic de l'île, branché par l'app.
    nonisolated(unsafe) static var onSnapshot: (() -> Void)?
    /// Diagnostic : ouvrir (vrai) ou refermer (faux) le tiroir de l'île sans la souris.
    nonisolated(unsafe) static var onDrawer: ((Bool) -> Void)?

    @MainActor
    static func listen(session: SessionController, onOpen: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            guard let command = note.object as? String else { return }
            Task { @MainActor in
                switch command {
                case "toggle-dictee": session.toggle(.dictation)
                case "toggle-reunion": session.toggle(.meeting)
                // Dictée sans collage : le texte attend dans la bibliothèque (`plume listen`, outil MCP).
                case "toggle-capture": session.toggle(.dictation, intent: .capture)
                case "toggle-transform": session.toggle(.dictation, intent: .transform)
                case "stop": session.stop()
                case "cancel": session.cancel()
                case "pause": session.togglePause()
                case "paste-last": session.pasteLast()
                case "restore": session.restoreCancelled()
                case "open": onOpen()
                case "snapshot": onSnapshot?()
                case "tiroir-ouvert": onDrawer?(true)
                case "tiroir-ferme": onDrawer?(false)
                case "selftest-system-audio": SelfTest.systemAudio()
                case "selftest-mic": SelfTest.microphone()
                default: break
                }
            }
        }
    }
}

/// Crochets d'essai, activés par des variables d'environnement : rejouer un fichier à la
/// place du micro ou du son système, et ne rien coller. Sans effet en usage normal.
enum TestHooks {
    private static let environment = ProcessInfo.processInfo.environment

    static var fakeMic: URL? { environment["PLUME_FAKE_MIC"].map { URL(fileURLWithPath: $0) } }
    static var fakeSystem: URL? { environment["PLUME_FAKE_SYSTEM"].map { URL(fileURLWithPath: $0) } }
    static var noPaste: Bool { environment["PLUME_NO_PASTE"] != nil }
    /// Instance d'essai invisible : ni île, ni icône, ni raccourcis globaux, pour ne pas
    /// gêner l'utilisateur ni réagir à ses propres frappes pendant un essai.
    static var headless: Bool { environment["PLUME_HEADLESS"] != nil }
    /// En mode invisible, montre tout de même l'île (pour contrôler son dessin).
    static var showsIsland: Bool { !headless || environment["PLUME_SHOW_ISLAND"] != nil }
    static var verbose: Bool { environment["PLUME_VERBOSE"] != nil }
    /// Essai du système de mise à jour par une instance invisible : vérification immédiate,
    /// téléchargement et installation sans interface.
    static var updates: Bool { environment["PLUME_UPDATES"] != nil }

    static func log(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(("[plume] " + message() + "\n").data(using: .utf8)!)
    }
}

/// Journal de l'app : `~/Library/Logs/Plume/plume.log`.
enum Log {
    private static let queue = DispatchQueue(label: "plume.log")
    static let url: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Plume", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("plume.log")
    }()

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        TestHooks.log(message)
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Source audio commune au micro, au son système et aux fichiers rejoués.
protocol AudioSource: AnyObject {
    var onSamples: (([Float]) -> Void)? { get set }
    func start() throws
    func stop()
}

extension MicCapture: AudioSource {}
extension SystemAudioCapture: AudioSource {}

/// Rejoue un fichier audio au rythme du temps réel, comme s'il arrivait d'un micro.
final class FileCapture: AudioSource {
    var onSamples: (([Float]) -> Void)?
    private let url: URL
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "plume.file-capture")

    init(url: URL) {
        self.url = url
    }

    func start() throws {
        let samples = try AudioIO.loadSamples(url)
        let chunk = SpeechEngine.sampleRate / 20  // 50 ms
        var offset = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if offset < samples.count {
                let end = min(offset + chunk, samples.count)
                self.onSamples?(Array(samples[offset..<end]))
                offset = end
            } else {
                // Fin du fichier : silence, comme un micro resté ouvert.
                self.onSamples?([Float](repeating: 0, count: chunk))
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

/// Vérification de la capture du son système, sans rien enregistrer : on ouvre le tap trois
/// secondes et on note dans le journal ce qui arrive.
@MainActor
enum SelfTest {
    private static var capture: SystemAudioCapture?

    private static var mic: MicCapture?

    /// Ouvre le micro une seconde et note dans le journal lequel a été utilisé et s'il capte.
    /// Rien n'est enregistré.
    static func microphone() {
        guard mic == nil, Permissions.microphoneGranted else {
            Log.write("essai micro : autorisation manquante ou essai déjà en cours")
            return
        }
        let capture = MicCapture()
        let lock = NSLock()
        var count = 0
        var peak: Float = 0
        capture.onSamples = { samples in
            let level = AudioLevel.rms(samples[...])
            lock.lock()
            count += samples.count
            peak = max(peak, level)
            lock.unlock()
        }
        do {
            try capture.start()
        } catch {
            Log.write("essai micro : échec — \(error.localizedDescription)")
            return
        }
        mic = capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            capture.stop()
            mic = nil
            lock.lock()
            let seconds = Double(count) / Double(SpeechEngine.sampleRate)
            let level = peak
            lock.unlock()
            Log.write(String(format: "essai micro : « %@ », %.2f s reçues en 1 s, niveau maximal %.4f", capture.deviceName, seconds, level))
        }
    }

    static func systemAudio() {
        guard capture == nil else { return }
        let tap = SystemAudioCapture()
        let lock = NSLock()
        var count = 0
        var peak: Float = 0
        tap.onSamples = { samples in
            let level = AudioLevel.rms(samples[...])
            lock.lock()
            count += samples.count
            peak = max(peak, level)
            lock.unlock()
        }
        try? tap.start()
        capture = tap
        Log.write("essai son système : démarrage demandé")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            tap.stop()
            capture = nil
            lock.lock()
            let seconds = Double(count) / Double(SpeechEngine.sampleRate)
            let level = peak
            lock.unlock()
            Log.write(String(format: "essai son système : %.2f s reçues en 3 s, niveau maximal %.4f", seconds, level))
        }
    }
}
