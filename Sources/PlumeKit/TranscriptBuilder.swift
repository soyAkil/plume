import Foundation

/// Assemble les mots horodatés et la diarisation en tours de parole lisibles.
public enum TranscriptBuilder {
    /// Pause au-delà de laquelle un même locuteur ouvre un nouveau paragraphe.
    public static let paragraphGap = 2.5

    /// Le propriétaire de l'appareil : « Moi », ou « Me » en anglais.
    public static var meName: String { tr("Moi") }

    /// « Interlocuteur 1 », ou « Speaker 1 ».
    public static func speakerName(_ index: Int) -> String { "\(tr("Interlocuteur")) \(index)" }

    /// Reconnaît le propriétaire quelle que soit la langue dans laquelle il a été nommé.
    public static func isMe(_ speaker: String) -> Bool { speaker == "Moi" || speaker == "Me" }

    /// Attribue chaque mot à un locuteur puis regroupe en tours de parole.
    /// - Parameters:
    ///   - words: mots horodatés d'un canal.
    ///   - turns: résultat de la diarisation de ce canal (vide = locuteur unique).
    ///   - names: nom affiché pour chaque identifiant de locuteur.
    ///   - fallback: nom utilisé sans diarisation.
    public static func segments(
        words: [Word], turns: [SpeakerTurn], names: [String: String], fallback: String, channel: AudioChannel
    ) -> [Segment] {
        guard !words.isEmpty else { return [] }
        var labels = words.map { word -> String in
            guard let id = speaker(at: (word.start + word.end) / 2, in: turns) else { return fallback }
            return names[id] ?? fallback
        }
        smooth(&labels, words: words)

        var out: [Segment] = []
        var current: (speaker: String, start: Double, end: Double, texts: [String])?
        func flush() {
            guard let c = current else { return }
            out.append(
                Segment(
                    id: out.count, speaker: c.speaker, channel: channel, start: c.start, end: c.end,
                    text: c.texts.joined(separator: " ")))
        }
        for (word, label) in zip(words, labels) {
            if let c = current, c.speaker == label, word.start - c.end < paragraphGap {
                current = (c.speaker, c.start, word.end, c.texts + [word.text])
            } else {
                flush()
                current = (label, word.start, word.end, [word.text])
            }
        }
        flush()
        return out
    }

    /// Locuteur actif à l'instant `t` : le tour qui le contient, sinon le plus proche dans le temps.
    public static func speaker(at t: Double, in turns: [SpeakerTurn]) -> String? {
        var nearest: (id: String, distance: Double)?
        for turn in turns {
            if t >= turn.start && t <= turn.end { return turn.speaker }
            let distance = t < turn.start ? turn.start - t : t - turn.end
            if distance < (nearest?.distance ?? .infinity) {
                nearest = (turn.speaker, distance)
            }
        }
        return nearest?.id
    }

    /// Un ou deux mots isolés attribués à quelqu'un d'autre au milieu d'une phrase sont
    /// presque toujours une erreur de frontière : on les rend au locuteur environnant.
    static func smooth(_ labels: inout [String], words: [Word]) {
        guard labels.count >= 3 else { return }
        var i = 1
        while i < labels.count - 1 {
            var j = i
            while j < labels.count - 1, labels[j] == labels[i] { j += 1 }
            let runLength = j - i
            let before = labels[i - 1]
            if labels[i] != before, runLength <= 2, labels[j] == before {
                let endsSentenceBefore = words[i - 1].text.last.map { ".?!…".contains($0) } ?? false
                let endsSentenceInside = words[j - 1].text.last.map { ".?!…".contains($0) } ?? false
                if !endsSentenceBefore && !endsSentenceInside {
                    for k in i..<j { labels[k] = before }
                }
            }
            i = max(j, i + 1)
        }
    }

