import AudioToolbox
import Foundation
import Testing

@testable import PlumeKit

@Suite("Dictation cleanup")
struct TextCleanupTests {
    @Test func removesStutteredFunctionWords() {
        #expect(TextCleanup.clean("et sur mon mon laptop") == "Et sur mon laptop")
        #expect(TextCleanup.clean("c'est c'est toujours le même") == "C'est toujours le même")
        #expect(TextCleanup.clean("sinon pas pas nécessaire") == "Sinon pas nécessaire")
    }

    @Test func removesRepeatedGroups() {
        #expect(TextCleanup.clean("ça le ça le ça le marque") == "Ça le marque")
        #expect(TextCleanup.clean("que quand que quand c'est bon") == "Que quand c'est bon")
        #expect(TextCleanup.clean("tout ça c'est tout ça c'est fait") == "Tout ça c'est fait")
    }

    @Test func keepsLegitimateRepetitions() {
        #expect(TextCleanup.clean("Nous nous sommes vus hier.") == "Nous nous sommes vus hier.")
        #expect(TextCleanup.clean("C'est très très bien.") == "C'est très très bien.")
        #expect(TextCleanup.clean("Oui oui, d'accord.") == "Oui oui, d'accord.")
    }

    @Test func doesNotMergeTwoSentences() {
        // Punctuation between the two occurrences signals a real restart.
        #expect(TextCleanup.clean("Je pense à ça. À ça aussi.") == "Je pense à ça. À ça aussi.")
    }

    @Test func removesHesitations() {
        #expect(TextCleanup.clean("Alors euh je voulais dire") == "Alors je voulais dire")
        #expect(TextCleanup.clean("Bon, euh. Voilà.") == "Bon, Voilà.")
        #expect(TextCleanup.clean("euh, bonjour") == "Bonjour")
    }
}

@Suite("Replacements")
struct ReplacementTests {
    let rules = [
        Replacement(original: "super whisper", with: "Superwhisper"),
        Replacement(original: "sitié", with: "CTA"),
    ]

    @Test func matchesWholeWordsCaseInsensitively() {
        #expect(ReplacementStore.apply(rules, to: "J'utilise Super Whisper.") == "J'utilise Superwhisper.")
        #expect(ReplacementStore.apply(rules, to: "Le sitié est rouge") == "Le CTA est rouge")
        #expect(ReplacementStore.apply(rules, to: "la densitié") == "la densitié")
    }

    @Test func ignoresEmptyRules() {
        #expect(ReplacementStore.apply([Replacement(original: " ", with: "x")], to: "a b") == "a b")
    }
}

@Suite("Speaker turns")
struct TranscriptBuilderTests {
    func words(_ items: [(String, Double, Double)]) -> [Word] {
        items.map { Word(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func assignsWordsToSpeakers() {
        L10n.$override.withValue(.french) {
            let w = words([("Bonjour", 0, 0.5), ("Marie.", 0.6, 1.0), ("Salut", 2.0, 2.4), ("Thomas.", 2.5, 3.0)])
            let turns = [SpeakerTurn(speaker: "S1", start: 0, end: 1.2), SpeakerTurn(speaker: "S2", start: 1.8, end: 3.2)]
            let names = TranscriptBuilder.names(for: turns)
            let segments = TranscriptBuilder.segments(words: w, turns: turns, names: names, fallback: "?", channel: .mic)
            #expect(segments.map(\.speaker) == ["Interlocuteur 1", "Interlocuteur 2"])
            #expect(segments.map(\.text) == ["Bonjour Marie.", "Salut Thomas."])
            #expect(segments[1].start == 2.0)
        }
    }

    @Test func givesAnIsolatedWordToTheSurroundingSpeaker() {
        let w = words([("je", 0, 0.2), ("pense", 0.3, 0.6), ("que", 0.7, 0.8), ("oui", 0.9, 1.1), ("vraiment", 1.2, 1.6)])
        var labels = ["A", "A", "B", "A", "A"]
        TranscriptBuilder.smooth(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "A"])
    }

    @Test func keepsAShortReplyAtSentenceEnd() {
        let w = words([("D'accord", 0, 0.4), ("?", 0.4, 0.5), ("Oui.", 1.0, 1.3), ("Parfait", 2.0, 2.5)])
        var labels = ["A", "A", "B", "A"]
        TranscriptBuilder.smooth(&labels, words: [w[0], Word(text: "d'accord ?", start: 0.4, end: 0.5), w[2], w[3]])
        #expect(labels == ["A", "A", "B", "A"])
    }

    @Test func withoutDiarizationEverythingGoesToTheDefaultSpeaker() {
        let w = words([("Un", 0, 0.2), ("test.", 0.3, 0.6)])
        let segments = TranscriptBuilder.segments(words: w, turns: [], names: [:], fallback: "Moi", channel: .mic)
        #expect(segments.count == 1)
        #expect(segments[0].speaker == "Moi")
    }

    @Test func startsAParagraphAfterALongPause() {
        let w = words([("Premier.", 0, 0.5), ("Second.", 5.0, 5.5)])
        let segments = TranscriptBuilder.segments(words: w, turns: [], names: [:], fallback: "Moi", channel: .mic)
        #expect(segments.count == 2)
    }

    /// System-audio words spread evenly from `start`.
    func spread(_ text: String, from start: Double, step: Double = 0.4) -> [Word] {
        text.split(separator: " ").enumerated().map { index, word in
            Word(text: String(word), start: start + Double(index) * step, end: start + Double(index) * step + 0.3)
        }
    }

    @Test func removesSystemAudioEchoFromTheMic() {
        let system = spread("On se retrouve demain à dix heures au bureau.", from: 10)
        let mic = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 10.2, end: 14.1, text: "on se retrouve demain à dix heures au bureau"),
            Segment(id: 1, speaker: "Moi", channel: .mic, start: 15, end: 17, text: "Très bien, je note ça tout de suite."),
        ]
        let kept = TranscriptBuilder.removingEcho(mic: mic, systemWords: system)
        #expect(kept.map(\.id) == [1])
    }

