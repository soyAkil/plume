import Foundation

/// Bibliothèque de transcripts sur disque : un dossier lisible par un humain comme par une IA.
///
///     ~/Plume/
///       LISEZMOI.md                  mode d'emploi du dossier (pour les IA)
///       dernier.md                   copie du transcript le plus récent
///       index.jsonl                  une ligne JSON par transcript, du plus ancien au plus récent
///       2026-10/
///         2026-10-02_14-31-05_dictee.md      texte lisible, avec en-tête
///         2026-10-02_14-31-05_dictee.json    données complètes (segments, interlocuteurs)
///         2026-10-02_14-31-05_mic.m4a        audio
public final class TranscriptStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    /// Verrou commun à toutes les instances : plusieurs peuvent viser le même dossier.
    private static let sharedLock = NSRecursiveLock()
    private var lock: NSRecursiveLock { Self.sharedLock }
    /// Identifiants déjà attribués dans ce processus, y compris ceux dont le fichier n'est pas encore écrit.
    private static var issued = Set<String>()

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Identifiants et chemins

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    /// « 2 oct. 2026 à 11:30 » ou « Oct 2, 2026 at 11:30 AM », selon la langue en vigueur.
    private static var titleFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    /// Identifiant libre pour cette date. En cas de collision dans la même seconde, une lettre
    /// (`b`, `c`…) est ajoutée : l'ordre alphabétique des fichiers reste l'ordre chronologique.
    public func makeID(for date: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }
        let base = Self.idFormatter.string(from: date)
        var candidate = base
        var letter = UInt8(ascii: "b")
        // Réservé dès maintenant : deux imports lancés dans la même seconde ne se marchent pas dessus.
        while Self.issued.contains(root.path + "/" + candidate) || existingJSON(forID: candidate) != nil,
            letter <= UInt8(ascii: "z")
        {
            candidate = base + String(UnicodeScalar(letter))
            letter += 1
        }
        Self.issued.insert(root.path + "/" + candidate)
        return candidate
    }

    /// Date portée par un identifiant (`2026-10-02_14-31-05`, éventuellement suivi d'une lettre).
    public static func date(fromID id: String) -> Date? {
        idFormatter.date(from: String(id.prefix(19)))
    }

    /// Dossier mensuel d'un identifiant (`2026-10`).
    public func directory(forID id: String) -> URL {
        root.appendingPathComponent(String(id.prefix(7)), isDirectory: true)
    }

    public func ensureDirectory(forID id: String) throws -> URL {
        let dir = directory(forID: id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func existingJSON(forID id: String) -> URL? {
        let dir = directory(forID: id)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        guard let name = names.first(where: { $0.hasPrefix(id + "_") && $0.hasSuffix(".json") }) else { return nil }
        return dir.appendingPathComponent(name)
    }

    public func markdownURL(for t: Transcript) -> URL {
        directory(forID: t.id).appendingPathComponent("\(t.id)_\(t.mode.slug).md")
    }

    public func jsonURL(for t: Transcript) -> URL {
        directory(forID: t.id).appendingPathComponent("\(t.id)_\(t.mode.slug).json")
    }

    public func audioURLs(for t: Transcript) -> [URL] {
        let dir = directory(forID: t.id)
        return t.audioFiles.map { dir.appendingPathComponent($0) }
    }

    // MARK: - Écriture

    public func save(_ t: Transcript) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureRoot()
        _ = try ensureDirectory(forID: t.id)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(t).write(to: jsonURL(for: t), options: .atomic)

        let md = Self.markdown(for: t)
        try md.write(to: markdownURL(for: t), atomically: true, encoding: .utf8)

        if latestUnlocked()?.id == t.id {
            try? md.write(to: root.appendingPathComponent("dernier.md"), atomically: true, encoding: .utf8)
        }
        try? rebuildIndexUnlocked()
    }

    /// Renomme un interlocuteur dans tout le transcript (« Interlocuteur 1 » → « Victor »).
    @discardableResult
    public func renameSpeaker(id: String, from old: String, to new: String) throws -> Transcript? {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old, var t = load(id: id) else { return nil }
        for index in t.segments.indices where t.segments[index].speaker == old {
            t.segments[index].speaker = name
        }
        t.speakers = TranscriptBuilder.speakers(in: t.segments)
        t.text = TranscriptBuilder.text(for: t.segments)
        try save(t)
        return t
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let t = loadUnlocked(id: id) else { return }
        var urls = [jsonURL(for: t), markdownURL(for: t)]
        urls.append(contentsOf: audioURLs(for: t))
        for url in urls where fm.fileExists(atPath: url.path) {
            try fm.trashItem(at: url, resultingItemURL: nil)
        }
        if let latest = latestUnlocked() {
            try? Self.markdown(for: latest)
                .write(to: root.appendingPathComponent("dernier.md"), atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(at: root.appendingPathComponent("dernier.md"))
        }
        try? rebuildIndexUnlocked()
    }

    /// Crée le dossier de la bibliothèque et son mode d'emploi, s'ils n'existent pas encore.
    public func prepare() {
        lock.lock()
        defer { lock.unlock() }
        try? ensureRoot()
    }

    private func ensureRoot() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("LISEZMOI.md")
        if !fm.fileExists(atPath: readme.path) {
            try Self.readme.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Lecture

    /// Tous les fichiers JSON de transcripts, du plus récent au plus ancien.
    private func allJSONFiles() -> [URL] {
        guard let months = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var files: [URL] = []
        for month in months where month.count == 7 && month.dropFirst(4).first == "-" {
            let dir = root.appendingPathComponent(month, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".json") {
                files.append(dir.appendingPathComponent(name))
            }
        }
        return files.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func decode(_ url: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: data)
    }

    private func loadUnlocked(id: String) -> Transcript? {
        existingJSON(forID: id).flatMap(decode)
    }

    private func latestUnlocked() -> Transcript? {
        allJSONFiles().lazy.compactMap(self.decode).first
    }

    public func load(id: String) -> Transcript? {
        loadUnlocked(id: id)
    }

    public func list(limit: Int? = nil, mode: RecordingMode? = nil) -> [Transcript] {
        var out: [Transcript] = []
        for url in allJSONFiles() {
            if let mode, !url.lastPathComponent.hasSuffix("_\(mode.slug).json") { continue }
            guard let t = decode(url) else { continue }
            out.append(t)
            if let limit, out.count >= limit { break }
        }
        return out
    }

    public func latest(mode: RecordingMode? = nil) -> Transcript? {
        list(limit: 1, mode: mode).first
    }

    /// Recherche plein texte, insensible à la casse et aux accents ; tous les mots doivent apparaître.
    public func search(_ query: String, limit: Int = 20) -> [Transcript] {
        let terms = Self.fold(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var out: [Transcript] = []
        for url in allJSONFiles() {
            guard let t = decode(url) else { continue }
            let haystack = Self.fold(t.text + " " + t.speakers.joined(separator: " "))
            if terms.allSatisfy({ haystack.contains($0) }) {
                out.append(t)
                if out.count >= limit { break }
            }
        }
        return out
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    // MARK: - Index

    private func rebuildIndexUnlocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var lines: [String] = []
        for url in allJSONFiles().reversed() {
            guard let t = decode(url) else { continue }
            let entry = IndexEntry(
                id: t.id,
                date: Self.isoFormatter.string(from: t.createdAt),
                mode: t.mode.slug,
                appareil: t.device,
                duree_s: Int(t.duration.rounded()),
                interlocuteurs: t.speakers,
                fichier: "\(String(t.id.prefix(7)))/\(t.id)_\(t.mode.slug).md",
                titre: t.title,
                apercu: t.preview
            )
            if let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        try (lines.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("index.jsonl"), atomically: true, encoding: .utf8)
    }

    private struct IndexEntry: Codable {
        var id: String
        var date: String
        var mode: String
        var appareil: String
        var duree_s: Int
        var interlocuteurs: [String]
        var fichier: String
        var titre: String?
        var apercu: String
    }

    // MARK: - Entretien

    /// Supprime l'audio des transcriptions plus anciennes que `cutoff` (le texte reste).
    /// - Returns: le nombre de transcriptions allégées.
    @discardableResult
    public func dropAudio(olderThan cutoff: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var count = 0
        for url in allJSONFiles() {
            guard var t = decode(url), !t.audioFiles.isEmpty, t.createdAt < cutoff else { continue }
            for audio in audioURLs(for: t) { try? fm.removeItem(at: audio) }
            t.audioFiles = []
            guard let json = try? jsonEncoder.encode(t) else { continue }
            try? json.write(to: jsonURL(for: t), options: .atomic)
            try? Self.markdown(for: t).write(to: markdownURL(for: t), atomically: true, encoding: .utf8)
            count += 1
        }
        if count > 0 { try? rebuildIndexUnlocked() }
        return count
    }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Rendu Markdown

    /// « Point lancement », ou à défaut « Réunion du 2 oct. 2026 à 11:30 ».
    public static func title(for t: Transcript) -> String {
        if let title = t.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return dateTitle(for: t)
    }

    public static func dateTitle(for t: Transcript) -> String {
        let date = titleFormatter.string(from: t.createdAt)
        return L10n.current == .french ? "\(t.mode.label) du \(date)" : "\(t.mode.label), \(date)"
    }

    public static func markdown(for t: Transcript) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(t.id)")
        lines.append("date: \(isoFormatter.string(from: t.createdAt))")
        lines.append("mode: \(t.mode.slug)")
        lines.append("appareil: \(t.device)")
        lines.append("duree: \(Format.duration(t.duration))")
        if !t.speakers.isEmpty {
            lines.append("interlocuteurs: [\(t.speakers.joined(separator: ", "))]")
        }
        if let app = t.app { lines.append("application: \(app)") }
        lines.append("moteur: \(t.engine)")
        if !t.audioFiles.isEmpty {
            lines.append("audio: [\(t.audioFiles.joined(separator: ", "))]")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(title(for: t))")
        if t.title != nil { lines.append("\(dateTitle(for: t))") }
        lines.append("")
        if let summary = t.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("## " + tr("Résumé"))
            lines.append("")
            lines.append(summary)
            lines.append("")
            lines.append("## " + tr("Transcription"))
            lines.append("")
        }
        lines.append(body(for: t))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Corps du transcript : texte simple, ou dialogue horodaté s'il y a plusieurs tours de parole.
    public static func body(for t: Transcript) -> String {
        guard t.mode != .dictation, t.speakers.count > 1 else { return t.text }
        return dialogue(t.segments)
    }

    public static func dialogue(_ segments: [Segment]) -> String {
        segments
            .map { "**\($0.speaker)** [\(Format.clock($0.start))] : \($0.text)" }
            .joined(separator: "\n\n")
    }

    static let readme = """
        # Plume — bibliothèque de transcriptions

        Ce dossier contient toutes les transcriptions vocales produites par Plume
        (dictées, réunions, imports). Tout est en texte brut, pensé pour être lu
        directement par une IA ou par un humain.

        - `dernier.md` : la transcription la plus récente.
        - `index.jsonl` : une ligne JSON par transcription (id, date, mode, durée,
          interlocuteurs, chemin du fichier, aperçu), de la plus ancienne à la plus récente.
        - `AAAA-MM/<id>_<mode>.md` : le texte, avec un en-tête (date, mode, durée,
          interlocuteurs). Modes : `dictee`, `reunion`, `import`.
        - `AAAA-MM/<id>_<mode>.json` : les données complètes (segments horodatés
          par interlocuteur, texte brut avant nettoyage).
        - `AAAA-MM/<id>_*.m4a` : l'audio d'origine (`mic` = micro, `sys` = son de l'ordinateur).

        Pour une réunion, chaque tour de parole est écrit ainsi :
        `**Interlocuteur** [mm:ss] : texte`. « Moi » désigne le propriétaire de l'appareil.

        En ligne de commande : `plume last`, `plume list`, `plume search <mots>`,
        `plume show <id>`.

        """
}