    /// Recale chaque changement de locuteur sur une coupure naturelle de la parole.
    ///
    /// La diarisation situe les changements de voix à quelques dixièmes de seconde près, ce qui
    /// laisse souvent un ou deux mots du mauvais côté (« il y | a tellement de… »). Autour de
    /// chaque changement, on cherche donc la vraie frontière : une pause, ou une fin de phrase.
    static func snap(_ labels: inout [String], words: [Word], reach: Int = 4) {
        guard labels.count >= 2 else { return }
        /// Qualité d'une frontière placée juste avant le mot `index` : une pause, une fin de phrase.
        func quality(_ index: Int) -> Double {
            let previous = words[index - 1]
            var score = min(max(0, words[index].start - previous.end), 1.0)
            if let last = previous.text.last {
                if ".?!…".contains(last) { score += 0.6 } else if ",;:".contains(last) { score += 0.15 }
            }
            return score
        }
        /// Écart, en secondes, entre l'instant `moment` et la coupure située avant le mot `index`.
        func distance(_ index: Int, from moment: Double) -> Double {
            let start = words[index - 1].end
            let end = words[index].start
            if moment < start { return start - moment }
            if moment > end { return moment - end }
            return 0
        }
        var index = 1
        while index < labels.count {
            guard labels[index] != labels[index - 1] else {
                index += 1
                continue
            }
            let left = labels[index - 1]
            let right = labels[index]
            // Positions possibles pour la frontière : tant qu'on reste dans la prise de parole
            // de gauche (en reculant) ou de droite (en avançant), à quelques mots au plus.
            var candidates: [Int] = []
            var back = index - 1
            while back >= 1, index - back <= reach, labels[back] == left {
                candidates.append(back)
                back -= 1
            }
            var forward = index + 1
            while forward < labels.count, forward - index <= reach, labels[forward - 1] == right {
                candidates.append(forward)
                forward += 1
            }

            // La diarisation se trompe rarement de plus d'une demi-seconde : une coupure
            // éloignée de l'instant qu'elle indique doit être nettement meilleure pour l'emporter.
            let moment = (words[index - 1].end + words[index].start) / 2
            var best = index
            var bestScore = quality(index)
            for candidate in candidates {
                // Le dernier mot avant une pause « dure » longtemps dans les horodatages : on
                // plafonne l'écart à trois dixièmes de seconde par mot enjambé.
                let away = min(distance(candidate, from: moment), 0.3 * Double(abs(candidate - index)))
                guard away <= 2 else { continue }
                let score = quality(candidate) - 1.2 * away
                if score > bestScore + 0.12 {
                    best = candidate
                    bestScore = score
                }
            }
            if best < index {
                for k in best..<index { labels[k] = right }
            } else if best > index {
                for k in index..<best { labels[k] = left }
            }
            index = max(best, index) + 1
        }
    }

    /// Noms d'affichage dans l'ordre de première prise de parole : « Interlocuteur 1 », « 2 »…
    public static func names(for turns: [SpeakerTurn], startingAt first: Int = 1, me: String? = nil) -> [String: String] {
        var names: [String: String] = [:]
        var next = first
        for turn in turns where names[turn.speaker] == nil {
            if turn.speaker == me {
                names[turn.speaker] = meName
            } else {
                names[turn.speaker] = speakerName(next)
                next += 1
            }
        }
        return names
    }

    /// Fusionne plusieurs canaux en un seul fil chronologique.
    public static func merge(_ channels: [[Segment]]) -> [Segment] {
        let sorted = channels.flatMap { $0 }.sorted { $0.start < $1.start }
        return sorted.enumerated().map { index, segment in
            var s = segment
            s.id = index
            return s
        }
    }

    /// Suite de mots d'un même locuteur sur un canal, avant mise en forme.
    public struct Run: Sendable, Equatable {
        public var speaker: String
        public var channel: AudioChannel
        public var words: [Word]

        public var start: Double { words.first?.start ?? 0 }
        public var end: Double { words.last?.end ?? 0 }
        public var text: String { words.map(\.text).joined(separator: " ") }

        public init(speaker: String, channel: AudioChannel, words: [Word]) {
            self.speaker = speaker
            self.channel = channel
            self.words = words
        }
    }

