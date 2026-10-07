import AVFoundation
import FluidAudio
import Foundation

public enum AudioIO {
    /// Loads any audio file (wav, m4a, mp3, caf…) as mono 16 kHz.
    public static func loadSamples(_ url: URL) throws -> [Float] {
        try AudioConverter().resampleAudioFile(url)
    }

    /// Encodes mono 16 kHz samples as AAC (.m4a), about 22 MB per hour. 48 kbps is the highest rate
    /// Apple's encoder accepts at 16 kHz mono (64 kbps throws), and it keeps re-transcription as
    /// accurate as the raw samples.
    public static func writeM4A(_ samples: [Float], to url: URL) throws {
        let sampleRate = Double(SpeechEngine.sampleRate)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_000 * 10
        var offset = 0
        while offset < samples.count {
            let n = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress! + offset, count: n)
            }
            try file.write(from: buffer)
            offset += n
        }
    }
}

/// Writes a 16-bit mono WAV as it goes: if the app crashes during a long
/// meeting, the audio already captured stays readable (the header is refreshed regularly).
public final class WavWriter: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "plume.wav-writer")
    private var dataBytes: UInt32 = 0
    private var bytesSinceHeader: UInt32 = 0
    private var closed = false
    private let sampleRate: UInt32

    public init(url: URL, sampleRate: Int = SpeechEngine.sampleRate) throws {
        self.url = url
        self.sampleRate = UInt32(sampleRate)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: header(dataBytes: 0))
    }

    private func header(dataBytes: UInt32) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        return data
    }

    public func append(_ samples: [Float]) {
        queue.async { [self] in
            // A last buffer may arrive after closing: ignore it.
            guard !closed else { return }
            var pcm = [Int16](repeating: 0, count: samples.count)
            for i in 0..<samples.count {
                pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767)
            }
            let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }
            guard (try? handle.write(contentsOf: data)) != nil else { return }
            dataBytes += UInt32(data.count)
            bytesSinceHeader += UInt32(data.count)
            // Every ~5 s of audio, make the file valid up to this point.
            if bytesSinceHeader > sampleRate * 2 * 5 {
                patchHeader()
            }
        }
    }

    private func patchHeader() {
        bytesSinceHeader = 0
        guard let end = try? handle.offset() else { return }
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: header(dataBytes: dataBytes))
        try? handle.seek(toOffset: end)
    }

    public func close() {
        queue.sync {
            guard !closed else { return }
            patchHeader()
            try? handle.close()
            closed = true
        }
    }
}