    @Test func keepsARealReplyDuringALongMonologue() {
        // The other person talks at length with common words; my reply reuses them without repeating it.
        let monologue = "alors oui je vois ce que tu veux dire mais d'accord on en parle maintenant parce que ça me va"
        let system = spread(monologue, from: 0, step: 0.5)
        let mic = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 4, end: 7, text: "D'accord, oui, je vois, tu veux qu'on en parle."),
            Segment(id: 1, speaker: "Moi", channel: .mic, start: 8, end: 9, text: "Oui, ça marche."),
        ]
        let kept = TranscriptBuilder.removingEcho(mic: mic, systemWords: system)
        #expect(kept.map(\.id) == [0, 1])
    }

    @Test func mergesChannelsInChronologicalOrder() {
        let a = [Segment(id: 0, speaker: "Moi", channel: .mic, start: 5, end: 6, text: "b")]
        let b = [Segment(id: 0, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "a")]
        let merged = TranscriptBuilder.merge([a, b])
        #expect(merged.map(\.text) == ["a", "b"])
        #expect(merged.map(\.id) == [0, 1])
    }

    @Test func interleavesAnInterruptionInALongTurn() {
        // The other person talks for 12 s in three sentences; I cut in at 5 s.
        let long = spread("Première phrase assez longue. Deuxième phrase tout aussi longue. Troisième phrase pour finir.", from: 0, step: 1.0)
        let other = TranscriptBuilder.Run(speaker: "sys:S1", channel: .system, words: long)
        let mine = TranscriptBuilder.Run(
            speaker: "mic:S1", channel: .mic, words: words([("Attends,", 5.1, 5.4), ("une", 5.5, 5.6), ("question.", 5.7, 6.2)]))
        let result = TranscriptBuilder.interleave([other, mine])
        #expect(result.map(\.speaker) == ["sys:S1", "mic:S1", "sys:S1"])
        #expect(result[0].text == "Première phrase assez longue.")
        #expect(result[2].text.hasPrefix("Deuxième phrase"))
    }

    @Test func doesNotSplitWithoutInterruption() {
        let long = spread("Une phrase. Puis une autre. Et une dernière.", from: 0, step: 0.5)
        let result = TranscriptBuilder.interleave([TranscriptBuilder.Run(speaker: "a", channel: .system, words: long)])
        #expect(result.count == 1)
    }

    @Test func numbersSpeakersInOrderOfAppearance() {
        L10n.$override.withValue(.french) {
            let runs = [
                TranscriptBuilder.Run(speaker: "sys:S3", channel: .system, words: words([("Bonjour.", 0, 1)])),
                TranscriptBuilder.Run(speaker: "mic:S1", channel: .mic, words: words([("Salut.", 1, 2)])),
                TranscriptBuilder.Run(speaker: "sys:S1", channel: .system, words: words([("Hello.", 2, 3)])),
                TranscriptBuilder.Run(speaker: "sys:S3", channel: .system, words: words([("Bien.", 3, 4)])),
            ]
            let segments = TranscriptBuilder.segments(from: runs, me: ["mic:S1"])
            #expect(segments.map(\.speaker) == ["Interlocuteur 1", "Moi", "Interlocuteur 2", "Interlocuteur 1"])
        }
    }

    @Test func snapsVoiceChangeToThePause() {
        // "… pour performer encore plus | c'est le bouche à oreille": diarization cut one word too early.
        let w = words([
            ("pour", 0.0, 0.2), ("performer", 0.2, 0.7), ("encore", 0.7, 1.0), ("plus", 1.0, 1.2),
            ("c'est", 1.9, 2.1), ("le", 2.1, 2.2), ("bouche", 2.2, 2.5), ("à", 2.5, 2.6), ("oreille", 2.6, 3.0),
        ])
        var labels = ["A", "A", "A", "B", "B", "B", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "B", "B", "B", "B", "B"])
    }

    @Test func snapsVoiceChangeToTheSentenceEnd() {
        // "… à la monnaie. Là on a | sorti quelques leviers": the three words go with what follows.
        let w = words([
            ("à", 0.0, 0.1), ("la", 0.1, 0.2), ("monnaie.", 0.2, 0.7), ("Là", 0.75, 0.9), ("on", 0.9, 1.0),
            ("a", 1.0, 1.1), ("sorti", 1.1, 1.4), ("quelques", 1.4, 1.7), ("leviers", 1.7, 2.1),
        ])
        var labels = ["A", "A", "A", "A", "A", "A", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "B", "B", "B", "B", "B", "B"])
    }

    @Test func leavesAWellPlacedBoundaryAlone() {
        let w = words([("Tu", 0, 0.2), ("viens", 0.2, 0.5), ("demain", 0.5, 0.9), ("?", 0.9, 1.0), ("Oui,", 1.6, 1.8), ("bien", 1.8, 2.0), ("sûr.", 2.0, 2.3)])
        var labels = ["A", "A", "A", "A", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "B", "B", "B"])
    }

    @Test func namesTheRecognizedSpeakerMe() {
        L10n.$override.withValue(.french) {
            let turns = [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)]
            let names = TranscriptBuilder.names(for: turns, startingAt: 3, me: "S2")
            #expect(names == ["S1": "Interlocuteur 3", "S2": "Moi"])
        }
    }
}

@Suite("Voiceprint and voice merging")
struct VoiceTests {
    @Test func recognizesTheClosestVoice() {
        let print = Voiceprint(embedding: [1, 0, 0], samples: 3)
        #expect(print.match(in: ["S1": [0, 1, 0], "S2": [0.9, 0.1, 0]]) == "S2")
        #expect(print.match(in: ["S1": [0, 1, 0]]) == nil)
    }

