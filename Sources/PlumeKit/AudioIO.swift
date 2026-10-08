import AVFoundation
import FluidAudio
import Foundation

public enum AudioIO {
    /// Loads any audio file (wav, m4a, mp3, caf…) as mono 16 kHz.
    public static func loadSamples(_ url: URL) throws -> [Float] {
        try AudioConverter().resampleAudioFile(url)
    }

    /// Encodes mono 16 kHz samples as AAC (.m4a), ~14 MB per hour.
    public static func writeM4A(_ samples: [Float], to url: URL) throws {
        let sampleRate = Double(SpeechEngine.sampleRate)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
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
///
/// A meeting WAV also carries a `plmo` chunk before `data`: the channel's offset from the
/// session start, so a recovered meeting keeps its two channels in time. It lives in the WAV
/// rather than a file of its own because it is then created, closed and deleted with the audio,
/// and written on the same queue as the samples. CoreAudio skips the unknown chunk.
public final class WavWriter: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "plume.wav-writer")
    private var dataBytes: UInt32 = 0
    private var bytesSinceHeader: UInt32 = 0
    private var closed = false
    private let sampleRate: UInt32
    private let recordsOffset: Bool
    /// Seconds from the session start to the first sample; -1 until known.
    private var offset: Double = -1

    public init(url: URL, sampleRate: Int = SpeechEngine.sampleRate, recordsOffset: Bool = false) throws {
        self.url = url
        self.sampleRate = UInt32(sampleRate)
        self.recordsOffset = recordsOffset
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
        append(UInt32(recordsOffset ? 52 : 36) + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        if recordsOffset {
            data.append(contentsOf: Array("plmo".utf8))
            append(UInt32(8))
            append(offset.bitPattern)
        }
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

    /// Records the channel's offset from the session start (meeting WAVs only). Queued like
    /// `append`, never waited on: it is called under the recorder's lock, on the audio thread.
    /// The header is rewritten at once, so a crash right after still leaves the offset.
    public func setOffset(_ seconds: Double) {
        guard recordsOffset else { return }
        queue.async { [self] in
            guard !closed else { return }
            offset = seconds
            patchHeader()
        }
    }

    /// Waits for the queued writes. Tests only: reads the header as a crash would leave it.
    func flush() {
        queue.sync {}
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

    /// Longest plausible channel offset (24 h): a larger value is a corrupt header, and
    /// padding by it would crash recovery.
    static let maxRecordedOffset: Double = 86_400

    /// The offset a meeting WAV recorded, or nil (1.0.1 file, not known yet, unreadable).
    static func recordedOffset(header: Data) -> Double? {
        let bytes = [UInt8](header)
        func tag(at i: Int) -> String? {
            i + 4 <= bytes.count ? String(decoding: bytes[i..<i + 4], as: UTF8.self) : nil
        }
        func integer(at i: Int, size: Int) -> UInt64? {
            guard i + size <= bytes.count else { return nil }
            return (0..<size).reduce(UInt64(0)) { $0 | UInt64(bytes[i + $1]) << (8 * UInt64($1)) }
        }
        guard tag(at: 0) == "RIFF", tag(at: 8) == "WAVE" else { return nil }
        var position = 12
        // Chunks up to `data`: the samples follow it, so nothing after it is read.
        while let id = tag(at: position), id != "data", let size = integer(at: position + 4, size: 4) {
            if id == "plmo" {
                guard size == 8, let bits = integer(at: position + 8, size: 8) else { return nil }
                let value = Double(bitPattern: bits)
                return value.isFinite && value >= 0 && value <= maxRecordedOffset ? value : nil
            }
            // A chunk of odd size is followed by one padding byte.
            position += 8 + Int(size) + Int(size % 2)
        }
        return nil
    }

    /// The offset a meeting WAV file recorded, read from its first 4,096 bytes.
    static func recordedOffset(of url: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4_096) else { return nil }
        return recordedOffset(header: data)
    }
}
