import Foundation
import Testing
@testable import PlumeKit

/// The files written by a released version (`Tests/Fixtures/<version>/`): the app must
/// always read them back, and rewrite them without losing anything.
@Suite("Files of released versions")
struct SavedFormatTests {
    /// Fields or settings removed on purpose, each with its line in `CHANGELOG.md`: the
    /// samples that still contain them are not touched up, and this is not a loss.
    /// Each entry is an exact path, without indices, valid in every file: a field
    /// (`.summary`, `.segments.speaker`), a setting by its table (`.booleans.polish`). A field
    /// present in several places is listed for each (`.polish` in `applications.json`,
    /// `.rules.polish` in the backup). An entry also exempts its path from the invented-data
    /// check: its values were checked when the folder was produced.
    /// An entry also covers what lies under it: `.shortcuts.transformShortcut` covers
    /// its `keyCode`.
    static let removedOnPurpose: Set<String> = []

    /// An excused loss: the path, without its indices, is an entry of the list or lies
    /// under one (a removed shortcut covers its `keyCode` and its `modifiers`).
    static func isExcused(_ path: String, by entries: Set<String> = removedOnPurpose) -> Bool {
        let bare = path.replacingOccurrences(of: #"\[[0-9]+\]"#, with: "", options: .regularExpression)
        return entries.contains { bare == $0 || bare.hasPrefix($0 + ".") }
    }

    @Test func thereIsAtLeastOneVersion() {
        #expect(!Fixtures.versions.isEmpty, "Tests/Fixtures/ is empty")
    }

    /// The repo is public: a sample contains only invented data (texts and numbers: the
    /// voiceprint has only numbers), and only JSON files.
    @Test func samplesContainOnlyInventedData() throws {
        let fm = FileManager.default
        // Only version folders at the root: a file or a link there would escape the
        // checks below.
        let rootKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = (try? fm.contentsOfDirectory(at: Fixtures.root, includingPropertiesForKeys: Array(rootKeys))) ?? []
        let stray = entries.filter { url in
            let values = try? url.resourceValues(forKeys: rootKeys)
            let isVersionFolder = values?.isDirectory == true && values?.isSymbolicLink != true
                && Fixtures.isVersion(url.lastPathComponent)
            return !isVersionFolder && url.lastPathComponent != ".DS_Store"
        }
        #expect(stray.isEmpty, "Tests/Fixtures: only version folders allowed, found \(stray.map(\.lastPathComponent).sorted())")
        let invented = FixtureSamples.allLeaves
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        for version in Fixtures.versions {
            let everything = (fm.enumerator(at: version, includingPropertiesForKeys: keys)?.allObjects as? [URL]) ?? []
            // A symbolic link counts as a file: git would keep its target path.
            let others = everything.filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true, url.lastPathComponent != ".DS_Store" else { return false }
                return url.pathExtension != "json" || values?.isSymbolicLink == true
            }
            #expect(others.isEmpty, "\(version.lastPathComponent): not JSON \(others.map(\.lastPathComponent))")
            for file in Fixtures.jsonFiles(in: version) {
                // What was removed on purpose is no longer in today's samples.
                let kept = Fixtures.leaves(in: try Fixtures.object(at: file), at: "").filter { !Self.isExcused($0.path) }
                let unknown = Set(kept.map(\.value)).subtracting(invented)
                #expect(unknown.isEmpty, "\(file.path): \(unknown.sorted())")
            }
        }
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Read back then rewritten by the app, a file keeps every original key and value,
    /// except what was removed on purpose.
    private func expectNothingLost(_ original: Any, rewritten: URL, _ name: String) throws {
        let lost = Fixtures.missing(original, in: try Fixtures.object(at: rewritten)).filter { path in
            !Self.isExcused(path)
        }
        #expect(lost.isEmpty, "\(name) loses \(lost)")
    }

    @Test func transcriptsReadBackAndRewriteWithoutLoss() throws {
        for version in Fixtures.versions {
            let library = temporaryFolder()
            try FileManager.default.copyItem(at: version.appendingPathComponent("library"), to: library)
            defer { try? FileManager.default.removeItem(at: library) }
            // Cancelled recordings, under their 1.0.1 or current folder name, are not transcripts.
            let files = Fixtures.jsonFiles(in: library).filter { !$0.path.contains("/.annules/") && !$0.path.contains("/.cancelled/") }
            let store = TranscriptStore(root: library)
            let listed = store.list()
            #expect(listed.count == files.count, "\(version.lastPathComponent): \(listed.count) read back out of \(files.count)")
            if listed.count != files.count {
                // A transcript that no longer reads back: say why (often a required field
                // was added, see AGENTS.md) rather than leave it to be hunted down.
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                for file in files {
                    do { _ = try decoder.decode(Transcript.self, from: Data(contentsOf: file)) } catch {
                        Issue.record("\(version.lastPathComponent)/\(file.lastPathComponent): \(error)")
                    }
                }
            }
            #expect(listed.map(\.id) == listed.map(\.id).sorted(by: >))
            #expect(store.latest()?.id == listed.first?.id)
            for transcript in listed {
                let file = try #require(files.first { $0.lastPathComponent.hasPrefix(transcript.id + "_") })
                let original = try Fixtures.object(at: file)
                #expect(store.load(id: transcript.id) == transcript)
                // Emptied first: if the app rewrote elsewhere, the comparison would see it.
                try Data("{}".utf8).write(to: file)
                try store.save(transcript)
                try expectNothingLost(original, rewritten: file, "\(version.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
    }

    @Test func cancelledReadBackAndRewriteWithoutLoss() throws {
        for version in Fixtures.versions {
            let library = temporaryFolder()
            try FileManager.default.copyItem(at: version.appendingPathComponent("library"), to: library)
            defer { try? FileManager.default.removeItem(at: library) }
            let frozen = Fixtures.jsonFiles(in: library.appendingPathComponent(Fixtures.cancelledFolder(version: version)))
            #expect(!frozen.isEmpty, "\(version.lastPathComponent): no cancelled recording")
            // The store moves a 1.0.1 folder to its new name: read the files where it put them.
            let cancelled = CancelledStore(library: library)
            let files = Fixtures.jsonFiles(in: cancelled.root)
            #expect(files.map(\.lastPathComponent) == frozen.map(\.lastPathComponent))
            let listed = cancelled.list()
            #expect(listed.count == files.count, "\(version.lastPathComponent): \(listed.count) read back out of \(files.count)")
            for recording in listed {
                let file = try #require(files.first { $0.lastPathComponent == recording.id + ".json" })
                let original = try Fixtures.object(at: file)
                // Emptied first: if the app rewrote elsewhere, the comparison would see it.
                try Data("{}".utf8).write(to: file)
                cancelled.update(recording)
                try expectNothingLost(original, rewritten: file, "\(version.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
    }

    @Test func sideSettingsReadBackAndRewriteWithoutLoss() throws {
        let output = temporaryFolder()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        for version in Fixtures.versions {
            let name = version.lastPathComponent
            let support = version.appendingPathComponent("support")

            let vocabularyName = Fixtures.supportFile(.replacements, version: version)
            let vocabulary = support.appendingPathComponent(vocabularyName)
            let replacements = try #require(ReplacementStore.read(from: vocabulary), "\(name): vocabulary unreadable")
            try ReplacementStore.write(replacements, to: output.appendingPathComponent("\(name)-replacements.json"))
            try expectNothingLost(try Fixtures.object(at: vocabulary), rewritten: output.appendingPathComponent("\(name)-replacements.json"), "\(name)/\(vocabularyName)")

            let applications = support.appendingPathComponent("applications.json")
            let rules = try #require(AppRuleStore.read(from: applications), "\(name): rules unreadable")
            try AppRuleStore.write(rules, to: output.appendingPathComponent("\(name)-applications.json"))
            try expectNothingLost(try Fixtures.object(at: applications), rewritten: output.appendingPathComponent("\(name)-applications.json"), "\(name)/applications.json")

            let printName = Fixtures.supportFile(.voiceprint, version: version)
            let print = support.appendingPathComponent(printName)
            let voiceprint = try #require(VoiceprintStore.read(from: print), "\(name): voiceprint unreadable")
            try VoiceprintStore.write(voiceprint, to: output.appendingPathComponent("\(name)-voiceprint.json"))
            try expectNothingLost(try Fixtures.object(at: print), rewritten: output.appendingPathComponent("\(name)-voiceprint.json"), "\(name)/\(printName)")

            let backupName = Fixtures.settingsFile(version: version)
            let backupURL = version.appendingPathComponent(backupName)
            let backup = try SettingsBackup.read(from: backupURL)
            try SettingsBackup.write(backup, to: output.appendingPathComponent("\(name)-settings.json"))
            try expectNothingLost(try Fixtures.object(at: backupURL), rewritten: output.appendingPathComponent("\(name)-settings.json"), "\(name)/\(backupName)")
        }
    }

    /// A renamed settings key would reset that setting to its default for everyone
    /// (`keepHistory`, the privacy switch, defaults to `true`).
    @Test func everySavedSettingIsStillRecognized() throws {
        for version in Fixtures.versions {
            let backup = try SettingsBackup.read(from: version.appendingPathComponent(Fixtures.settingsFile(version: version)))
            let name = version.lastPathComponent
            let unknown = Set(backup.booleans.keys.filter { !SettingsBackup.booleanKeys.contains($0) }.map { ".booleans.\($0)" })
                .union(backup.numbers.keys.filter { !SettingsBackup.numberKeys.contains($0) }.map { ".numbers.\($0)" })
                .union(backup.strings.keys.filter { !SettingsBackup.stringKeys.contains($0) }.map { ".strings.\($0)" })
                .union(backup.shortcuts.keys.filter { !SettingsBackup.shortcutKeys.contains($0) }.map { ".shortcuts.\($0)" })
                .subtracting(Self.removedOnPurpose)
            #expect(unknown.isEmpty, "\(name): settings no longer recognized \(unknown.sorted())")
        }
    }

    /// These settings are not in the backup, but every Mac has stored them under this name:
    /// rename `libraryPath`, and a moved library would look empty.
    @Test func settingsOutsideTheBackupKeepTheirName() {
        #expect(PlumeSettings.Key.libraryPath == "libraryPath")
        #expect(PlumeSettings.Key.microphoneUID == "microphoneUID")
        #expect(PlumeSettings.Key.customModelPath == "customModelPath")
        #expect(PlumeSettings.Key.onboarded == "onboarded")
        #expect(PlumeSettings.Key.changelogSeen == "changelogSeen")
        #expect(PlumeSettings.Key.readAloudEngine == "readAloudEngine")
        #expect(PlumeSettings.Key.readAloudPendingDownload == "readAloudPendingDownload")
    }

    /// A format change adds the folder of its version: the newest contains everything
    /// today's code writes for the same samples.
    @Test func theNewestFolderIsUpToDate() throws {
        let newest = try #require(Fixtures.versions.last)
        let today = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: today) }
        try FixtureSamples.write(to: today)
        let command = "FIXTURES_VERSION=<version> ./scripts/test.sh --filter FixtureGenerator"
        let base = today.resolvingSymlinksInPath().path + "/"
        for file in Fixtures.jsonFiles(in: today) {
            let relative = String(file.resolvingSymlinksInPath().path.dropFirst(base.count))
            let frozen = newest.appendingPathComponent(relative)
            let name = "\(newest.lastPathComponent)/\(relative)"
            guard FileManager.default.fileExists(atPath: frozen.path) else {
                Issue.record("\(name) is missing: \(command)")
                continue
            }
            let lost = Fixtures.missing(try Fixtures.object(at: file), in: try Fixtures.object(at: frozen))
            #expect(lost.isEmpty, "\(name) lacks \(lost): \(command)")
        }
    }

    /// The full samples fill in every optional field: a field added without a sample
    /// value would appear in no sample.
    @Test func fullSamplesFillInEveryField() {
        func unset(_ value: Any) -> [String] {
            Mirror(reflecting: value).children.compactMap { child in
                let mirror = Mirror(reflecting: child.value)
                return mirror.displayStyle == .optional && mirror.children.isEmpty ? child.label : nil
            }
        }
        #expect(unset(FixtureSamples.dictation).isEmpty, "dictation: \(unset(FixtureSamples.dictation))")
        #expect(unset(FixtureSamples.meeting).isEmpty, "meeting: \(unset(FixtureSamples.meeting))")
        #expect(unset(FixtureSamples.cancelled).isEmpty, "cancelled: \(unset(FixtureSamples.cancelled))")
    }

    /// The samples cover every value these files can contain: a case added to an
    /// enumeration, or a setting added to the backup, must enter them too.
    @Test func samplesCoverEveryValue() {
        #expect(Set(FixtureSamples.transcripts.map(\.mode)) == Set(RecordingMode.allCases))
        #expect(Set(FixtureSamples.rules.map(\.style)) == Set(DictationStyle.allCases))
        #expect(Set(FixtureSamples.meeting.segments.map(\.channel)) == Set(AudioChannel.allCases))
        #expect(Set(FixtureSamples.backup.booleans.keys) == Set(SettingsBackup.booleanKeys))
        #expect(Set(FixtureSamples.backup.numbers.keys) == Set(SettingsBackup.numberKeys))
        #expect(Set(FixtureSamples.backup.strings.keys) == Set(SettingsBackup.stringKeys))
        #expect(Set(FixtureSamples.backup.shortcuts.keys) == Set(SettingsBackup.shortcutKeys))
    }

    /// `NSNumber` confuses `true` and `1`: a boolean turned into a number would pass the lossless read-back.
    @Test func valuesCompareAsTheyAre() {
        #expect(!Fixtures.missing(["a": true], in: ["a": 1]).isEmpty)
        #expect(!Fixtures.missing(["a": [1, 2]], in: ["a": [1]]).isEmpty)
        #expect(Fixtures.missing(["a": 6, "b": ["c": "d"]], in: ["a": 6, "b": ["c": "d", "e": 1], "f": 2]).isEmpty)
    }

    /// An entry excuses only the path it names: not the setting of the same name, nor the reverse.
    @Test func aRemovedEntryExcusesOnlyWhatItNames() {
        #expect(Self.isExcused("[0].polish", by: [".polish"]))
        #expect(Self.isExcused(".rules[2].polish", by: [".rules.polish"]))
        #expect(!Self.isExcused(".rules[2].polish", by: [".polish"]))
        #expect(!Self.isExcused(".rules[2].polish", by: [".booleans.polish"]))
        #expect(!Self.isExcused(".booleans.polish", by: [".polish"]))
        #expect(!Self.isExcused(".booleans.polish", by: [".rules.polish"]))
        #expect(!Self.isExcused(".booleans.autopolish", by: ["polish"]))
        #expect(!Self.isExcused(".summary", by: [".booleans.polish"]))
        #expect(Self.isExcused(".shortcuts.transformShortcut.keyCode", by: [".shortcuts.transformShortcut"]))
        #expect(!Self.isExcused(".shortcuts.transformShortcutX.keyCode", by: [".shortcuts.transformShortcut"]))
    }
}