    @Test func keepsTwoMerelySimilarVoicesApart() {
        // Similarity of about 0.5: two people with close voices, not the same person.
        let output = DiarizationOutput(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)],
            embeddings: ["S1": [1, 0, 0], "S2": [0.5, 0.866, 0]])
        #expect(SpeechEngine.mergingSimilarVoices(output).embeddings.count == 2)
    }

    @Test func removesAPhantomVoice() {
        let output = DiarizationOutput(
            turns: [
                SpeakerTurn(speaker: "S1", start: 0, end: 300), SpeakerTurn(speaker: "S4", start: 300, end: 302),
                SpeakerTurn(speaker: "S2", start: 302, end: 600),
            ],
            embeddings: ["S1": [1, 0], "S2": [0, 1], "S4": [0.7, 0.7]])
        let cleaned = SpeechEngine.removingPhantomVoices(output)
        #expect(cleaned.turns.map(\.speaker) == ["S1", "S2"])
        #expect(cleaned.embeddings["S4"] == nil)
    }

    @Test func mergesTwoNearlyIdenticalVoices() {
        let output = DiarizationOutput(
            turns: [
                SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1.1, end: 2),
                SpeakerTurn(speaker: "S3", start: 3, end: 4),
            ],
            embeddings: ["S1": [1, 0, 0], "S2": [0.9, 0.2, 0], "S3": [0, 0, 1]])
        let merged = SpeechEngine.mergingSimilarVoices(output)
        #expect(Set(merged.embeddings.keys) == ["S1", "S3"])
        #expect(merged.turns.map(\.speaker) == ["S1", "S3"])
        #expect(merged.turns[0].end == 2)
    }

    @Test func leavesTwoDistinctVoicesAlone() {
        let output = DiarizationOutput(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)],
            embeddings: ["S1": [1, 0], "S2": [0.2, 1]])
        #expect(SpeechEngine.mergingSimilarVoices(output).embeddings.count == 2)
    }
}

@Suite("Library")
struct LibraryTests {
    func makeStore() -> TranscriptStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        return TranscriptStore(root: root)
    }

    func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)!
    }

    @Test func savesListsAndSearches() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = date("2026-10-01 09:00:00")
        let second = date("2026-10-02 14:31:05")
        try store.save(
            Transcript(
                id: store.makeID(for: first), createdAt: first, mode: .dictation, duration: 12, engine: "test",
                text: "Rappeler le plombier demain.", rawText: "rappeler le plombier demain"))
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 2, text: "On valide le budget ?"),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 2, end: 4, text: "Oui, validé."),
        ]
        try store.save(
            Transcript(
                id: store.makeID(for: second), createdAt: second, mode: .meeting, duration: 60, engine: "test",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
                speakers: ["Moi", "Interlocuteur 1"]))

        #expect(store.list().map(\.id) == ["2026-10-02_14-31-05", "2026-10-01_09-00-00"])
        #expect(store.latest()?.mode == .meeting)
        #expect(store.latest(mode: .dictation)?.id == "2026-10-01_09-00-00")
        #expect(store.search("PLOMBIER").count == 1)
        #expect(store.search("valide budget").map(\.id) == ["2026-10-02_14-31-05"])
        #expect(store.search("introuvable").isEmpty)

        let latest = try String(contentsOf: store.root.appendingPathComponent("dernier.md"), encoding: .utf8)
        #expect(latest.contains("**Interlocuteur 1** [0:02] : Oui, validé."))
        let index = try String(contentsOf: store.root.appendingPathComponent("index.jsonl"), encoding: .utf8)
        #expect(index.split(separator: "\n").count == 2)
    }

    @Test func twoIDsReservedBeforeWritingAreDistinct() {
        let store = makeStore()
        let moment = date("2026-10-02 12:00:00")
        let ids = (0..<3).map { _ in store.makeID(for: moment) }
        #expect(Set(ids).count == 3)
    }

    @Test func twoIDsInTheSameSecondStayOrdered() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let moment = date("2026-10-02 10:00:00")
        let a = store.makeID(for: moment)
        try store.save(Transcript(id: a, createdAt: moment, mode: .dictation, duration: 1, engine: "t", text: "un", rawText: ""))
        let b = store.makeID(for: moment)
        try store.save(Transcript(id: b, createdAt: moment, mode: .dictation, duration: 1, engine: "t", text: "deux", rawText: ""))
        #expect(a != b)
        #expect(store.list().map(\.text) == ["deux", "un"])
    }

    @Test func renamesASpeaker() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let moment = date("2026-10-02 11:00:00")
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 1, text: "Salut."),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "Salut."),
        ]
        let id = store.makeID(for: moment)
        try store.save(
            Transcript(
                id: id, createdAt: moment, mode: .meeting, duration: 2, engine: "t",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
                speakers: ["Moi", "Interlocuteur 1"]))
        let renamed = try store.renameSpeaker(id: id, from: "Interlocuteur 1", to: "Victor")
        #expect(renamed?.speakers == ["Moi", "Victor"])
        #expect(store.load(id: id)?.text.contains("Victor [0:01] : Salut.") == true)
    }
}

@Suite("Recovery of interrupted recordings")
struct RecoveryTests {
    @Test func findsAudioWithoutTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        let store = TranscriptStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try store.ensureDirectory(forID: "2026-10-02_10-00-00")
        let silence = [Float](repeating: 0, count: 1600)
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_10-00-00_mic.wav"))
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_10-00-00_sys.wav"))
        Recovery.stash(silence, at: try Recovery.dictationURL(id: "2026-10-02_11-00-00", store: store))
        // This one already has its transcript: it must not be recovered.
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_12-00-00_mic.wav"))
        try store.save(
            Transcript(
                id: "2026-10-02_12-00-00", createdAt: Date(), mode: .meeting, duration: 1, engine: "t", text: "x",
                rawText: ""))

