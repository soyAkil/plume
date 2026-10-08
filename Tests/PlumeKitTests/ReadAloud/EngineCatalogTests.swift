import FluidAudio
import Foundation
import Testing
@testable import PlumeKit

@Suite("Engine catalog")
struct EngineCatalogTests {
    @Test func entriesArePinnedAndWellFormed() {
        let all = SummaryEngineCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        for entry in all {
            guard case .llama(let spec) = entry.kind else { continue }
            #expect(spec.download.revision.count == 40, "\(entry.id)")
            #expect(spec.download.sha256.count == 64, "\(entry.id)")
            #expect(spec.download.bytes > 0, "\(entry.id)")
            #expect(spec.download.url.absoluteString.contains("/resolve/\(spec.download.revision)/"), "\(entry.id)")
            #expect(!spec.reasoningMarkers.isEmpty, "\(entry.id)")
            if case .explicit(let template) = spec.promptFormat {
                #expect(template.contains("{system}") && template.contains("{user}"), "\(entry.id)")
                // The tokenizer adds BOS itself: a literal one would be doubled.
                #expect(!template.contains("<bos>") && !template.contains("<s>"), "\(entry.id)")
            }
        }
    }

    @Test func unknownIdsResolveToNothing() {
        #expect(SummaryEngineCatalog.entry(id: "qwen3.5-4b-q4km") == SummaryEngineCatalog.qwen35_4b)
        #expect(SummaryEngineCatalog.entry(id: "gone-model") == nil)
        #expect(SummaryEngineCatalog.entry(id: "") == nil)
    }

    @Test func recommendsByChipAndMemory() {
        let gb: UInt64 = 1 << 30
        let rows: [(String, UInt64, String)] = [
            ("Apple M1", 8 * gb, "gemma4-e2b-q4"),
            ("Apple M2", 16 * gb, "gemma4-e2b-q4"),
            ("Apple M4", 24 * gb, "gemma4-e2b-q4"),
            ("Apple M1 Pro", 16 * gb, "qwen3.5-4b-q4km"),
            ("Apple M3 Max", 64 * gb, "qwen3.5-4b-q4km"),
            ("Apple M2 Ultra", 128 * gb, "qwen3.5-4b-q4km"),
            ("Apple M5", 24 * gb, "qwen3.5-4b-q4km"),
            ("Apple M5", 8 * gb, "gemma4-e2b-q4"),
            ("Apple M4 Pro", 8 * gb, "gemma4-e2b-q4"),
        ]
        for (chip, memory, expected) in rows {
            #expect(SummaryEngineCatalog.recommended(chip: chip, memoryBytes: memory)?.id == expected, "\(chip) \(memory / gb) GB")
        }
        let onlyOne = [SummaryEngineCatalog.qwen35_4b]
        #expect(SummaryEngineCatalog.recommended(chip: "Apple M1", memoryBytes: 8 * gb, in: onlyOne)?.id == "qwen3.5-4b-q4km")
        #expect(SummaryEngineCatalog.recommended(chip: "Apple M1", memoryBytes: 8 * gb, in: []) == nil)
    }

    @Test func voicesFallBackToTheDefault() {
        #expect(VoiceCatalog.entry(id: "supertonic3-m2").style == .m2)
        #expect(VoiceCatalog.entry(id: "nope") == VoiceCatalog.f1)
    }

    /// FluidAudio's download name is internal: rebuild it from the public part, so the
    /// variant downloaded is the one the manager loads.
    @Test func voiceVariantMatchesFluidAudio() {
        #expect(VoiceAssets.variant == "ane-" + Supertonic3Quantization.int4.rawValue)
        #expect(VoiceAssets.vectorEstimator == .aneBucketed(.int4))
    }

    /// The marker and every file: either alone could make loading download what is missing.
    @Test func voiceIsInstalledOnlyWithItsMarkerAndItsFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = VoiceAssets.folder(in: folder).appendingPathComponent(VoiceAssets.completeMarker)
        try FileManager.default.createDirectory(at: VoiceAssets.folder(in: folder), withIntermediateDirectories: true)
        #expect(!VoiceAssets.isInstalled(in: folder))
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        #expect(!VoiceAssets.isInstalled(in: folder))
        try FakeVoiceFiles.write(in: folder)
        #expect(VoiceAssets.isInstalled(in: folder))
        try FileManager.default.removeItem(at: VoiceAssets.styleURL(.m2, in: folder))
        #expect(!VoiceAssets.isInstalled(in: folder))
        try FakeVoiceFiles.write(in: folder)
        try FileManager.default.removeItem(at: marker)
        #expect(!VoiceAssets.isInstalled(in: folder))
    }

    @Test func pinningTheVoiceRevisionKeepsOtherOverrides() {
        VoiceAssets.pinRevision()
        #expect(ModelRegistry.revisionOverrides[VoiceAssets.repoID] == VoiceAssets.revision)
    }
}
