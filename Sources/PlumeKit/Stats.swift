import Foundation

/// Chiffres d'usage calculés à partir de la bibliothèque, pour la page d'accueil.
public struct LibraryStats: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var date: Date
        public var words: Int
        public var id: Date { date }
    }

    public var transcripts = 0
    public var dictations = 0
    public var meetings = 0
    public var words = 0
    /// Durée totale d'audio, en secondes.
    public var duration: Double = 0
    public var wordsThisWeek = 0
    /// Débit moyen en dictée, en mots par minute.
    public var wordsPerMinute = 0
    /// Temps gagné par rapport à la frappe au clavier, en secondes.
    public var timeSaved: Double = 0
    /// Jours consécutifs d'utilisation, aujourd'hui ou hier inclus.
    public var streak = 0
    /// Plus longue série jamais atteinte.
    public var bestStreak = 0
    /// Mots dictés aujourd'hui.
    public var wordsToday = 0
    /// Meilleure journée : le plus de mots dictés en un jour.
    public var bestDay: Day?
    /// Mots par jour sur les derniers jours, du plus ancien au plus récent.
    public var days: [Day] = []

    /// Vitesse de frappe de référence pour estimer le temps gagné.
    public static let typingWordsPerMinute = 40.0

    public init() {}

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }

    public init(transcripts list: [Transcript], now: Date = Date(), dayCount: Int = 371, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var perDay: [Date: Int] = [:]
        var dictatedWords = 0
        var dictatedSeconds = 0.0

        for t in list {
            // Pour une réunion, seul ce que le propriétaire a dit compte comme « dicté ».
            let spoken: Int
            if t.speakers.count > 1 {
                spoken = t.segments.filter { TranscriptBuilder.isMe($0.speaker) }.reduce(0) { $0 + Self.wordCount($1.text) }
            } else {
                spoken = Self.wordCount(t.text)
            }
            transcripts += 1
            if t.mode == .dictation { dictations += 1 }
            if t.mode == .meeting { meetings += 1 }
            words += spoken
            duration += t.duration
            let day = calendar.startOfDay(for: t.createdAt)
            perDay[day, default: 0] += spoken
            if day >= weekStart { wordsThisWeek += spoken }
            if t.mode == .dictation {
                dictatedWords += spoken
                dictatedSeconds += t.duration
            }
        }

        if dictatedSeconds > 0 {
            wordsPerMinute = Int((Double(dictatedWords) / (dictatedSeconds / 60)).rounded())
        }
        timeSaved = max(0, Double(dictatedWords) / Self.typingWordsPerMinute * 60 - dictatedSeconds)

        days = (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, words: perDay[date] ?? 0)
        }

        wordsToday = perDay[today] ?? 0
        if let best = perDay.max(by: { $0.value < $1.value }), best.value > 0 {
            bestDay = Day(date: best.key, words: best.value)
        }
        // Plus longue suite de jours consécutifs dans tout l'historique.
        var run = 0
        var previous: Date?
        for day in perDay.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            bestStreak = max(bestStreak, run)
            previous = day
        }

        // La série reste vivante si rien n'a encore été dicté aujourd'hui.
        var cursor = today
        if perDay[cursor] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            cursor = yesterday
        }
        while perDay[cursor] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
    }
}