        let pending = Recovery.pending(in: store)
        #expect(pending.map(\.id) == ["2026-10-02_10-00-00", "2026-10-02_11-00-00"])
        #expect(pending[0].mode == .meeting)
        #expect(pending[0].system != nil)
        #expect(pending[1].mode == .dictation)
        #expect(Recovery.pending(in: store, excluding: ["2026-10-02_10-00-00"]).count == 1)
        #expect(TranscriptStore.date(fromID: "2026-10-02_10-00-00b") != nil)
    }

    /// 1.0.1 named a dictation's backup `_dictee.wav`: one left by a crash before the
    /// upgrade is still recovered.
    @Test func findsDictationBackupsUnderBothNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        let store = TranscriptStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try store.ensureDirectory(forID: "2026-10-02_10-00-00")
        let silence = [Float](repeating: 0, count: 1600)
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_10-00-00_dictee.wav"))
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_11-00-00_dictation.wav"))

        let pending = Recovery.pending(in: store)
        #expect(pending.map(\.id) == ["2026-10-02_10-00-00", "2026-10-02_11-00-00"])
        #expect(pending.allSatisfy { $0.mode == .dictation })
        #expect(Recovery.isDictationBackup("2026-10-02_10-00-00_dictee.wav"))
        #expect(Recovery.isDictationBackup("2026-10-02_11-00-00_dictation.wav"))
        #expect(!Recovery.isDictationBackup("2026-10-02_11-00-00_mic.wav"))
        #expect(try Recovery.dictationURL(id: "2026-10-02_12-00-00", store: store).lastPathComponent
            == "2026-10-02_12-00-00_dictation.wav")
    }
}

@Suite("Cancelled recordings")
struct CancelledTests {
    /// One second of a 440 Hz A, loud enough not to pass for silence.
    let tone = (0..<16_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000)) * 0.3 }

    @Test func keepsListsAndDeletes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CancelledStore(library: root)
        let now = Date()
        try store.keep(
            CancelledRecording(id: "2026-10-05_10-00-00", createdAt: now, cancelledAt: now.addingTimeInterval(-10), mode: .dictation, duration: 1),
            mic: tone)
        try store.keep(
            CancelledRecording(id: "2026-10-05_11-00-00", createdAt: now, cancelledAt: now, mode: .meeting, duration: 1, app: "Zoom"),
            mic: tone, system: (samples: tone, offset: 0.5))

        let list = store.list()
        #expect(list.map(\.id) == ["2026-10-05_11-00-00", "2026-10-05_10-00-00"])
        #expect(list[0].audioFiles == ["2026-10-05_11-00-00_mic.m4a", "2026-10-05_11-00-00_sys.m4a"])
        #expect(store.audioURLs(for: list[0]).count == 2)
        #expect(list[0].app == "Zoom")

        // Text found afterwards is added to the record.
        var dictation = list[1]
        dictation.text = "Bonjour à tous."
        store.update(dictation)
        #expect(store.load(id: dictation.id)?.preview == "Bonjour à tous.")

        store.delete(id: "2026-10-05_11-00-00")
        #expect(store.list().map(\.id) == ["2026-10-05_10-00-00"])
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("2026-10-05_11-00-00_mic.m4a").path))
        // A deleted record is not recreated by a late update.
        store.update(CancelledRecording(id: "2026-10-05_11-00-00", createdAt: now, mode: .meeting, duration: 1))
        #expect(store.list().count == 1)
    }

    @Test func purgesWhatIsPastTheDeadline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CancelledStore(library: root)
        let now = Date()
        try store.keep(CancelledRecording(id: "vieux", createdAt: now, cancelledAt: now.addingTimeInterval(-3 * 3600), mode: .dictation, duration: 1), mic: tone)
        try store.keep(CancelledRecording(id: "recent", createdAt: now, cancelledAt: now, mode: .dictation, duration: 1), mic: tone)
        #expect(store.purge(cancelledBefore: now.addingTimeInterval(-3600)) == 1)
        #expect(store.list().map(\.id) == ["recent"])
    }

    @Test func staysOutOfTheLibraryIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try CancelledStore(library: root).keep(
            CancelledRecording(id: "2026-10-05_10-00-00", createdAt: Date(), mode: .dictation, duration: 1), mic: tone)
        let library = TranscriptStore(root: root)
        #expect(library.list().isEmpty)
        #expect(Recovery.pending(in: library).isEmpty)
    }

    @Test func cancelShortcutDefaultAndBackup() {
        // Escape alone by default, as before; changeable in settings.
        #expect(PlumeSettings.defaultCancelShortcut == Shortcut(keyCode: 53, modifiers: 0))
        #expect(SettingsBackup.shortcutKeys.contains(PlumeSettings.Key.cancelShortcut))
        #expect(SettingsBackup.shortcutKeys.contains(PlumeSettings.Key.restoreShortcut))
        #expect(SettingsBackup.numberKeys.contains(PlumeSettings.Key.cancelledRetentionHours))
    }
}

@Suite("Audio files")
struct AudioFileTests {
    /// Four tones plus noise from a fixed-seed generator: every run encodes the same signal.
    static func signal(count: Int) -> [Float] {
        var seed: UInt32 = 1
        return (0..<count).map { i in
            let t = Double(i) / 16_000
            var value = 0.0
            for frequency in [220.0, 660.0, 1500.0, 3200.0] {
                value += 0.1 * sin(2 * .pi * frequency * t)
            }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            value += (Double(seed) / Double(UInt32.max) * 2 - 1) * 0.01
            return Float(value)
        }
    }

