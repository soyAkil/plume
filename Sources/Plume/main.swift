import AppKit
import PlumeKit

/// Lancé par un lien symbolique (`~/.local/bin/plume`), le binaire ne trouve pas son app :
/// `Bundle.main` désigne le dossier du lien, sans les sons enregistrés ni les polices. On se
/// relance depuis le chemin résolu du binaire lancé, transmis par le noyau, et non d'après
/// `Bundle.main`, que la variable `CFProcessPath` peut détourner. `realpath` étant idempotent,
/// la relance n'a lieu qu'une fois.
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

let arguments = CommandLine.arguments
// La langue de l'interface vaut aussi pour la ligne de commande (titres, noms d'interlocuteurs).
L10n.current = PlumeSettings.shared.language

if CLI.handles(arguments) {
    // Mode ligne de commande : pas d'interface, on sort avec le code de la commande.
    // Les bibliothèques de modèles écrivent des traces sur la sortie standard : on les
    // renvoie vers la sortie d'erreur pour que seul notre résultat reste sur stdout.
    CLI.isolateStandardOutput()
    Task.detached {
        let code = await CLI.run(arguments)
        exit(code)
    }
    // Boucle d'événements sur le vrai thread principal (AppKit en a besoin pour `render`).
    while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
} else {
    // Une seule instance : si Plume tourne déjà, on la laisse faire. Une instance d'essai,
    // sur son propre canal de commande, peut tourner à côté.
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
