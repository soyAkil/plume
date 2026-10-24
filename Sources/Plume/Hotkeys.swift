import AppKit
import Carbon.HIToolbox
import PlumeKit

enum HotkeyAction: Int {
    case dictation = 1
    case meeting = 2
    /// Opens the Plume window.
    case open = 3
    /// Pastes the last dictation again.
    case pasteLast = 4
    /// Dictates an instruction that the local AI applies to the selected text.
    case transform = 5
    /// Restores the last cancelled recording.
    case restore = 6
    /// A dictation that opens the game chat, pastes and sends (Minecraft).
    case gameChat = 7

    var mode: RecordingMode? {
        switch self {
        case .dictation, .transform, .gameChat: return .dictation
        case .meeting: return .meeting
        case .open, .pasteLast, .restore: return nil
        }
    }
}

/// Global shortcuts.
///
/// Two mechanisms, both without a system permission:
/// - key + modifiers (⌥Space…): Carbon shortcut, with press and release;
/// - modifier-only combo (⌃⌥…): periodic reading of the modifier state.
///   The combo only counts if it is "clean": no other key or click while it
///   is held, so it doesn't fire on a shortcut like ⌃⌥→.
final class HotkeyManager {
    var onPress: ((HotkeyAction) -> Void)?
    var onRelease: ((HotkeyAction, TimeInterval) -> Void)?
    /// Another key was pressed during a hold: it wasn't a dictation.
    var onCancel: ((HotkeyAction) -> Void)?
    /// The cancel shortcut (Esc by default) was pressed during a recording.
    var onCancelShortcut: (() -> Void)?
    /// Suspended while a new shortcut is being entered in settings.
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
    /// Clean hold duration from which the combo becomes "hold to talk".
    private let holdThreshold: TimeInterval = 0.4

    private struct Chord {
        var start: Date
        var lastChange: Date
        var maxMask: Int
        var keyCount: UInt32
        var clickCount: UInt32
        /// A key or click happened during the combo: it isn't a Plume shortcut.
        var dirty = false
        var fired: HotkeyAction?
        var firedAt: Date?
        /// The triggered hold ended (released or cancelled); wait for the full release.
        var finished = false
        /// The hold was cancelled because the combo grew (⌃⌥ then ⌘).
        var outgrown = false
    }

    /// During a recording, a hold must not stop it before we know whether
    /// the combo is clean: only a clean release counts.
    var holdEnabled = true
    /// After a shortcut is entered in settings, wait until everything is released.
    private var waitingForRelease = false
    /// Window during which another key cancels a hold that was just triggered.
    private let cancelWindow: TimeInterval = 1.0

    init() {
        installCarbonHandler()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reloads the shortcuts from settings.
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
        register(settings.gameChatShortcut, for: .gameChat)
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

    /// The cancel shortcut is only intercepted during a dictation: the rest of the time,
    /// the key (Esc…) keeps its role in other apps.
    func setCancelEnabled(_ enabled: Bool) {
        cancelEnabled = enabled
        if let ref = cancelKey {
            UnregisterEventHotKey(ref)
            cancelKey = nil
        }
        let shortcut = PlumeSettings.shared.cancelShortcut
        // A modifier-only combo can't be used here: it would be confused with those
        // that start a recording.
        guard enabled, let keyCode = shortcut.keyCode else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.cancelID)
        if RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
        {
            cancelKey = ref
        }
    }

    // MARK: - Key + modifiers (Carbon)

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

    // MARK: - Modifier-only combos

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
                // Right after the trigger, a key signals another shortcut (⌃⌥→):
                // cancel. Later, it's an accidental keystroke: ignore it.
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
            // The combo grows after the trigger (⌃⌥ then ⌘): it wasn't that one.
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
                    // ⌃⌥⌘ formed slowly: it was the other shortcut after all.
                    onPress?(action)
                    onRelease?(action, 0)
                }
            } else if !current.dirty, let action = action(for: current.maxMask) {
                // Clean combo released without a triggered hold: toggle.
                onPress?(action)
                onRelease?(action, 0)
            }
            return
        }

        if let fired = current.fired {
            // One of the combo's keys is released: end of the hold.
            if !current.finished, mask != chordMasks[fired] {
                current.finished = true
                onRelease?(fired, now.timeIntervalSince(current.firedAt ?? current.start) + holdThreshold)
            }
        } else if holdEnabled, !current.dirty, mask == current.maxMask, chordMasks[.dictation] == mask,
            now.timeIntervalSince(current.lastChange) >= holdThreshold
        {
            // Dictation combo held: start without waiting for the release.
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

    // MARK: - Conversions and display

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

    /// `⌃⌥` or `⌥Space`.
    static func describe(_ shortcut: Shortcut) -> String {
        guard !shortcut.isEmpty else { return tr("None") }
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

    /// Key name according to the active keyboard layout (AZERTY included).
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
