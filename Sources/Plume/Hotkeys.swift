import AppKit
import Carbon.HIToolbox
import PlumeKit

enum HotkeyAction: Int {
    case dictation = 1
    case meeting = 2
    /// Ouvre la fenêtre de Plume.
    case open = 3
    /// Recolle la dernière dictée.
    case pasteLast = 4
    /// Dicte une consigne que l'IA locale applique au texte sélectionné.
    case transform = 5
    /// Récupère le dernier enregistrement annulé.
    case restore = 6

    var mode: RecordingMode? {
        switch self {
        case .dictation, .transform: return .dictation
        case .meeting: return .meeting
        case .open, .pasteLast, .restore: return nil
        }
    }
}

/// Raccourcis globaux.
///
/// Deux mécanismes, tous deux sans autorisation système :
/// - touche + modificateurs (⌥Espace…) : raccourci Carbon, avec appui et relâchement ;
/// - accord de modificateurs seuls (⌃⌥…) : lecture périodique de l'état des modificateurs.
///   L'accord ne compte que s'il est « propre » : aucune autre touche ni clic pendant qu'il
///   est tenu, pour ne pas se déclencher sur un raccourci comme ⌃⌥→.
final class HotkeyManager {
    var onPress: ((HotkeyAction) -> Void)?
    var onRelease: ((HotkeyAction, TimeInterval) -> Void)?
    /// Une autre touche a été pressée pendant un maintien : ce n'était pas une dictée.
    var onCancel: ((HotkeyAction) -> Void)?
    /// Le raccourci d'annulation (Échap par défaut) a été pressé pendant un enregistrement.
    var onCancelShortcut: (() -> Void)?
    /// Suspendu pendant la saisie d'un nouveau raccourci dans les réglages.
    var isPaused = false {
        didSet { if oldValue, !isPaused { waitingForRelease = true } }
    }

    private var handler: EventHandlerRef?
    private var carbonKeys: [HotkeyAction: EventHotKeyRef] = [:]
    private var cancelKey: EventHotKeyRef?
    private var cancelEnabled = false
    private var pressDates: [HotkeyAction: Date] = [:]
    private var chordMasks: [HotkeyAction: Int] = [:]
    private var timer: Timer?
    private var chord: Chord?

    private static let signature: OSType = 0x504C_554D  // 'PLUM'
    private static let cancelID: UInt32 = 99
    /// Durée de maintien propre à partir de laquelle l'accord devient un « parler en maintenant ».
    private let holdThreshold: TimeInterval = 0.4

    private struct Chord {
        var start: Date
        var lastChange: Date
        var maxMask: Int
        var keyCount: UInt32
        var clickCount: UInt32
        /// Une touche ou un clic a eu lieu pendant l'accord : ce n'est pas un raccourci Plume.
        var dirty = false
        var fired: HotkeyAction?
        var firedAt: Date?
        /// Le maintien déclenché s'est terminé (relâché ou annulé) ; on attend le relâchement complet.
        var finished = false
        /// Le maintien a été annulé parce que l'accord a grandi (⌃⌥ puis ⌘).
        var outgrown = false
    }

    /// Pendant un enregistrement, un maintien ne doit pas arrêter avant qu'on sache si
    /// l'accord est propre : seul un relâchement propre compte.
    var holdEnabled = true
    /// Après la saisie d'un raccourci dans les réglages, on attend que tout soit relâché.
    private var waitingForRelease = false
    /// Fenêtre pendant laquelle une autre touche annule un maintien tout juste déclenché.
    private let cancelWindow: TimeInterval = 1.0

    init() {
        installCarbonHandler()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Relit les raccourcis depuis les réglages.
    func reload() {
        for (_, ref) in carbonKeys { UnregisterEventHotKey(ref) }
        carbonKeys.removeAll()
        chordMasks.removeAll()
        let settings = PlumeSettings.shared
        register(settings.dictationShortcut, for: .dictation)
        register(settings.meetingShortcut, for: .meeting)
        register(settings.openShortcut, for: .open)
        register(settings.pasteLastShortcut, for: .pasteLast)
        register(settings.transformShortcut, for: .transform)
        register(settings.restoreShortcut, for: .restore)
        setCancelEnabled(cancelEnabled)
    }

    private func register(_ shortcut: Shortcut, for action: HotkeyAction) {
        guard !shortcut.isEmpty else { return }
        guard let keyCode = shortcut.keyCode else {
            chordMasks[action] = shortcut.modifiers
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(action.rawValue))
        let status = RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { carbonKeys[action] = ref }
    }

    /// Le raccourci d'annulation n'est intercepté que pendant une dictée : le reste du temps,
    /// la touche (Échap…) garde son rôle dans les autres apps.
    func setCancelEnabled(_ enabled: Bool) {
        cancelEnabled = enabled
        if let ref = cancelKey {
            UnregisterEventHotKey(ref)
            cancelKey = nil
        }
        let shortcut = PlumeSettings.shared.cancelShortcut
        // Un accord de modificateurs seuls ne peut pas servir ici : il se confondrait avec ceux
        // qui démarrent un enregistrement.
        guard enabled, let keyCode = shortcut.keyCode else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.cancelID)
        if RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
        {
            cancelKey = ref
        }
    }

    // MARK: - Touche + modificateurs (Carbon)

