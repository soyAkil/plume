import Foundation
import PlumeKit

/// Serveur MCP minimal (JSON-RPC 2.0 sur stdio) : donne à une IA un accès en lecture
/// à la bibliothèque de transcriptions.
struct MCPServer {
    let store: TranscriptStore

    func run() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard let response = await handle(message) else { continue }
            if let out = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes]),
                let text = String(data: out, encoding: .utf8)
            {
                CLI.emit(text)
            }
        }
    }

    private func handle(_ message: [String: Any]) async -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        // Les notifications n'ont pas d'identifiant et n'attendent pas de réponse.
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return result(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "plume", "version": "1.0.0"],
                "instructions":
                    "Transcriptions vocales locales de l'utilisateur (dictées, réunions avec interlocuteurs, imports). "
                    + "« Moi » (ou « Me ») désigne l'utilisateur.",
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let text = await call(name, arguments) else {
                return result(id, ["content": [["type": "text", "text": "Outil inconnu : \(name)"]], "isError": true])
            }
            return result(id, ["content": [["type": "text", "text": text]]])
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Méthode inconnue : \(method)"]]
        }
    }

    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private func call(_ name: String, _ args: [String: Any]) async -> String? {
        let mode = (args["mode"] as? String).flatMap(RecordingMode.init(slug:))
        switch name {
        case "get_latest_transcript":
            guard let t = store.latest(mode: mode) else { return "Aucune transcription." }
            return TranscriptStore.markdown(for: t)
        case "get_transcript":
            guard let id = args["id"] as? String, let t = store.load(id: id) else {
                return "Transcription introuvable."
            }
            return TranscriptStore.markdown(for: t)
        case "list_transcripts":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 200)
            return summaries(store.list(limit: limit, mode: mode))
        case "search_transcripts":
            let limit = min(max(args["limit"] as? Int ?? 10, 1), 50)
            return summaries(store.search(args["query"] as? String ?? "", limit: limit))
        case "listen":
            // L'app enregistre, l'utilisateur termine avec son raccourci, le texte revient ici.
            let timeout = min(max(args["timeout"] as? Double ?? 180, 10), 900)
            guard let text = await Listener.listen(store: store, timeout: timeout) else {
                return "Aucune dictée reçue : Plume n'est peut-être pas lancée, ou l'utilisateur n'a rien dit avant le délai."
            }
            return text
        case "summarize_transcript":
            guard let id = args["id"] as? String, var t = store.load(id: id) else { return "Transcription introuvable." }
            do {
                let summary = try await LocalAI.summarize(t)
                t.summary = summary.markdown
                if t.title == nil { t.title = summary.title }
                try store.save(t)
                return "# \(summary.title)\n\n\(summary.markdown)"
            } catch {
                return "Résumé impossible : \(error.localizedDescription)"
            }
        default:
            return nil
        }
    }

    private func summaries(_ items: [Transcript]) -> String {
        guard !items.isEmpty else { return "Aucun résultat." }
        return items.map { t in
            let who = t.speakers.isEmpty ? "" : " · \(t.speakers.joined(separator: ", "))"
            return "- \(t.id) · \(t.mode.label) · \(Format.duration(t.duration))\(who)\n  \(t.preview)"
        }.joined(separator: "\n")
    }

    private static let modeProperty: [String: Any] = [
        "type": "string",
        "enum": ["dictee", "reunion", "import"],
        "description": "Filtrer par type : dictée, réunion (plusieurs interlocuteurs) ou fichier importé.",
    ]

    private static let tools: [[String: Any]] = [
        [
            "name": "get_latest_transcript",
            "description":
                "Renvoie la transcription vocale la plus récente de l'utilisateur (texte complet, avec interlocuteurs pour une réunion). À utiliser pour « ma dernière transcription », « ma dernière réunion » (mode=reunion), « ma dernière dictée » (mode=dictee).",
            "inputSchema": ["type": "object", "properties": ["mode": modeProperty]],
        ],
        [
            "name": "list_transcripts",
            "description": "Liste les transcriptions récentes (id, type, durée, interlocuteurs, aperçu), de la plus récente à la plus ancienne.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Nombre maximal de résultats (20 par défaut)."],
                    "mode": modeProperty,
                ],
            ],
        ],
        [
            "name": "get_transcript",
            "description": "Renvoie le texte complet d'une transcription à partir de son id (ex. 2026-10-02_14-31-05).",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "Identifiant de la transcription."]],
                "required": ["id"],
            ],
        ],
        [
            "name": "search_transcripts",
            "description": "Recherche plein texte dans toutes les transcriptions (insensible à la casse et aux accents ; tous les mots doivent apparaître).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Mots à chercher."],
                    "limit": ["type": "integer", "description": "Nombre maximal de résultats (10 par défaut)."],
                ],
                "required": ["query"],
            ],
        ],
        [
            "name": "listen",
            "description":
                "Fait parler l'utilisateur : Plume ouvre le micro, l'utilisateur dicte sa réponse puis termine avec son raccourci (ou plume stop), et le texte transcrit est renvoyé. À utiliser pour poser une question à l'utilisateur et recevoir sa réponse à la voix, ou quand il demande à répondre à l'oral. Bloque jusqu'à la fin de la dictée (délai maximal : timeout).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "timeout": ["type": "number", "description": "Délai maximal d'attente, en secondes (180 par défaut)."]
                ],
            ],
        ],
        [
            "name": "summarize_transcript",
            "description": "Résume une réunion avec l'IA locale du Mac (points clés, décisions, actions) et range le résumé dans la transcription.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "Identifiant de la transcription."]],
                "required": ["id"],
            ],
        ],
    ]
}
