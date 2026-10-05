import Foundation

/// Le journal des modifications (`CHANGELOG.md`), lu pour la fenêtre « Nouveautés ».
///
///     ## 1.0.0 — 2026-10-05
///     ### 2026-10-05
///     - Historique : les enregistrements annulés restent récupérables (#7)
public enum Changelog {
    public struct Entry: Sendable, Equatable, Hashable {
        public var date: String?
        /// « Historique », « Collage »… : ce qui est touché.
        public var domain: String?
        public var text: String
        /// Numéro de la pull request, le cas échéant.
        public var pullRequest: Int?
    }

    public struct Release: Sendable, Equatable, Identifiable {
        public var version: String
        /// Date de publication ; `nil` tant que la version n'est pas publiée.
        public var date: String?
        public var entries: [Entry]
        public var id: String { version }
    }

    public static func parse(_ markdown: String) -> [Release] {
        var releases: [Release] = []
        /// Date du `### <date>` en cours, qui vaut pour les lignes qui suivent.
        var day: String?
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                day = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("## ") {
                day = nil
                let title = String(line.dropFirst(3))
                let parts = title.components(separatedBy: " — ")
                releases.append(
                    Release(
                        version: parts[0].trimmingCharacters(in: .whitespaces),
                        date: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil, entries: []))
            } else if line.hasPrefix("- "), !releases.isEmpty {
                var item = entry(String(line.dropFirst(2)))
                if item.date == nil { item.date = day }
                releases[releases.count - 1].entries.append(item)
            }
        }
        return releases.filter { !$0.entries.isEmpty }
    }

    static func entry(_ line: String) -> Entry {
        var rest = line
        var date: String?
        if let range = rest.range(of: " — "), isDate(rest[..<range.lowerBound]) {
            date = String(rest[..<range.lowerBound])
            rest = String(rest[range.upperBound...])
        }
        var pullRequest: Int?
        if let match = rest.range(of: #"\s*\(#(\d+)\)$"#, options: .regularExpression) {
            pullRequest = Int(rest[match].filter(\.isNumber))
            rest.removeSubrange(match)
        }
        var domain: String?
        if let colon = rest.range(of: " : ") {
            domain = String(rest[..<colon.lowerBound])
            rest = String(rest[colon.upperBound...])
        }
        let text = rest.prefix(1).uppercased() + rest.dropFirst()
        return Entry(date: date, domain: domain, text: text, pullRequest: pullRequest)
    }

    private static func isDate(_ text: Substring) -> Bool {
        text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// Empreinte de la dernière entrée : quand elle change, il y a du nouveau à montrer.
    public static func signature(of releases: [Release]) -> String {
        guard let release = releases.first, let entry = release.entries.first else { return "" }
        return release.version + "|" + entry.text
    }
}
