import AppKit
import PlumeKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = PlumeSettings.shared
    private let session = SessionController()
    private let hotkeys = HotkeyManager()
    private let meetings = MeetingDetector()
    private lazy var app = AppModel(session: session)
    private var island: IslandController!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var remote: NSObjectProtocol?
    /// Sans cela, macOS met en sommeil les apps sans fenêtre (App Nap) et ralentit la
    /// détection des raccourcis.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Raccourcis globaux de dictée")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        L10n.current = settings.language
        Fonts.register()
        Sounds.live = true
        buildMainMenu()
        installKeys()

        island = IslandController(session: session)
        island.onOpen = { [weak self] transcript in
            self?.session.dismiss()
            self?.showWindow(opening: transcript)
        }
        // Un appel qui démarre dans Zoom, Meet, Teams… : l'île propose d'enregistrer.
        meetings.onCallStarted = { [weak self] app in self?.session.suggestMeeting(app: app) }
        if !TestHooks.headless || ProcessInfo.processInfo.environment["PLUME_FAKE_CALL"] != nil { meetings.start() }

        session.onPhaseChanged = { [weak self] phase in
            guard let self else { return }
            if TestHooks.showsIsland { self.island.phaseChanged(phase) }
            self.updateEscape()
            self.hotkeys.holdEnabled = !self.session.isRecording
            self.updateStatusIcon()
        }
        session.onModeChanged = { [weak self] _ in self?.updateEscape() }
        session.onLibraryChanged = { [weak self] in self?.app.refresh() }

        hotkeys.onPress = { [weak self] action in
            TestHooks.log("raccourci : appui \(action)")
            if action == .open {
                self?.showWindow()
            } else {
                self?.session.handlePress(action)
            }
        }
        app.settings.onRulesChanged = { [weak self] in self?.app.refresh() }
        hotkeys.onRelease = { [weak self] in
            TestHooks.log("raccourci : relâchement \($0) après \(String(format: "%.2f", $1)) s")
            self?.session.handleRelease($0, held: $1)
        }
        hotkeys.onCancel = { [weak self] in
            TestHooks.log("raccourci : annulation \($0)")
            self?.session.handleCancel($0)
        }
        hotkeys.onEscape = { [weak self] in self?.session.cancel() }
        if !TestHooks.headless { hotkeys.reload() }

        app.settings.onShortcutsChanged = { [weak self] in
            if !TestHooks.headless { self?.hotkeys.reload() }
        }
        app.settings.onRecordingShortcut = { [weak self] recording in self?.hotkeys.isPaused = recording }
        app.settings.onModelChanged = { [weak self] in self?.session.loadModel() }
        app.settings.onAppearanceChanged = { [weak self] in self?.applyAppearance() }
        app.settings.onLanguageChanged = { [weak self] in
            self?.buildMainMenu()
            self?.updateStatusIcon()
        }

        settings.store.prepare()
        // Mise en veille en plein enregistrement : on termine avec ce qui a été capté.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.session.stop() }
        }
        remote = Remote.listen(session: session) { [weak self] in self?.showWindow() }
        Remote.onSnapshot = { [weak self] in
            self?.island.debugSnapshot(to: FileManager.default.temporaryDirectory.appendingPathComponent("plume-ile.png"))
        }
        Remote.onDrawer = { [weak self] open in self?.island.debugPin(open) }
        if !TestHooks.headless { setupStatusItem() }
        Updates.shared.start()
        session.loadModel()
        purgeOldAudio()

        // Premier lancement, ou autorisation manquante : la fenêtre s'ouvre sur l'accueil.
        if TestHooks.fakeMic == nil, !settings.onboarded || app.settings.permissionsMissing {
            settings.onboarded = true
            showWindow()
        }
    }

    /// L'audio plus ancien que la durée de conservation choisie est supprimé au lancement ; le
    /// texte, lui, reste.
    private func purgeOldAudio() {
        let days = settings.audioRetentionDays
        guard days > 0 else { return }
        let store = settings.store
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        Task.detached(priority: .utility) {
            let count = store.dropAudio(olderThan: cutoff)
            if count > 0 { Log.write("audio supprimé sur \(count) transcription(s) de plus de \(days) jours") }
        }
    }

    /// Échap n'est intercepté que pendant une dictée (pas pendant une réunion d'une heure).
    private func updateEscape() {
        guard !TestHooks.headless else { return }
        hotkeys.setEscapeEnabled(session.phase == .recording && session.mode == .dictation)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// Liens `plume://dictee`, `plume://reunion`, `plume://stop`, `plume://cancel`, `plume://pause`,
    /// `plume://recoller`, `plume://ouvrir` : pour Raccourcis, Raycast, un Stream Deck.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "plume" {
            let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            Log.write("lien : plume://\(command)")
            switch command {
            case "dictee", "dictée", "dictation": session.toggle(.dictation)
            case "reunion", "réunion", "meeting": session.toggle(.meeting)
            case "transformer", "transform": session.toggle(.dictation, intent: .transform)
            case "stop", "terminer": session.stop()
            case "cancel", "annuler": session.cancel()
            case "pause": session.togglePause()
            case "recoller", "paste": session.pasteLast()
            case "ouvrir", "open", "": showWindow()
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown()
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = tr("Plume — clic : ouvrir · clic droit : menu")
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        // La plume de l'icône de l'app, en forme pleine.
        let image = Glyph.plume.image(size: 18)
        image.accessibilityDescription = "Plume"
        button.image = image
        button.contentTintColor = session.phase == .recording ? .systemRed : nil
    }

    /// Clic : la fenêtre de Plume. Clic droit (ou ⌃clic) : un court menu.
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard secondary else {
            showWindow()
            return
        }
        let menu = NSMenu()
        let recording = session.phase == .recording
        menu.addItem(
            item(recording ? tr("Terminer l'enregistrement") : tr("Dicter"), #selector(toggleDictation),
                hint: HotkeyManager.describe(settings.dictationShortcut)))
        if recording {
            menu.addItem(item(session.paused ? tr("Reprendre") : tr("Mettre en pause"), #selector(togglePause)))
            menu.addItem(item(tr("Annuler"), #selector(cancelRecording)))
        } else {
            menu.addItem(item(tr("Enregistrer une réunion"), #selector(toggleMeeting)))
            menu.addItem(
                item(tr("Recoller la dernière dictée"), #selector(pasteLast), hint: HotkeyManager.describe(settings.pasteLastShortcut)))
            // Les dernières dictées, à recopier d'un clic.
            let recent = settings.store.list(limit: 6, mode: .dictation)
            if !recent.isEmpty {
                let submenu = NSMenu()
                for transcript in recent {
                    let entry = NSMenuItem(title: String(transcript.preview.prefix(60)), action: #selector(copyRecent(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = transcript.text
                    submenu.addItem(entry)
                }
                let parent = NSMenuItem(title: tr("Copier une dictée récente"), action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item(tr("Ouvrir Plume"), #selector(openWindow)))
        if Updates.shared.isAvailable {
            menu.addItem(item(tr("Rechercher une mise à jour…"), #selector(checkForUpdates)))
        }
        menu.addItem(item(tr("Quitter Plume"), #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "", hint: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let hint, hint != tr("Aucun") {
            let text = NSMutableAttributedString(string: title)
            text.append(
                NSAttributedString(
                    string: "   \(hint)",
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 13)]))
            item.attributedTitle = text
        }
        return item
    }

    @objc private func toggleDictation() {
        if session.phase == .recording { session.stop() } else { session.start(.dictation) }
    }
    @objc private func toggleMeeting() { session.toggle(.meeting) }
    @objc private func togglePause() { session.togglePause() }
    @objc private func cancelRecording() { session.cancel() }
    @objc private func pasteLast() { session.pasteLast() }
    @objc private func copyRecent(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String { Paster.copy(text) }
    }
    @objc private func openWindow() { showWindow() }
    @objc private func checkForUpdates() { Updates.shared.check() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Fenêtre

    private func showWindow(opening transcript: Transcript? = nil) {
        if window == nil {
            let host = NSHostingController(rootView: AppShell(app: app, session: session))
            let window = NSWindow(contentViewController: host)
            window.title = "Plume"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 1040, height: 740))
            window.minSize = NSSize(width: 880, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("PlumeFenetre")
            self.window = window
            applyAppearance()
        }
        app.refresh()
        app.settings.refreshPermissions()
        if window?.isVisible != true { Sounds.play(.windowOpen) }
        if let transcript { app.open(transcript) }
        // Tant que la fenêtre est ouverte, Plume se comporte comme une app ordinaire
        // (Dock, ⌘Tab) ; fermée, elle redevient une simple icône de barre de menus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Touches de la fenêtre, comme sur le portfolio : 1 à 4 pour les pages, T pour le thème,
    /// S pour les sons. Sans effet pendant qu'on écrit dans un champ ou qu'on saisit un raccourci.
    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, !self.hotkeys.isPaused,
                event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                !(window.firstResponder is NSText), let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }
            switch key {
            case "1", "2", "3", "4", "5", "&", "é", "\"", "'", "(":
                // Rangée du haut d'un clavier français : & é " ' ( sans majuscule.
                let index = ["1": 0, "2": 1, "3": 2, "4": 3, "5": 4, "&": 0, "é": 1, "\"": 2, "'": 3, "(": 4][key] ?? 0
                withAnimation(UI.spring) { self.app.page = Page.allCases[index] }
            case "t":
                Sounds.play(.tab)
                let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.app.settings.appearance = dark ? "clair" : "sombre"
            case "s":
                self.app.settings.sounds.toggle()
                if self.app.settings.sounds { Sounds.play(.confirm) }
            default:
                return event
            }
            return nil
        }
    }

    private func applyAppearance() {
        switch settings.appearance {
        case "clair": window?.appearance = NSAppearance(named: .aqua)
        case "systeme": window?.appearance = nil
        default: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func windowWillClose(_ notification: Notification) {
        app.library.player.stop()
        NSApp.setActivationPolicy(.accessory)
    }

    /// Menu principal : nécessaire pour que ⌘C, ⌘V, ⌘W et ⌘Q fonctionnent dans la fenêtre.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: tr("Plume"))
        appItem.submenu?.addItem(
            NSMenuItem(title: tr("Masquer Plume"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(
            NSMenuItem(title: tr("Quitter Plume"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(appItem)

        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: tr("Édition"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Annuler"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.submenu?.addItem(
            NSMenuItem(title: tr("Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(edit)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: tr("Fenêtre"))
        windowItem.submenu?.addItem(
            NSMenuItem(title: tr("Fermer"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu?.addItem(
            NSMenuItem(title: tr("Réduire"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
