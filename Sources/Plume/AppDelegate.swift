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
    /// Without this, macOS puts apps without a window to sleep (App Nap) and slows down
    /// shortcut detection.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Global dictation shortcuts")

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
        // A call starting in Zoom, Meet, Teams…: the island offers to record.
        meetings.onCallStarted = { [weak self] app in self?.session.suggestMeeting(app: app) }
        if !TestHooks.headless || ProcessInfo.processInfo.environment["PLUME_FAKE_CALL"] != nil { meetings.start() }

        session.onPhaseChanged = { [weak self] phase in
            guard let self else { return }
            if TestHooks.showsIsland { self.island.phaseChanged(phase) }
            self.updateCancelShortcut()
            self.hotkeys.holdEnabled = !self.session.isRecording
            self.updateStatusIcon()
        }
        session.onModeChanged = { [weak self] _ in self?.updateCancelShortcut() }
        session.onLibraryChanged = { [weak self] in self?.app.refresh() }

        hotkeys.onPress = { [weak self] action in
            TestHooks.log("shortcut: press \(action)")
            if action == .open {
                self?.showWindow()
            } else if action == .restore {
                self?.session.restoreCancelled()
            } else {
                self?.session.handlePress(action)
            }
        }
        app.settings.onRulesChanged = { [weak self] in self?.app.refresh() }
        hotkeys.onRelease = { [weak self] in
            TestHooks.log("shortcut: release \($0) after \(String(format: "%.2f", $1)) s")
            self?.session.handleRelease($0, held: $1)
        }
        hotkeys.onCancel = { [weak self] in
            TestHooks.log("shortcut: cancel \($0)")
            self?.session.handleCancel($0)
        }
        hotkeys.onCancelShortcut = { [weak self] in self?.session.cancel() }
        if !TestHooks.headless { hotkeys.reload() }

        app.settings.onShortcutsChanged = { [weak self] in
            if !TestHooks.headless { self?.hotkeys.reload() }
        }
        app.settings.onRecordingShortcut = { [weak self] recording in self?.hotkeys.isPaused = recording }
        app.settings.onModelChanged = { [weak self] in self?.session.loadModel() }
        app.onStartFromWindow = { [weak self] in self?.startFromWindow() }
        app.settings.onCancelledRetentionChanged = { [weak self] in
            self?.session.purgeCancelled()
            self?.app.library.reload()
        }
        app.settings.onAppearanceChanged = { [weak self] in self?.applyAppearance() }
        app.settings.onLanguageChanged = { [weak self] in
            self?.buildMainMenu()
            self?.updateStatusIcon()
        }

        settings.store.prepare()
        // Sleep in the middle of a recording: finish with what was captured.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.session.stop() }
        }
        remote = Remote.listen(session: session) { [weak self] in self?.showWindow() }
        Remote.onSnapshot = { [weak self] in
            self?.island.debugSnapshot(to: FileManager.default.temporaryDirectory.appendingPathComponent("plume-island.png"))
        }
        Remote.onDrawer = { [weak self] open in self?.island.debugPin(open) }
        if !TestHooks.headless { setupStatusItem() }
        Log.write("launch: Plume \(Updates.runningVersion)")
        Updates.shared.start()
        session.loadModel()
        purgeOldAudio()
        session.purgeCancelled()

        // First launch, or a missing permission: the window opens on Home.
        if TestHooks.fakeMic == nil, !settings.onboarded || app.settings.permissionsMissing {
            settings.onboarded = true
            showWindow()
        }
    }

    /// Audio older than the chosen retention period is deleted at launch; the
    /// text stays.
    private func purgeOldAudio() {
        let days = settings.audioRetentionDays
        guard days > 0 else { return }
        let store = settings.store
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        Task.detached(priority: .utility) {
            let count = store.dropAudio(olderThan: cutoff)
            if count > 0 { Log.write("audio deleted from \(count) transcript(s) older than \(days) days") }
        }
    }

    /// Home button: Plume steps aside to hand control back to the previous app (the one where the
    /// text will be pasted), then recording starts in the notch. During a dictation, the
    /// same button finishes it.
    private func startFromWindow() {
        if session.phase == .recording {
            session.stop()
            return
        }
        NSApp.hide(nil)
        // Wait for the previous app to come back to the front: it is the one the dictation remembers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.session.start(.dictation) }
    }

    /// The cancel shortcut is only intercepted during a dictation (not during an hour-long
    /// meeting, which is cancelled from the notch).
    private func updateCancelShortcut() {
        guard !TestHooks.headless else { return }
        hotkeys.setCancelEnabled(session.phase == .recording && session.mode == .dictation)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// Links `plume://dictee`, `plume://reunion`, `plume://stop`, `plume://cancel`, `plume://pause`,
    /// `plume://recoller`, `plume://recuperer`, `plume://ouvrir`: for Shortcuts, Raycast, a Stream Deck.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "plume" {
            let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            Log.write("link: plume://\(command)")
            switch command {
            case "dictee", "dictée", "dictation": session.toggle(.dictation)
            case "reunion", "réunion", "meeting": session.toggle(.meeting)
            case "transformer", "transform": session.toggle(.dictation, intent: .transform)
            case "stop", "terminer": session.stop()
            case "cancel", "annuler": session.cancel()
            case "pause": session.togglePause()
            case "recoller", "paste": session.pasteLast()
            case "recuperer", "récupérer", "restore": session.restoreCancelled()
            case "ouvrir", "open", "": showWindow()
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = tr("Plume — click: open · right-click: menu")
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        // The app icon's feather, filled.
        let image = Glyph.plume.image(size: 18)
        image.accessibilityDescription = "Plume"
        button.image = image
        button.contentTintColor = session.phase == .recording ? .systemRed : nil
    }

    /// Click: the Plume window. Right click (or ⌃click): a short menu.
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
            item(recording ? tr("Finish recording") : tr("Dictate"), #selector(toggleDictation),
                hint: HotkeyManager.describe(settings.dictationShortcut)))
        if recording {
            menu.addItem(item(session.paused ? tr("Resume") : tr("Pause"), #selector(togglePause)))
            menu.addItem(item(tr("Cancel"), #selector(cancelRecording), hint: HotkeyManager.describe(settings.cancelShortcut)))
        } else {
            menu.addItem(item(tr("Record a meeting"), #selector(toggleMeeting)))
            menu.addItem(
                item(tr("Paste the last dictation again"), #selector(pasteLast), hint: HotkeyManager.describe(settings.pasteLastShortcut)))
            if !settings.cancelled.list().isEmpty {
                menu.addItem(
                    item(
                        tr("Restore the last cancelled recording"), #selector(restoreCancelled),
                        hint: HotkeyManager.describe(settings.restoreShortcut)))
            }
            // The latest dictations, to copy with one click.
            let recent = settings.store.list(limit: 6, mode: .dictation)
            if !recent.isEmpty {
                let submenu = NSMenu()
                for transcript in recent {
                    let entry = NSMenuItem(title: String(transcript.preview.prefix(60)), action: #selector(copyRecent(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = transcript.text
                    submenu.addItem(entry)
                }
                let parent = NSMenuItem(title: tr("Copy a recent dictation"), action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item(tr("Open Plume"), #selector(openWindow)))
        if Updates.shared.isAvailable {
            menu.addItem(item(tr("Check for updates…"), #selector(checkForUpdates)))
        }
        menu.addItem(item(tr("Quit Plume"), #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "", hint: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let hint, hint != tr("None") {
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
    @objc private func restoreCancelled() { session.restoreCancelled() }
    @objc private func copyRecent(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String { Paster.copy(text) }
    }
    @objc private func openWindow() { showWindow() }
    @objc private func checkForUpdates() { Updates.shared.check() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Window

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
        // While the window is open, Plume behaves like a regular app
        // (Dock, ⌘Tab); when closed, it goes back to being a plain menu bar icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Window keys, as in the portfolio: 1 to 4 for the pages, T for the theme,
    /// S for the sounds. No effect while typing in a field or recording a shortcut.
    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, !self.hotkeys.isPaused,
                event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                !(window.firstResponder is NSText), let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }
            switch key {
            case "1", "2", "3", "4", "5", "&", "é", "\"", "'", "(":
                // Top row of a French keyboard: & é " ' ( without shift.
                let index = ["1": 0, "2": 1, "3": 2, "4": 3, "5": 4, "&": 0, "é": 1, "\"": 2, "'": 3, "(": 4][key] ?? 0
                withAnimation(UI.spring) { self.app.page = Page.allCases[index] }
            case "t":
                Sounds.play(.tab)
                let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.app.settings.appearance = dark ? "light" : "dark"
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
        case "light": window?.appearance = NSAppearance(named: .aqua)
        case "system": window?.appearance = nil
        default: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func windowWillClose(_ notification: Notification) {
        app.library.player.stop()
        NSApp.setActivationPolicy(.accessory)
    }

    /// Main menu: needed for ⌘C, ⌘V, ⌘W and ⌘Q to work in the window.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: tr("Plume"))
        appItem.submenu?.addItem(
            NSMenuItem(title: tr("Hide Plume"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(
            NSMenuItem(title: tr("Quit Plume"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(appItem)

        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: tr("Edit"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Cancel"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.submenu?.addItem(NSMenuItem(title: tr("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.submenu?.addItem(
            NSMenuItem(title: tr("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(edit)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: tr("Window"))
        windowItem.submenu?.addItem(
            NSMenuItem(title: tr("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu?.addItem(
            NSMenuItem(title: tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
