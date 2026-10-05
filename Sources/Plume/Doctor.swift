import AVFoundation
import AppKit
import FluidAudio
import PlumeKit

/// `plume doctor` : un état des lieux lisible, pour comprendre pourquoi quelque chose ne marche pas.
enum Doctor {
    @MainActor
    static func run() async {
        let settings = PlumeSettings.shared
        func line(_ label: String, _ value: String) {
            CLI.emit(label.padding(toLength: 30, withPad: " ", startingAt: 0) + value)
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: PlumeSettings.bundleID)
        line("App en cours d'exécution", running.isEmpty ? "non" : "oui")
        line("Bibliothèque", settings.libraryURL.path)
        line("Transcriptions", "\(settings.store.list().count)")
        line("Modèle choisi", settings.model == .custom ? "dossier : \(settings.customModelURL?.path ?? "aucun")" : settings.model.rawValue)
        let cached = settings.model.isAvailableOffline(customDirectory: settings.customModelURL)
        line(settings.model == .custom ? "Dossier complet" : "Modèle téléchargé", cached ? "oui" : "non (téléchargé au premier lancement)")
        line("Historique", settings.keepHistory ? (settings.keepAudio ? "texte et audio" : "texte seulement") : "rien n'est conservé")
        line("Raccourci dictée", HotkeyManager.describe(settings.dictationShortcut))
        line("Raccourci réunion", HotkeyManager.describe(settings.meetingShortcut))

        let mic: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = "accordé"
        case .denied, .restricted: mic = "refusé"
        default: mic = "pas encore demandé"
        }
        // Les autorisations dépendent du programme qui lance la commande : depuis un terminal,
        // ce sont celles du terminal, pas celles de l'app.
        line("Micro (ce processus)", mic)
        line("Accessibilité (ce processus)", Paster.isTrusted ? "accordée" : "non accordée")
        let microphones = AudioDevices.inputs()
        line("Micro utilisé par Plume", AudioDevices.preferredInput(among: microphones)?.name ?? "entrée par défaut du système")
        if let device = AVCaptureDevice.default(for: .audio) {
            line("Entrée par défaut du système", device.localizedName)
        }
        for device in microphones {
            let kind = device.isBuiltIn ? "intégré" : (device.isBluetooth ? "Bluetooth" : "autre")
            line("  micro disponible", "\(device.name) (\(kind))")
        }
        for screen in NSScreen.screens {
            let geometry = NotchGeometry(screen: screen)
            let notch = geometry.hasNotch
                ? "encoche \(Int(geometry.notchWidth)) × \(Int(geometry.topHeight)) pt"
                : "sans encoche (barre de \(Int(geometry.topHeight)) pt)"
            line("Écran \(screen.localizedName)", "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt, \(notch)")
        }
        line("Empreinte vocale", VoiceprintStore.load().map { "apprise sur \($0.samples) dictée(s)" } ?? "pas encore apprise")
        switch LocalAI.availability {
        case .available: line("IA locale", "Apple Intelligence disponible")
        case .unavailable(let reason): line("IA locale", "indisponible — \(reason)")
        }
        line("Règles par application", "\(AppRuleStore.load().count)")
        let calls = MeetingDetector.processesUsingInput()
        line("Apps utilisant le micro", calls.isEmpty ? "aucune" : calls.map(\.bundleID).joined(separator: ", "))
    }
}
