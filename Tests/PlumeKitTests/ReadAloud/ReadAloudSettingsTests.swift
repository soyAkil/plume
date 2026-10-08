import Foundation
import Testing
@testable import PlumeKit

@Suite("Read-aloud settings")
struct ReadAloudSettingsTests {
    /// A settings object on a throwaway suite, never the real one.
    private func withSettings(_ body: (PlumeSettings, UserDefaults) throws -> Void) rethrows {
        let name = "plume-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(PlumeSettings(defaults: defaults), defaults)
    }

    @Test func defaultsMatchTheSpec() {
        withSettings { settings, _ in
            #expect(settings.readAloudEngine == "")
            #expect(settings.readAloudPendingDownload == "")
            #expect(settings.readAloudKeepLoaded == nil)
            #expect(settings.readAloudShortcut == .none)
            #expect(settings.summarizeAloudShortcut == .none)
            #expect(settings.readAloudLength == .automatic)
            #expect(settings.readAloudLanguage == .sameAsText)
            #expect(settings.readAloudVoice == "supertonic3-f1")
            #expect(settings.readAloudSpeed == 1.5)
            #expect(settings.readAloudShowText == false)
        }
    }

    @Test func speedIsClampedToQuarterSteps() {
        #expect(ReadAloudSpeed.clamped(0.1) == 0.75)
        #expect(ReadAloudSpeed.clamped(9) == 2.0)
        #expect(ReadAloudSpeed.clamped(1.37) == 1.25)
        #expect(ReadAloudSpeed.clamped(1.38) == 1.5)
        withSettings { settings, _ in
            settings.readAloudSpeed = 3
            #expect(settings.readAloudSpeed == 2.0)
        }
    }

    @Test func keepLoadedDependsOnMemoryUntilChosen() {
        #expect(KeepLoaded.defaultFor(memoryBytes: 8 << 30) == .fiveMinutes)
        #expect(KeepLoaded.defaultFor(memoryBytes: 16 << 30) == .thirtyMinutes)
        #expect(KeepLoaded.defaultFor(memoryBytes: 24 << 30) == .thirtyMinutes)
        #expect(KeepLoaded.always.delay == nil)
        #expect(KeepLoaded.fiveMinutes.delay == 300)
        withSettings { settings, _ in
            settings.readAloudKeepLoaded = .always
            #expect(settings.readAloudKeepLoaded == .always)
            settings.readAloudKeepLoaded = nil
            #expect(settings.readAloudKeepLoaded == nil)
        }
    }

    /// Only a chosen "keep loaded" travels in a backup: an 8 GB Mac must not inherit
    /// the 30 minutes a 24 GB Mac defaults to.
    @Test func keepLoadedIsExportedOnlyOnceChosen() {
        withSettings { settings, defaults in
            func strings() -> [String: String] { SettingsBackup.snapshot(defaults: defaults, replacements: [], rules: []).strings }
            #expect(strings()[PlumeSettings.Key.readAloudKeepLoaded] == nil)
            settings.readAloudKeepLoaded = .thirtyMinutes
            #expect(strings()[PlumeSettings.Key.readAloudKeepLoaded] == "30min")
        }
    }

    /// The models are not on a restored Mac: the engine and a pending download stay out.
    @Test func modelChoicesStayOutOfTheBackup() {
        withSettings { settings, defaults in
            settings.readAloudEngine = "qwen3.5-4b-q4km"
            settings.readAloudPendingDownload = "voice"
            let file = SettingsBackup.snapshot(defaults: defaults, replacements: [], rules: [])
            #expect(file.strings[PlumeSettings.Key.readAloudEngine] == nil)
            #expect(file.strings[PlumeSettings.Key.readAloudPendingDownload] == nil)
        }
    }
}
