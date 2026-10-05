import Foundation

/// Tampon d'échantillons mono 16 kHz, alimenté par le thread audio et lu par la transcription.
public final class SampleBuffer: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    public init() {
        storage.reserveCapacity(SpeechEngine.sampleRate * 120)
    }

    public func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    public var duration: Double { Double(count) / Double(SpeechEngine.sampleRate) }

    public func slice(_ range: Range<Int>) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let lower = max(0, min(range.lowerBound, storage.count))
        let upper = max(lower, min(range.upperBound, storage.count))
        return Array(storage[lower..<upper])
    }

    public func all() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public enum AudioLevel {
    /// Niveau RMS d'un bloc d'échantillons.
    public static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Vrai si aucune trame de 100 ms ne dépasse le seuil de parole.
    public static func isSilent(_ samples: [Float], threshold: Float = 0.006) -> Bool {
        firstActiveFrame(samples, threshold: threshold) == nil
    }

    /// Indice du premier échantillon d'une trame de 100 ms au-dessus du seuil.
    public static func firstActiveFrame(_ samples: [Float], threshold: Float = 0.006) -> Int? {
        let frame = SpeechEngine.sampleRate / 10
        var i = 0
        while i < samples.count {
            let end = min(i + frame, samples.count)
            if rms(samples[i..<end]) > threshold { return i }
            i = end
        }
        return nil
    }
}