    static func rms(_ samples: [Float]) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// Encoded audio bytes, the value `afinfo` prints as "audio bytes": the file's header adds
    /// several KB, which on a 10 s file would blur 32 against 48 kbps.
    static func audioDataBytes(_ url: URL) throws -> Int {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { AudioFileClose(file) }
        var bytes: UInt64 = 0
        var size = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyAudioDataByteCount, &size, &bytes) == noErr else {
            throw CocoaError(.fileReadUnknown)
        }
        return Int(bytes)
    }

    /// Writes and reads back through the app's own functions, in a temporary folder.
    static func roundTrip(_ input: [Float], check: ([Float], URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("2026-10-07_10-00-00_mic.m4a")
        try AudioIO.writeM4A(input, to: url)
        try check(try AudioIO.loadSamples(url), url)
    }

    @Test func writeThenLoadRoundTrip() throws {
        let input = Self.signal(count: 160_000)
        try Self.roundTrip(input) { output, url in
            // AVAudioFile trims the encoder's priming; the slack covers the last frame's padding
            // and FluidAudio stopping early at the end of the stream.
            #expect(abs(output.count - input.count) <= 2_112)
            #expect(abs(20 * log10(Self.rms(output) / Self.rms(input))) <= 1)
            // 48 kbps × 10 s = 60,000 bytes ± 15 %: 40 kbps (50,000) or 32 kbps (40,000) falls outside.
            let bytes = try Self.audioDataBytes(url)
            #expect((51_000...69_000).contains(bytes))
        }
    }

    /// Nothing at all, a 50 ms tap, and a meeting channel: 1 s of lead silence, then more than
    /// one 10 s write chunk.
    @Test(arguments: [0, 800, 400_000])
    func roundTripKeepsLength(count: Int) throws {
        let lead = count > 16_000 ? 16_000 : 0
        let input = [Float](repeating: 0, count: lead) + Self.signal(count: count - lead)
        try Self.roundTrip(input) { output, _ in
            #expect(abs(output.count - input.count) <= 2_112)
            if !input.isEmpty {
                #expect(abs(20 * log10(Self.rms(output) / Self.rms(input))) <= 1)
            }
        }
    }
}

@Suite("Changelog")
struct ChangelogTests {
    @Test func readsVersionsAndEntries() {
        let releases = Changelog.parse("""
            # Journal des modifications

            Une ligne par PR.

            ## 1.0.0

            ### 2026-10-05

            - Historique : les enregistrements annulés restent récupérables (#7)

            ### 2026-10-02

            - README en anglais

            ## 0.9.0 — 2026-10-02

            ### 2026-10-02

            - 2026-10-02 — Première version publique
            """)
        #expect(releases.map(\.version) == ["1.0.0", "0.9.0"])
        #expect(releases[0].date == nil)
        #expect(releases[1].date == "2026-10-02")
        #expect(releases[0].entries[0] == Changelog.Entry(
            date: "2026-10-05", domain: "Historique", text: "Les enregistrements annulés restent récupérables", pullRequest: 7))
        #expect(releases[0].entries[1].domain == nil)
        #expect(releases[0].entries[1].date == "2026-10-02")
        #expect(releases[1].entries[0].text == "Première version publique")
        #expect(releases[0].entries[1].text == "README en anglais")
        #expect(Changelog.signature(of: releases) == "1.0.0|Les enregistrements annulés restent récupérables")
    }

    @Test func splitsTheAreaInBothFormats() {
        let releases = Changelog.parse("""
            ## 1.0.3
            ### 2026-10-06
            - Repo: code in English (#15)
            - Historique : les annulés restent récupérables (#7)
            - No area here, just text
            - Première version publique : Plume 1.0
            - Fixed a crash when the text says: hello world again
            """)
        #expect(releases[0].entries[0] == Changelog.Entry(date: "2026-10-06", domain: "Repo", text: "Code in English", pullRequest: 15))
        #expect(releases[0].entries[1].domain == "Historique")
        #expect(releases[0].entries[1].text == "Les annulés restent récupérables")
        #expect(releases[0].entries[2].domain == nil)
        #expect(releases[0].entries[3].domain == "Première version publique")
        #expect(releases[0].entries[4].domain == nil)
    }
}

@Suite("Statistics")
struct StatsTests {
    func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    func dictation(_ day: String, words: Int, seconds: Double) -> Transcript {
        Transcript(
            id: day, createdAt: date(day), mode: .dictation, duration: seconds, engine: "t",
            text: Array(repeating: "mot", count: words).joined(separator: " "), rawText: "")
    }

    @Test func totalsRateAndTimeSaved() {
        let now = date("2026-10-02 18:00")
        let stats = LibraryStats(
            transcripts: [
                dictation("2026-10-02 09:00", words: 300, seconds: 120),
                dictation("2026-10-01 09:00", words: 100, seconds: 60),
                dictation("2026-09-20 09:00", words: 50, seconds: 30),
            ], now: now)
        #expect(stats.transcripts == 3)
        #expect(stats.words == 450)
        #expect(stats.wordsThisWeek == 400)
        // 450 words in 210 s: 129 words per minute.
        #expect(stats.wordsPerMinute == 129)
        // At 40 words per minute, 450 words take 675 s of typing; 210 s of speech.
        #expect(stats.timeSaved == 465)
        #expect(stats.streak == 2)
        #expect(stats.days.count == 371)
        #expect(stats.days.last?.words == 300)
        #expect(stats.wordsToday == 300)
        #expect(stats.bestDay?.words == 300)
        #expect(stats.bestStreak == 2)
        #expect(stats.days.reduce(0) { $0 + $1.words } == 450)
    }