    /// Attribue chaque mot d'un canal à un locuteur et regroupe les mots consécutifs.
    /// - Parameter label: nom à donner à un identifiant de locuteur de la diarisation
    ///   (`nil` quand aucun tour n'a été détecté).
    public static func runs(
        words: [Word], turns: [SpeakerTurn], channel: AudioChannel, gap: Double = paragraphGap,
        label: (String?) -> String
    ) -> [Run] {
        guard !words.isEmpty else { return [] }
        var labels = words.map { label(speaker(at: ($0.start + $0.end) / 2, in: turns)) }
        smooth(&labels, words: words)
        snap(&labels, words: words)
        var runs: [Run] = []
        for (word, speaker) in zip(words, labels) {
            if let last = runs.last, last.speaker == speaker, word.start - last.end < gap {
                runs[runs.count - 1].words.append(word)
            } else {
                runs.append(Run(speaker: speaker, channel: channel, words: [word]))
            }
        }
        return runs
    }

    private static func endsSentence(_ word: Word) -> Bool {
        word.text.last.map { ".?!…".contains($0) } ?? false
    }

    /// Entremêle les prises de parole de tous les canaux dans l'ordre où elles ont eu lieu.
    ///
    /// Quand quelqu'un intervient au milieu du long tour d'un autre, ce tour est coupé à la fin
    /// de la phrase la plus proche : l'intervention apparaît à sa place dans la conversation
    /// au lieu d'être repoussée après le monologue.
    public static func interleave(_ runs: [Run], gap: Double = paragraphGap) -> [Run] {
        // Chaque morceau porte l'instant qui fixe sa place dans le fil : son début, ou, pour la
        // suite d'un tour coupé, l'instant de l'intervention qui l'a coupé (la suite vient après).
        var keyed: [(key: Double, run: Run)] = []
        for run in runs {
            // Instants où un autre locuteur prend la parole pendant ce tour.
            let interruptions = runs
                .filter { $0.speaker != run.speaker && $0.start > run.start + 0.5 && $0.start < run.end - 0.5 }
                .map(\.start)
                .sorted()
            var remaining = run.words
            var key = run.start
            for moment in interruptions {
                guard let cut = splitIndex(in: remaining, near: moment) else { continue }
                keyed.append((key, Run(speaker: run.speaker, channel: run.channel, words: Array(remaining[..<cut]))))
                remaining = Array(remaining[cut...])
                key = max(remaining.first?.start ?? moment, moment + 0.001)
            }
            if !remaining.isEmpty {
                keyed.append((key, Run(speaker: run.speaker, channel: run.channel, words: remaining)))
            }
        }
        let pieces = keyed.sorted { $0.key < $1.key }.map(\.run)

        // Deux morceaux consécutifs du même locuteur, sans personne entre eux, se recollent.
        var merged: [Run] = []
        for piece in pieces {
            if let last = merged.last, last.speaker == piece.speaker, piece.start - last.end < gap {
                merged[merged.count - 1].words.append(contentsOf: piece.words)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// Indice où couper `words` pour laisser passer une intervention à l'instant `moment` :
    /// la fin de phrase la plus proche, à défaut la pause la plus proche.
    static func splitIndex(in words: [Word], near moment: Double) -> Int? {
        guard words.count >= 4 else { return nil }
        var best: (index: Int, score: Double)?
        for index in 2...(words.count - 2) {
            let previous = words[index - 1]
            let gap = words[index].start - previous.end
            let sentence = endsSentence(previous)
            guard sentence || gap >= 0.35 else { continue }
            let distance = abs(previous.end - moment)
            guard distance <= 5 else { continue }
            // Une fin de phrase vaut mieux qu'une simple pause, à distance égale.
            let score = distance + (sentence ? 0 : 2.5)
            if score < (best?.score ?? .infinity) { best = (index, score) }
        }
        return best?.index
    }

    /// Convertit les prises de parole en segments, en nommant les locuteurs dans l'ordre où
    /// ils interviennent : « Interlocuteur 1 », « 2 »… ; `Moi` garde son nom.
    public static func segments(from runs: [Run], me: Set<String> = []) -> [Segment] {
        var names: [String: String] = [:]
        var next = 1
        return runs.enumerated().map { index, run in
            let name: String
            if me.contains(run.speaker) || isMe(run.speaker) {
                name = meName
            } else if let known = names[run.speaker] {
                name = known
            } else {
                name = speakerName(next)
                names[run.speaker] = name
                next += 1
            }
            // Un tour de parole commence par une majuscule, même quand le modèle l'a enchaîné
            // sans ponctuation à la phrase de quelqu'un d'autre.
            var text = run.text
            if let first = text.first, first.isLowercase { text = first.uppercased() + text.dropFirst() }
            return Segment(id: index, speaker: name, channel: run.channel, start: run.start, end: run.end, text: text)
        }
    }

    /// Retire du canal micro ce qui n'est que l'écho du son de l'ordinateur
    /// (réunion sans écouteurs : les haut-parleurs repassent dans le micro).
    ///
    /// Un segment micro n'est un écho que s'il répète, au même moment, les mêmes enchaînements
    /// de mots que le son système. Partager du vocabulaire courant ne suffit pas : une vraie
    /// réponse (« d'accord, je vois ce que tu veux dire ») doit rester.
    public static func removingEcho(mic: [Segment], systemWords: [Word]) -> [Segment] {
        guard !systemWords.isEmpty else { return mic }
        return mic.filter { segment in
            let spoken = tokens(segment.text)
            guard spoken.count >= 4 else { return true }
            let nearby = systemWords
                .filter { $0.end >= segment.start - 1.5 && $0.start <= segment.end + 1.5 }
                .flatMap { tokens($0.text) }
            guard nearby.count >= 3 else { return true }
            let heard = Set(zip(nearby, nearby.dropFirst()).map { "\($0) \($1)" })
            let pairs = zip(spoken, spoken.dropFirst()).map { "\($0) \($1)" }
            let shared = pairs.filter(heard.contains).count
            return Double(shared) / Double(pairs.count) < 0.5
        }
    }

    /// Même filtre, appliqué aux prises de parole du micro avant leur mise en forme.
    public static func removingEcho(mic: [Run], systemWords: [Word]) -> [Run] {
        let kept = Set(
            removingEcho(
                mic: mic.enumerated().map {
                    Segment(id: $0.offset, speaker: $0.element.speaker, channel: .mic, start: $0.element.start, end: $0.element.end, text: $0.element.text)
                }, systemWords: systemWords
            ).map(\.id))
        return mic.enumerated().filter { kept.contains($0.offset) }.map(\.element)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Texte brut d'une conversation : dialogue horodaté s'il y a plusieurs voix, paragraphes sinon.
    public static func text(for segments: [Segment]) -> String {
        if speakers(in: segments).count > 1 {
            return segments
                .map { "\($0.speaker) [\(Format.clock($0.start))] : \($0.text)" }
                .joined(separator: "\n\n")
        }
        return segments.map(\.text).joined(separator: "\n\n")
    }

    public static func speakers(in segments: [Segment]) -> [String] {
        var seen: [String] = []
        for s in segments where !seen.contains(s.speaker) { seen.append(s.speaker) }
        return seen
    }
}

/// Empreinte vocale du propriétaire, apprise au fil des dictées, pour le reconnaître
/// (« Moi ») parmi les interlocuteurs d'une réunion.
public struct Voiceprint: Codable, Sendable {
    public var embedding: [Float]
    public var samples: Int

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denominator = (na * nb).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }

    /// Intègre une nouvelle mesure (moyenne glissante plafonnée pour suivre l'évolution de la voix).
    public mutating func add(_ other: [Float]) {
        guard other.count == embedding.count else { return }
        let weight = Float(min(samples, 30))
        for i in 0..<embedding.count {
            embedding[i] = (embedding[i] * weight + other[i]) / (weight + 1)
        }
        samples += 1
    }

    /// Identifiant du locuteur qui correspond à l'empreinte, s'il y en a un de suffisamment proche.
    public func match(in embeddings: [String: [Float]], threshold: Float = 0.45) -> String? {
        let scored = embeddings.map { ($0.key, Self.cosine(embedding, $0.value)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= threshold else { return nil }
        return best.0
    }
}
