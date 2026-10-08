import Foundation
import Testing
@testable import PlumeKit

@Suite("Supertonic voice")
struct SupertonicVoiceTests {
    /// Loading never downloads: without the completion marker it fails, and writes nothing.
    @Test func loadingWithoutTheVoiceFailsAndDownloadsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let voice = SupertonicVoice(entry: VoiceCatalog.f1, modelsDirectory: folder)
        await #expect(throws: ReadAloudError.voiceNotInstalled) { try await voice.load() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    /// A marker left over a folder that lost files: FluidAudio would fetch them on load.
    @Test func loadingWithTheMarkerButMissingFilesDownloadsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")
        let voiceFolder = VoiceAssets.folder(in: folder)
        try FileManager.default.createDirectory(at: voiceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: voiceFolder.appendingPathComponent(VoiceAssets.completeMarker).path, contents: nil)
        let voice = SupertonicVoice(entry: VoiceCatalog.f1, modelsDirectory: folder)
        await #expect(throws: ReadAloudError.voiceNotInstalled) { try await voice.load() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: voiceFolder.path) == [VoiceAssets.completeMarker])
    }

    @Test func speaksAt44kHz() {
        let voice = SupertonicVoice(entry: VoiceCatalog.f1, modelsDirectory: URL(fileURLWithPath: "/nonexistent"))
        #expect(voice.sampleRate == 44_100)
    }
}