    @Test func streakHoldsIfNothingWasDictatedToday() {
        let stats = LibraryStats(
            transcripts: [dictation("2026-10-01 09:00", words: 10, seconds: 5), dictation("2026-09-30 09:00", words: 10, seconds: 5)],
            now: date("2026-10-02 08:00"))
        #expect(stats.streak == 2)
        let broken = LibraryStats(
            transcripts: [dictation("2026-09-29 09:00", words: 10, seconds: 5)], now: date("2026-10-02 08:00"))
        #expect(broken.streak == 0)
    }

    @Test func inMeetingsOnlyMyWordsCount() {
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 1, text: "un deux trois"),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "quatre cinq six sept"),
        ]
        let meeting = Transcript(
            id: "m", createdAt: date("2026-10-02 10:00"), mode: .meeting, duration: 60, engine: "t",
            text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
            speakers: ["Moi", "Interlocuteur 1"])
        let stats = LibraryStats(transcripts: [meeting], now: date("2026-10-02 18:00"))
        #expect(stats.words == 3)
        #expect(stats.meetings == 1)
        #expect(stats.wordsPerMinute == 0)
    }
}

@Suite("Formats")
struct FormatTests {
    @Test func durations() {
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3723) == "1:02:03")
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(725) == "12 min 05 s")
        #expect(Format.duration(3720) == "1 h 02 min")
    }

    @Test func modesFromTheirSlug() {
        #expect(RecordingMode(slug: "reunion") == .meeting)
        #expect(RecordingMode(slug: "Dictée") == .dictation)
        #expect(RecordingMode(slug: "autre") == nil)
    }
}

@Suite("Voice commands")
struct VoiceCommandsTests {
    func run(_ text: String) -> String { VoiceCommands.apply(to: text).text }

    @Test func lineBreaksAndParagraphs() {
        #expect(run("Bonjour Marc, à la ligne, je voulais te dire que c'est validé.") == "Bonjour Marc,\nJe voulais te dire que c'est validé.")
        #expect(run("C'est validé. Nouveau paragraphe. On se voit jeudi.") == "C'est validé.\n\nOn se voit jeudi.")
        #expect(run("Merci à la ligne bonne journée") == "Merci\nBonne journée")
        #expect(run("Hello team, new line, the release is ready. New paragraph. See you.") == "Hello team,\nThe release is ready.\n\nSee you.")
        #expect(run("c'est fini point à la ligne et voilà") == "c'est fini.\nEt voilà")
    }

    @Test func doesNotConfuseWithEverydayLanguage() {
        #expect(run("Il adore la pêche à la ligne.") == "Il adore la pêche à la ligne.")
        #expect(run("Regarde à la ligne 42 du fichier.") == "Regarde à la ligne 42 du fichier.")
        #expect(run("On passe à la ligne suivante.") == "On passe à la ligne suivante.")
        #expect(run("La nouvelle ligne de produits sort en mai.") == "La nouvelle ligne de produits sort en mai.")
        #expect(run("Il faut un nouveau paragraphe ici.") == "Il faut un nouveau paragraphe ici.")
        #expect(run("J'ai deux points de vue là-dessus.") == "J'ai deux points de vue là-dessus.")
    }

    @Test func dictatedPunctuation() {
        #expect(run("Tu viens demain point d'interrogation") == "Tu viens demain ?")
        #expect(run("Génial point d'exclamation on y va") == "Génial ! on y va")
        #expect(run("Liste de courses, deux points, à la ligne, tiret, des pâtes, à la ligne, tiret, des tomates") == "Liste de courses :\n- des pâtes\n- des tomates")
        #expect(run("Il a dit ouvrez les guillemets c'est parfait fermez les guillemets.") == "Il a dit « c'est parfait ».")
        #expect(run("Nouvelle puce premier point nouvelle puce deuxième point") == "\n- premier point\n- deuxième point")
    }

    @Test func scratchThat() {
        #expect(run("Je passe demain matin. Non en fait je passe demain soir. Efface ça. Je passe jeudi.") == "Je passe demain matin. Je passe jeudi.")
        #expect(run("Première idée. Efface ça.") == "")
        #expect(run("Bonjour. Deuxième phrase, efface ça, troisième phrase.") == "Bonjour. Troisième phrase.")
        #expect(run("Tout un texte. Efface tout. On repart.") == "On repart.")
        #expect(run("Il faut que j'efface ça de la liste.") == "Il faut que j'efface ça de la liste.")
        #expect(run("Hello there. Scratch that. Hi.") == "Hi.")
    }

    @Test func pressEnter() {
        let result = VoiceCommands.apply(to: "On se voit demain. Appuie sur Entrée.")
        #expect(result.text == "On se voit demain.")
        #expect(result.pressReturn)
        #expect(VoiceCommands.apply(to: "Ok, press enter").pressReturn)
        #expect(!VoiceCommands.apply(to: "Il faut appuyer sur Entrée pour valider le formulaire.").pressReturn)
    }
}

@Suite("Styles and insertion")
struct StyleTests {
    @Test func styles() {
        #expect(TextStyle.apply(.message, to: "Salut, on se voit demain.") == "Salut, on se voit demain")
        #expect(TextStyle.apply(.message, to: "Tu viens ?") == "Tu viens ?")
        #expect(TextStyle.apply(.message, to: "Attends…") == "Attends…")
        #expect(TextStyle.apply(.casual, to: "Salut. Je passe à 10 h. L'URL est bonne. I think so.") == "salut. je passe à 10 h. l'URL est bonne. I think so")
        #expect(TextStyle.apply(.standard, to: "Tel quel.") == "Tel quel.")
    }

