import AppKit
import Sparkle

/// Automatic updates (Sparkle). The feed and the signing key are written into Info.plist by
/// `scripts/release.sh`, and by `scripts/build.sh` for dev builds; a binary without them,
/// such as `.build` or a trial release, never looks for an update.
@MainActor
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = Updates()

    /// Version found during a background check, not yet presented.
    @Published private(set) var pending: String?
    @Published var automatic = true {
        didSet {
            if let updater = controller?.updater, updater.automaticallyChecksForUpdates != automatic {
                updater.automaticallyChecksForUpdates = automatic
            }
        }
    }

    private var controller: SPUStandardUpdaterController?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// The running app's version and build number, for `plume doctor` and the launch log line.
    static var runningVersion: String { versionLine(info: Bundle.main.infoDictionary ?? [:]) }

    /// "<version> (<build>)", for example `1.0.2-dev+8553033 (202610071530)`: a dev build is
    /// told apart by both. Without a version (a bare `.build` binary), "—", even if a build
    /// number is present. Nonisolated so tests call it off the main actor.
    nonisolated static func versionLine(info: [String: Any]) -> String {
        guard let short = info["CFBundleShortVersionString"] as? String else { return "—" }
        guard let build = info["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    /// True when Info.plist has a feed and key (releases and dev builds); false in a `.build`
    /// binary or a trial release.
    var isAvailable: Bool { controller != nil }

    func start() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard controller == nil, info["SUFeedURL"] != nil, info["SUPublicEDKey"] != nil else { return }
        guard !TestHooks.headless || TestHooks.updates else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automatic = controller.updater.automaticallyChecksForUpdates
        // Headless trial run: immediate check. Automatic download is
        // requested by the trial app's Info.plist, not by a setting, so nothing is
        // written to the installed app's preferences.
        if TestHooks.updates { controller.updater.checkForUpdatesInBackground() }
    }

    /// Check requested by the user: Sparkle shows the result, whatever it is.
    func check() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: Log

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.write("update: version \(item.displayVersionString) found")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.write("update: nothing new")
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Log.write("update: version \(item.displayVersionString) downloaded")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Log.write("update: installing version \(item.displayVersionString)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        // 1001: "already up to date", this is not an incident.
        if error.domain == SUSparkleErrorDomain, error.code == 1001 { return }
        Log.write("update: failed — \(error.localizedDescription)")
    }

    nonisolated func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // In normal use, installation waits until Plume is quit.
        guard TestHooks.updates else { return false }
        immediateInstallHandler()
        return true
    }

    // MARK: Discreet reminders

    // Plume lives in the menu bar: an update window popping up while you
    // dictate elsewhere would be unwelcome. An update found in the background is therefore announced
    // by a simple button in Plume's window, and only opens if asked.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in
            if !handleShowingUpdate { self.pending = version }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pending = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pending = nil }
    }
}
