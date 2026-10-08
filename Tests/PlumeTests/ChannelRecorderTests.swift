import Foundation
import Testing
@testable import Plume
@testable import PlumeKit

/// A meeting channel writes its offset into its WAV as soon as it is known, so a meeting
/// recovered after a crash keeps its two channels in time. Time is passed with `elapsed:`.
@Suite("Channel recorder offset")
struct ChannelRecorderTests {
    static let start = Date(timeIntervalSince1970: 0)

    static func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func meetingWriter(in root: URL) throws -> WavWriter {
        try WavWriter(url: root.appendingPathComponent("2026-10-08_10-00-00_sys.wav"), recordsOffset: true)
    }

    /// The header as a crash would leave it: queued writes done, not closed.
    static func crashHeader(_ writer: WavWriter) throws -> (dataBytes: UInt32, offset: Double?) {
        writer.flush()
        let handle = try FileHandle(forReadingFrom: writer.url)
        defer { try? handle.close() }
        let bytes = [UInt8](try handle.read(upToCount: 60) ?? Data())
        let dataBytes = bytes[56..<60].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return (dataBytes, WavWriter.recordedOffset(header: Data(bytes)))
    }

    @Test func firstAppendRecordsTheOffset() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .system, sessionStart: Self.start)
        recorder.attach(writer)
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 10.1)
        writer.close()
        #expect(abs((WavWriter.recordedOffset(of: writer.url) ?? -1) - 10.0) < 1e-9)
    }

    /// After a pause over 30 s, the origin moves forward: the header follows it.
    @Test func originShiftRewritesTheOffset() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .system, sessionStart: Self.start)
        recorder.attach(writer)
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 1.1)
        // 1,580,800 samples missing, 480,000 padded: the origin moves 68.8 s forward.
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 100)
        writer.close()
        #expect(abs((WavWriter.recordedOffset(of: writer.url) ?? -1) - 69.8) < 1e-9)
    }

    /// Dictation switched to a meeting: the writer is attached after the first samples.
    @Test func attachAfterSamplesRecordsTheOffset() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .mic, sessionStart: Self.start)
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 0.1)
        recorder.attach(writer)
        writer.close()
        #expect(WavWriter.recordedOffset(of: writer.url) == 0)
        let count = try AudioIO.loadSamples(writer.url).count
        #expect(count == 1_600)
    }

    /// 80,001 samples (160,002 bytes) trigger a header rewrite: the counted header must
    /// already carry the offset, 10.0 − 80,001 / 16,000 s.
    @Test func crashTimeHeaderCarriesTheOffsetAfterFirstAppend() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .system, sessionStart: Self.start)
        recorder.attach(writer)
        recorder.append([Float](repeating: 0, count: 80_001), elapsed: 10.0)
        let header = try Self.crashHeader(writer)
        #expect(header.dataBytes == 160_002)
        #expect(abs((header.offset ?? -1) - 4.9999375) < 1e-9)
    }

    @Test func crashTimeHeaderCarriesTheOffsetAfterTheSwitch() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .mic, sessionStart: Self.start)
        recorder.append([Float](repeating: 0, count: 80_001), elapsed: 10.0)
        recorder.attach(writer)
        let header = try Self.crashHeader(writer)
        #expect(header.dataBytes == 160_002)
        #expect(abs((header.offset ?? -1) - 4.9999375) < 1e-9)
    }

    /// A dictation paused over 30 s, then switched to a meeting: the writer gets the shifted
    /// origin, not the first one.
    @Test func attachAfterAShiftRecordsTheShiftedOffset() throws {
        let root = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Self.meetingWriter(in: root)
        defer { writer.close() }
        let recorder = ChannelRecorder(channel: .mic, sessionStart: Self.start)
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 1.1)
        recorder.append([Float](repeating: 0, count: 1_600), elapsed: 100)
        recorder.attach(writer)
        writer.close()
        #expect(abs((WavWriter.recordedOffset(of: writer.url) ?? -1) - 69.8) < 1e-9)
    }
}