    private func installCarbonHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.carbonEvent(id: id.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, types.count, &types,
            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func carbonEvent(id: UInt32, pressed: Bool) {
        guard !isPaused else { return }
        if id == Self.cancelID {
            if pressed { onCancelShortcut?() }
            return
        }
        guard let action = HotkeyAction(rawValue: Int(id)) else { return }
        if pressed {
            pressDates[action] = Date()
            onPress?(action)
        } else {
            let held = pressDates[action].map { Date().timeIntervalSince($0) } ?? 0
            onRelease?(action, held)
        }
    }

    // MARK: - Accords de modificateurs seuls

    private func poll() {
        guard !isPaused, !chordMasks.isEmpty else {
            chord = nil
            return
        }
        let mask = Self.currentModifierMask()
        if waitingForRelease {
            if mask == 0 { waitingForRelease = false }
            chord = nil
            return
        }
        let keys = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        let clicks =
            CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)
            &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: .rightMouseDown)
        let now = Date()

        guard var current = chord else {
            if mask != 0 {
                chord = Chord(start: now, lastChange: now, maxMask: mask, keyCount: keys, clickCount: clicks)
            }
            return
        }

        if keys != current.keyCount || clicks != current.clickCount {
            current.keyCount = keys
            current.clickCount = clicks
            if let firedAt = current.firedAt, !current.finished {
                // Juste après le déclenchement, une touche signale un autre raccourci (⌃⌥→) :
                // on annule. Plus tard, c'est une frappe accidentelle : on l'ignore.
                if now.timeIntervalSince(firedAt) < cancelWindow {
                    current.dirty = true
                    current.finished = true
                    onCancel?(current.fired ?? .dictation)
                }
            } else {
                current.dirty = true
            }
        }
        if mask | current.maxMask != current.maxMask {
            current.maxMask |= mask
            current.lastChange = now
            // L'accord grandit après le déclenchement (⌃⌥ puis ⌘) : ce n'était pas celui-là.
            if let fired = current.fired, !current.finished {
                current.finished = true
                current.outgrown = true
                onCancel?(fired)
            }
        }

        if mask == 0 {
            chord = nil
            if let fired = current.fired {
                if !current.finished {
                    onRelease?(fired, now.timeIntervalSince(current.firedAt ?? current.start) + holdThreshold)
                } else if current.outgrown, !current.dirty, let action = action(for: current.maxMask), action != fired {
                    // ⌃⌥⌘ formé lentement : c'était bien l'autre raccourci.
                    onPress?(action)
                    onRelease?(action, 0)
                }
            } else if !current.dirty, let action = action(for: current.maxMask) {
                // Accord propre relâché sans maintien déclenché : bascule.
                onPress?(action)
                onRelease?(action, 0)
            }
            return
        }

        if let fired = current.fired {
            // Une des touches de l'accord est relâchée : fin du maintien.
            if !current.finished, mask != chordMasks[fired] {
                current.finished = true
                onRelease?(fired, now.timeIntervalSince(current.firedAt ?? current.start) + holdThreshold)
            }
        } else if holdEnabled, !current.dirty, mask == current.maxMask, chordMasks[.dictation] == mask,
            now.timeIntervalSince(current.lastChange) >= holdThreshold
        {
            // Accord de dictée tenu : on démarre sans attendre le relâchement.
            current.fired = .dictation
            current.firedAt = now
            onPress?(.dictation)
        }
        chord = current
    }

    private func action(for mask: Int) -> HotkeyAction? {
        chordMasks.first { $0.value == mask }?.key
    }

    static func currentModifierMask() -> Int {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var mask = 0
        if flags.contains(.maskControl) { mask |= ModifierMask.control }
        if flags.contains(.maskAlternate) { mask |= ModifierMask.option }
        if flags.contains(.maskShift) { mask |= ModifierMask.shift }
        if flags.contains(.maskCommand) { mask |= ModifierMask.command }
        return mask
    }

    // MARK: - Conversions et affichage

    static func carbonModifiers(_ mask: Int) -> UInt32 {
        var result = 0
        if mask & ModifierMask.control != 0 { result |= controlKey }
        if mask & ModifierMask.option != 0 { result |= optionKey }
        if mask & ModifierMask.shift != 0 { result |= shiftKey }
        if mask & ModifierMask.command != 0 { result |= cmdKey }
        return UInt32(result)
    }

    static func mask(from flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.control) { mask |= ModifierMask.control }
        if flags.contains(.option) { mask |= ModifierMask.option }
        if flags.contains(.shift) { mask |= ModifierMask.shift }
        if flags.contains(.command) { mask |= ModifierMask.command }
        return mask
    }

    /// `⌃⌥` ou `⌥Espace`.
    static func describe(_ shortcut: Shortcut) -> String {
        guard !shortcut.isEmpty else { return tr("Aucun") }
        var text = ""
        if shortcut.modifiers & ModifierMask.control != 0 { text += "⌃" }
        if shortcut.modifiers & ModifierMask.option != 0 { text += "⌥" }
        if shortcut.modifiers & ModifierMask.shift != 0 { text += "⇧" }
        if shortcut.modifiers & ModifierMask.command != 0 { text += "⌘" }
        if let keyCode = shortcut.keyCode { text += keyName(keyCode) }
        return text
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Nom de la touche selon la disposition de clavier active (AZERTY compris).
    static func keyName(_ keyCode: Int) -> String {
        if let special = specialKeys[keyCode] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "touche \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { pointer -> OSStatus in
            guard let layout = pointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "touche \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