/// Transcription en direct par fenêtre glissante.
///
/// À chaque passe, on retranscrit tout ce qui n'est pas encore « validé » (au plus ~13 s).
/// Dès que la fenêtre contient une pause nette, le texte qui la précède est validé et ne
/// bougera plus ; le reste est « volatil » et peut encore être corrigé à la passe suivante.
public actor LiveTranscriber {
    public struct State: Sendable, Equatable {
        /// Texte validé, stable.
        public var committed: String
        /// Texte de la fenêtre en cours, susceptible de changer.
        public var volatile: String

        public var full: String {
            [committed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private let engine: SpeechEngine
    private let buffer: SampleBuffer
    private let sampleRate = Double(SpeechEngine.sampleRate)

    private var committedSample = 0
    private var committedText = ""
    private var volatileText = ""
    private var processedCount = 0

    /// Durée maximale d'audio non validé envoyée au modèle (son entrée native fait 15 s).
    private let maxWindow: Double
    /// Audio déjà validé rejoué avant la fenêtre, pour que le modèle garde le fil de la phrase.
    private let leftContext = 2.0
    /// Durée à partir de laquelle on cherche une pause où valider.
    private let commitAfter: Double
    /// Fin de fenêtre laissée volatile : le modèle manque de contexte sur les derniers mots.
    private let tailKeep = 1.2

    /// - Parameter eager: fenêtres plus courtes, validées plus tôt : chaque passe coûte moins
    ///   et le texte arrive plus vite, au prix d'un peu de contexte (écriture au fil de la dictée).
    public init(engine: SpeechEngine, buffer: SampleBuffer, eager: Bool = false) {
        self.engine = engine
        self.buffer = buffer
        maxWindow = eager ? 9 : 12
        commitAfter = eager ? 2.2 : 3.5
    }

    public var state: State { State(committed: committedText, volatile: volatileText) }

    /// Une passe de transcription. Renvoie `nil` si rien de nouveau n'a été capté.
    public func tick() async -> State? {
        let total = buffer.count
        guard total - processedCount >= Int(0.3 * sampleRate) else { return nil }
        processedCount = total

        let end = min(total, committedSample + Int(maxWindow * sampleRate))
        guard end > committedSample else { return nil }
        let truncated = end < total
        let fresh = buffer.slice(committedSample..<end)

        // Rien de parlé depuis la dernière validation : on avance en gardant une demi-seconde.
        guard let firstActive = AudioLevel.firstActiveFrame(fresh) else {
            committedSample = max(committedSample, end - Int(0.5 * sampleRate))
            volatileText = ""
            return state
        }
        // On saute le silence initial pour ne pas le retranscrire à chaque passe.
        committedSample += max(0, firstActive - Int(0.3 * sampleRate))

        let contextSamples = min(Int(leftContext * sampleRate), committedSample)
        let windowStart = committedSample - contextSamples
        let window = buffer.slice(windowStart..<end)
        guard let output = try? await engine.transcribe(window) else { return state }

        // Les mots du contexte sont déjà validés : on ne garde que ce qui suit.
        let contextDuration = Double(contextSamples) / sampleRate
        let words = output.words.filter { ($0.start + $0.end) / 2 >= contextDuration }
        let windowDuration = Double(window.count) / sampleRate
        let freshDuration = windowDuration - contextDuration

        guard !words.isEmpty else {
            volatileText = ""
            if freshDuration > commitAfter {
                committedSample = end - Int(1.0 * sampleRate)
            }
            return state
        }

        if freshDuration >= commitAfter || truncated,
            let cut = commitIndex(
                words: words, windowDuration: windowDuration, freshDuration: freshDuration, force: truncated)
        {
            let head = words[..<cut].map(\.text).joined(separator: " ")
            committedText = [committedText, head].filter { !$0.isEmpty }.joined(separator: " ")
            let next = cut < words.count ? words[cut].start : min(windowDuration, words[cut - 1].end + 0.6)
            let cutTime = (words[cut - 1].end + next) / 2
            committedSample = windowStart + Int(cutTime * sampleRate)
            volatileText = words[cut...].map(\.text).joined(separator: " ")
        } else {
            volatileText = words.map(\.text).joined(separator: " ")
        }
        return state
    }

    /// Fin d'enregistrement : tout ce qui reste est transcrit et validé d'un coup.
    public func finish() async -> State {
        let total = buffer.count
        guard total > committedSample else {
            volatileText = ""
            return state
        }
        let contextSamples = min(Int(leftContext * sampleRate), committedSample)
        let windowStart = committedSample - contextSamples
        let window = buffer.slice(windowStart..<total)
        volatileText = ""
        guard !AudioLevel.isSilent(Array(window)), let output = try? await engine.transcribe(window) else { return state }
        let contextDuration = Double(contextSamples) / sampleRate
        let words = output.words.filter { ($0.start + $0.end) / 2 >= contextDuration }
        let tail = words.map(\.text).joined(separator: " ")
        committedText = [committedText, tail].filter { !$0.isEmpty }.joined(separator: " ")
        committedSample = total
        processedCount = total
        return state
    }

    /// Nombre de mots à valider, ou `nil` si aucune coupe propre n'existe encore.
    ///
    /// On coupe de préférence à une fin de phrase ou à une vraie pause : couper au milieu
    /// d'une phrase prive la fenêtre suivante de son contexte et dégrade la reconnaissance.
    private func commitIndex(words: [Word], windowDuration: Double, freshDuration: Double, force: Bool) -> Int? {
        let limit = force ? windowDuration : windowDuration - tailKeep
        var strong: Int?
        var weak: Int?
        var widest: (index: Int, gap: Double)?
        for i in 1..<max(1, words.count) {
            let previous = words[i - 1]
            guard previous.end <= limit else { break }
            let gap = words[i].start - previous.end
            let endsSentence = previous.text.last.map { ".?!…".contains($0) } ?? false
            if (endsSentence && gap >= 0.2) || gap >= 0.7 { strong = i }
            if gap >= 0.3 { weak = i }
            if gap > (widest?.gap ?? -1) { widest = (i, gap) }
        }
        // Silence après le dernier mot : tout ce qui a été dit peut être validé.
        if let last = words.last, windowDuration - last.end >= 0.9 { return words.count }
        if let strong { return strong }
        // Parole continue : à l'approche de la saturation, on se contente d'une respiration.
        if force || freshDuration >= maxWindow - 3 {
            return weak ?? widest?.index
        }
        return nil
    }
}