    @Test func rulePerApp() {
        let rules = [
            AppRule(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", style: .message),
            AppRule(bundleID: "*", name: "Autres", style: .casual),
        ]
        #expect(AppRuleStore.rule(for: "com.tinyspeck.slackmacgap", in: rules)?.style == .message)
        #expect(AppRuleStore.rule(for: "com.apple.mail", in: rules)?.style == .casual)
        #expect(AppRuleStore.rule(for: nil, in: rules)?.bundleID == "*")
        #expect(AppRuleStore.rule(for: "x", in: [rules[0]]) == nil)
    }

    @Test func smartInsertion() {
        let text = "Je passe demain."
        #expect(SmartInsert.adapt(text, context: .empty) == text)
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "Bonjour.")) == " Je passe demain.")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "Bonjour. ")) == "Je passe demain.")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "Comme prévu,")) == " je passe demain.")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "Comme prévu, ", after: "et je reste.")) == "je passe demain ")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "Note :\n")) == "Je passe demain.")
        #expect(SmartInsert.adapt("Paris est loin.", context: InsertionContext(before: "Je crois que")) == " Paris est loin.")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "(")) == "Je passe demain.")
        #expect(SmartInsert.adapt(text, context: InsertionContext(before: "donc", after: "\nSuite")) == " je passe demain.")
    }

    @Test func fullFormatting() {
        let options = DictationOptions(cleanup: true, voiceCommands: true, style: .message)
        let result = Pipeline.format("euh bonjour Marc, à la ligne, c'est c'est validé. Appuie sur entrée.", options: options, replacements: [])
        #expect(result.text == "Bonjour Marc,\nC'est validé")
        #expect(result.pressReturn)
    }
}

@Suite("Export and maintenance")
struct ExportTests {
    let meeting: Transcript = {
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 2.5, text: "On valide le budget ?"),
            Segment(id: 1, speaker: "Inès", channel: .system, start: 2.5, end: 4, text: "Oui, validé."),
        ]
        return Transcript(
            id: "2026-10-02_11-30-00", createdAt: Date(), mode: .meeting, duration: 4, engine: "t",
            text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments, speakers: ["Moi", "Inès"],
            title: "Point budget", summary: "## Points clés\n- Budget validé")
    }()

    @Test func subtitles() {
        let srt = Exporter.render(meeting, as: .subtitles)
        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,500\nMoi : On valide le budget ?\n"))
        #expect(srt.contains("2\n00:00:02,500 --> 00:00:04,000\nInès : Oui, validé."))
        let vtt = Exporter.render(meeting, as: .webSubtitles)
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:02.500"))
        #expect(Exporter.fileName(for: meeting, format: .subtitles) == "2026-10-02_11-30-00 Point budget.srt")
    }

    @Test func splitsLongLines() {
        let long = Transcript(
            id: "x", createdAt: Date(), mode: .imported, duration: 20, engine: "t",
            text: String(repeating: "mot ", count: 60).trimmingCharacters(in: .whitespaces), rawText: "")
        let cues = Exporter.cues(for: long)
        #expect(cues.count == 3)
        #expect(cues.allSatisfy { $0.text.count <= Exporter.maxCueCharacters })
        #expect(abs((cues.last?.end ?? 0) - 20) < 0.001)
    }

    @Test func markdownWithSummaryAndTitle() {
        L10n.$override.withValue(.french) {
            let md = TranscriptStore.markdown(for: meeting)
            #expect(md.contains("# Point budget\nRéunion du"))
            #expect(md.contains("## Résumé\n\n## Points clés\n- Budget validé\n\n## Transcription"))
            #expect(Exporter.render(meeting, as: .text).hasPrefix("Point budget\n\n## Points clés"))
        }
    }

    @Test func deletesOldAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        let store = TranscriptStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = Date().addingTimeInterval(-40 * 86_400)
        let recent = Date().addingTimeInterval(-2 * 86_400)
        for (date, name) in [(old, "ancien"), (recent, "récent")] {
            let id = store.makeID(for: date)
            let directory = try store.ensureDirectory(forID: id)
            try Data([0, 1]).write(to: directory.appendingPathComponent("\(id)_mic.m4a"))
            try store.save(
                Transcript(
                    id: id, createdAt: date, mode: .dictation, duration: 1, engine: "t", text: name, rawText: "",
                    audioFiles: ["\(id)_mic.m4a"]))
        }
        #expect(store.dropAudio(olderThan: Date().addingTimeInterval(-30 * 86_400)) == 1)
        let items = store.list()
        #expect(items.first { $0.text == "ancien" }?.audioFiles.isEmpty == true)
        #expect(items.first { $0.text == "récent" }?.audioFiles.count == 1)
        #expect(store.audioURLs(for: items.first { $0.text == "récent" }!).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}

