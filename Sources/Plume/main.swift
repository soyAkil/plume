import AppKit
import PlumeKit

/// Launched through a symbolic link (`~/.local/bin/plume`), the binary doesn't find its app:
/// `Bundle.main` points to the link's folder, without the bundled sounds or fonts. It
/// relaunches from the resolved path of the running binary, passed by the kernel, and not from
/// `Bundle.main`, which the `CFProcessPath` variable can hijack. Since `realpath` is idempotent,
/// the relaunch happens only once.
private func relaunchFromRealPathIfNeeded() {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0, let resolved = realpath(buffer, nil) else { return }
    let path = String(cString: buffer)
    let real = String(cString: resolved)
    free(resolved)
    guard real != path, real.contains(".app/Contents/MacOS/") else { return }
    execv(real, CommandLine.unsafeArgv)
}

relaunchFromRealPathIfNeeded()

// Before any FluidAudio call: FluidAudio reads the revision overrides unsynchronized.
VoiceAssets.pinRevision()

let arguments = CommandLine.arguments
// The interface language also applies to the command line (titles, speaker names).
L10n.current = PlumeSettings.shared.language

if CLI.handles(arguments) {
    // Command line mode: no interface, exit with the command's code.
    // Model libraries write traces to standard output: redirect them
    // to standard error so that only our result stays on stdout.
    CLI.isolateStandardOutput()
    Task.detached {
        let code = await CLI.run(arguments)
        exit(code)
    }
    // Event loop on the real main thread (AppKit needs it for `render`).
    while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
} else {
    // A single instance: if Plume is already running, leave it alone. A trial instance,
    // on its own command channel, can run alongside.
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: PlumeSettings.bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    let trial = ProcessInfo.processInfo.environment["PLUME_CHANNEL"] != nil
    if Bundle.main.bundleIdentifier == PlumeSettings.bundleID, !others.isEmpty, !trial {
        others.first?.activate()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
