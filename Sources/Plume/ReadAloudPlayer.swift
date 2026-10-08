import AVFoundation

/// Plays sentences one after another through a pitch-preserving time-stretch, so the
/// speed setting never re-synthesizes. Minimal for the command line; PR 2 adds pause,
/// skipping and live speed changes for the island.
final class ReadAloudPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat

    init(sampleRate: Double, rate: Double) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        pitch.rate = Float(rate)
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        try engine.start()
        player.play()
    }

    /// Schedules one sentence and returns once it has been heard.
    func play(_ samples: [Float]) async {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in continuation.resume() }
        }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