@Suite("Settings backup")
struct SettingsBackupTests {
    @Test func roundTrip() throws {
        let file = SettingsBackup.File(
            date: Date(), shortcuts: ["dictationShortcut": Shortcut(keyCode: 49, modifiers: ModifierMask.option)],
            booleans: ["voiceCommands": false, "pasInconnu": true], numbers: ["audioRetentionDays": 30], strings: ["soundPack": "beeps"],
            replacements: [Replacement(original: "a", with: "b")], rules: [AppRule(bundleID: "*", name: "Autres", style: .message)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsBackup.File.self, from: try encoder.encode(file))
        #expect(decoded.shortcuts["dictationShortcut"]?.keyCode == 49)
        #expect(decoded.rules.first?.style == .message)
        #expect(decoded.replacements == file.replacements)
    }
}

@Suite("Appearance and sound pack values")
struct SettingsValueTests {
    @Test func appearanceReadsOldAndNewValues() {
        let cases: [(String?, String)] = [
            ("sombre", "dark"), ("clair", "light"), ("systeme", "system"), ("dark", "dark"), ("light", "light"),
            ("system", "system"), (nil, "dark"), ("autre", "dark"),
        ]
        for (raw, expected) in cases { #expect(PlumeSettings.normalizedAppearance(raw) == expected) }
    }

    @Test func soundPackReadsOldAndNewValues() {
        let cases: [(String?, String)] = [
            ("bips", "beeps"), ("clics", "clicks"), ("melodie", "melody"), ("glisse", "glide"), ("bois", "wood"),
            ("pluck", "pluck"), ("beeps", "beeps"), ("wood", "wood"), (nil, "pluck"), ("inconnu", "inconnu"),
        ]
        for (raw, expected) in cases { #expect(PlumeSettings.normalizedSoundPack(raw) == expected) }
    }

    @Test func backupExportsEnglishValues() {
        let name = "plume-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        func strings() -> [String: String] { SettingsBackup.snapshot(defaults: defaults, replacements: [], rules: []).strings }

        let appearance = PlumeSettings.Key.appearance, soundPack = PlumeSettings.Key.soundPack
        #expect(strings()[appearance] == nil)
        defaults.set("sombre", forKey: appearance)
        defaults.set("bips", forKey: soundPack)
        #expect(strings()[appearance] == "dark")
        #expect(strings()[soundPack] == "beeps")
    }
}

@Suite("Local AI, without a model")
struct LocalAITests {
    @Test func splitsAtParagraphs() {
        let paragraph = String(repeating: "Une phrase courte. ", count: 20)
        let text = (0..<12).map { _ in paragraph }.joined(separator: "\n")
        let chunks = LocalAI.chunks(of: text, limit: 1_000)
        #expect(chunks.count >= 4)
        #expect(chunks.allSatisfy { $0.count <= 1_000 })
        #expect(chunks.joined(separator: "\n").replacingOccurrences(of: "\n", with: " ") == text.replacingOccurrences(of: "\n", with: " "))
        #expect(LocalAI.chunks(of: "court") == ["court"])
    }

    @Test func cleansTheReply() {
        #expect(LocalAI.stripped("Voici le texte corrigé : Bonjour.") == "Bonjour.")
        #expect(LocalAI.stripped("```\nBonjour.\n```") == "Bonjour.")
        #expect(LocalAI.stripped("« Bonjour. »") == "Bonjour.")
        #expect(LocalAI.plausible("Bonjour Marc, ça va ?", for: "bonjour marc ça va"))
        #expect(!LocalAI.plausible("", for: "bonjour"))
        #expect(!LocalAI.plausible(String(repeating: "x", count: 400), for: String(repeating: "y", count: 100)))
    }
}

extension LocalAITests {
    @Test func tidiesMarkdown() {
        let raw = "- ## Points clés\n  - La page est prête.\n  * Annonce jeudi.\n\n\n- ## Actions\n  - Thomas : captures."
        #expect(LocalAI.tidyMarkdown(raw) == "## Points clés\n- La page est prête.\n- Annonce jeudi.\n\n## Actions\n- Thomas : captures.")
    }
}

@Suite("Transcription models")
struct EngineModelTests {
    @Test func allDescribedAndCustomLast() {
        #expect(EngineModel.allCases.allSatisfy { !$0.label.isEmpty && !$0.detail.isEmpty })
        #expect(EngineModel.allCases.last == .custom)
        #expect(EngineModel.allCases.filter { !$0.isBuiltIn } == [.custom])
        #expect(EngineModel(rawValue: "parakeet-ultra") == .parakeetUltra)
    }

    @Test func incompleteCustomFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("plume-modele-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(SpeechEngine.missingCustomFiles(in: directory).count == 4)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Preprocessor.mlmodelc"), withIntermediateDirectories: true)
        #expect(SpeechEngine.missingCustomFiles(in: directory).first == "Decoder.mlmodelc")
        #expect(!EngineModel.custom.isAvailableOffline(customDirectory: directory))
        #expect(!EngineModel.custom.isAvailableOffline(customDirectory: nil))
    }
}

@Suite("Interface language")
struct LocalizationTests {
    @Test func translatesToEnglishAndBackToFrench() {
        L10n.$override.withValue(.english) {
            #expect(tr("History") == "History")
            #expect(tr("String missing from the table") == "String missing from the table")
            #expect(TranscriptBuilder.speakerName(1) == "Speaker 1")
            #expect(TranscriptBuilder.meName == "Me")
            #expect(RecordingMode.meeting.label == "Meeting")
        }
        L10n.$override.withValue(.french) {
            #expect(tr("History") == "Historique")
            #expect(tr("String missing from the table") == "String missing from the table")
            #expect(tr("Microphone") == "Micro")
            #expect(tr("Microphone access") == "Microphone")
            #expect(tr("Import") == "Import")
            #expect(tr("Import file") == "Importer")
            #expect(TranscriptBuilder.speakerName(1) == "Interlocuteur 1")
            #expect(TranscriptBuilder.isMe("Me") && TranscriptBuilder.isMe("Moi") && !TranscriptBuilder.isMe("Inès"))
        }
    }

    @Test func noEmptyTranslation() {
        #expect(L10n.missing.isEmpty)
        #expect(Language.english.locale.identifier == "en_US")
    }

    /// Every single-line `tr("…")` literal in Sources must be a key of the French table.
    /// Multi-line `tr("""…""")` literals and calls with interpolation are skipped.
    @Test func everyTrLiteralHasAFrenchEntry() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let call = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])tr\("((?:[^"\\]|\\.)*)"\)"#)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        var missing: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(match.range(at: 1), in: text)!])
                guard !raw.contains("\\("), raw.contains(where: \.isLetter), raw != "Plume" else { continue }
                let key = raw
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                checked += 1
                if L10nTable.french[key] == nil { missing.append("\(file.lastPathComponent): \(raw.prefix(60))") }
            }
        }
        #expect(checked > 100)
        #expect(missing.isEmpty, "Keys missing from L10nTable.french: \(missing)")
    }
}
