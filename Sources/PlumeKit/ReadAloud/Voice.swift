import FluidAudio
import Foundation

/// Speaks one sentence at a time. Speed is not here: the player applies it, so changing it
/// never re-synthesizes.
public protocol Voice: Sendable {
    var sampleRate: Double { get }
    func load() async throws
    /// Mono samples at `sampleRate`.
    func speak(_ sentence: String, language: String) async throws -> [Float]
    func unload() async
}

/// Supertonic-3 through FluidAudio, from Plume's own models folder.
public actor SupertonicVoice: Voice {
    public nonisolated let sampleRate = Double(Supertonic3Constants.sampleRate)
    public let entry: VoiceEntry
    private let modelsDirectory: URL
    private var manager: Supertonic3Manager?
    private var style: Supertonic3VoiceStyle?

    public init(entry: VoiceEntry, modelsDirectory: URL) {
        self.entry = entry
        self.modelsDirectory = modelsDirectory
    }

    /// Checks the files first: FluidAudio would otherwise download what is missing, without
    /// the user's consent or a progress bar.
    public func load() async throws {
        guard manager == nil else { return }
        guard VoiceAssets.isInstalled(in: modelsDirectory) else { throw ReadAloudError.voiceNotInstalled }
        let manager = Supertonic3Manager(directory: modelsDirectory, vectorEstimator: VoiceAssets.vectorEstimator)
        try await manager.initialize()
        style = try Supertonic3VoiceStyle.load(from: VoiceAssets.styleURL(entry.style, in: modelsDirectory))
        self.manager = manager
    }

    public func speak(_ sentence: String, language: String) async throws -> [Float] {
        guard let manager, let style else { throw ReadAloudError.voiceNotInstalled }
        let spoken = SpokenText.voiceLanguages.contains(language) ? language : "en"
        let text = SpokenText.normalizerLanguage(spoken).map { NemoTextNormalizer.normalize(sentence, language: $0) } ?? sentence
        // Speed 1.0: Supertonic's own default is 1.05, and speed belongs to the player.
        return try await manager.synthesize(text: text, language: spoken, style: style, speed: 1.0).samples
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
        style = nil
    }
}
