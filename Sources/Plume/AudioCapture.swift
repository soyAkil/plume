import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import PlumeKit

enum CaptureError: LocalizedError {
    case noInput
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInput: return tr("No microphone available.")
        case .coreAudio(let step, let status): return String(format: tr("System audio capture failed (%@, code %d)."), step, status)
        }
    }
}

/// Continuously converts any audio stream to 16 kHz mono.
final class StreamResampler {
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(SpeechEngine.sampleRate), channels: 1, interleaved: false)!

    /// AVAudioEngine buffer (microphone).
    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, let data = buffer.floatChannelData else { return [] }
        // On a sound card with several inputs, the microphone often only uses one channel: we only
        // average the channels that carry signal, so as not to divide the voice by eight.
        let interleaved = buffer.format.isInterleaved
        func sample(_ channel: Int, _ frame: Int) -> Float {
            interleaved ? data[0][frame * channels + channel] : data[channel][frame]
        }
        var energy = [Float](repeating: 0, count: channels)
        for c in 0..<channels {
            var sum: Float = 0
            for f in 0..<frames {
                let value = sample(c, f)
                sum += value * value
            }
            energy[c] = sum
        }
        let loudest = energy.max() ?? 0
        let active = (0..<channels).filter { energy[$0] >= loudest * 0.05 }
        var mono = [Float](repeating: 0, count: frames)
        for c in active {
            for f in 0..<frames { mono[f] += sample(c, f) }
        }
        if active.count > 1 {
            let scale = 1 / Float(active.count)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: buffer.format.sampleRate)
    }

    /// Raw Core Audio buffers from a microphone, as 32-bit floats: all of the device's input streams,
    /// keeping only the channels that carry signal.
    func convert(microphone bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> [Float] {
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        // Each channel: (pointer, stride between two samples, frame count).
        var channels: [(UnsafePointer<Float>, Int, Int)] = []
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
            let base = UnsafePointer(data.assumingMemoryBound(to: Float.self))
            for channel in 0..<count { channels.append((base + channel, count, frames)) }
        }
        guard let frames = channels.map(\.2).min(), frames > 0 else { return [] }
        // On a sound card with several inputs, the microphone often only uses one channel: we only
        // average the active channels, so as not to divide the voice by eight.
        let energy = channels.map { channel -> Float in
            var sum: Float = 0
            for f in 0..<frames {
                let value = channel.0[f * channel.1]
                sum += value * value
            }
            return sum
        }
        let loudest = energy.max() ?? 0
        let active = channels.indices.filter { energy[$0] >= loudest * 0.05 }
        var mono = [Float](repeating: 0, count: frames)
        for index in active {
            let channel = channels[index]
            for f in 0..<frames { mono[f] += channel.0[f * channel.1] }
        }
        if active.count > 1 {
            let scale = 1 / Float(active.count)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: format.mSampleRate)
    }

    /// Raw Core Audio buffers (system audio tap), as 32-bit floats.
    func convert(bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> [Float] {
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        // If the audio output also has inputs (external sound card), their streams precede
        // the tap's in the list: system audio is always at the end.
        let separate = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let wanted = separate ? max(1, min(Int(format.mChannelsPerFrame), buffers.count)) : 1
        let tapBuffers = Array(buffers.suffix(wanted))
        guard let first = tapBuffers.first, first.mData != nil else { return [] }
        let interleavedChannels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * interleavedChannels)
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)

        var used = 0
        for buffer in tapBuffers {
            guard let data = buffer.mData,
                Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * interleavedChannels) == frames
            else { continue }
            let source = data.assumingMemoryBound(to: Float.self)
            if interleavedChannels > 1 {
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<interleavedChannels { sum += source[f * interleavedChannels + c] }
                    mono[f] += sum / Float(interleavedChannels)
                }
            } else {
                for f in 0..<frames { mono[f] += source[f] }
            }
            used += 1
        }
        if used > 1 {
            let scale = 1 / Float(used)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: format.mSampleRate)
    }

    private func resample(_ mono: [Float], rate: Double) -> [Float] {
        guard rate > 0 else { return [] }
        if rate == target.sampleRate { return mono }
        if converter == nil || sourceFormat?.sampleRate != rate {
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
            else { return [] }
            sourceFormat = format
            converter = AVAudioConverter(from: format, to: target)
        }
        guard let converter, let sourceFormat,
            let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(mono.count))
        else { return [] }
        input.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: mono.count) }

        let capacity = AVAudioFrameCount(Double(mono.count) * target.sampleRate / rate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}

/// Capture of the microphone chosen in settings (by default, the Mac's).
///
/// The device is read directly through Core Audio rather than AVAudioEngine: the latter
/// follows the system's default input — which Bluetooth headphones or a speaker
/// hijack as soon as they connect — and delivers nothing if another one is forced on it.
final class MicCapture {
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var aliveListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "plume.microphone", qos: .userInitiated)
    private let control = DispatchQueue(label: "plume.microphone.control")
    private let resampler = StreamResampler()
    private var running = false
    var onSamples: (([Float]) -> Void)?
    /// The microphone disappeared and no other could take over.
    var onFailure: (() -> Void)?
    /// Name of the microphone actually used (for the log and diagnostics).
    private(set) var deviceName = tr("none")

    private static var aliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() throws {
        try open()
        running = true
    }

    private func open() throws {
        // The chosen microphone if it is plugged in, otherwise the Mac's, otherwise the system input.
        var device = AudioObjectID(kAudioObjectUnknown)
        if let preferred = AudioDevices.preferredInput() {
            device = preferred.deviceID
            deviceName = preferred.name
        } else {
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            deviceName = tr("system default input")
        }
        guard device != kAudioObjectUnknown else { throw CaptureError.noInput }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0 else { throw CaptureError.coreAudio(tr("microphone format"), status) }
        TestHooks.log("microphone: \(deviceName), \(Int(format.mSampleRate)) Hz, \(format.mChannelsPerFrame) channel(s)")

        let streamFormat = format
        var described = false
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            if !described {
                described = true
                let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                TestHooks.log(
                    "microphone: first buffer [\(list.map { "\($0.mNumberChannels) channel(s) × \($0.mDataByteSize) bytes" }.joined(separator: ", "))], "
                        + "flags \(streamFormat.mFormatFlags), \(streamFormat.mBitsPerChannel) bits")
            }
            let samples = self.resampler.convert(microphone: input, format: streamFormat)
            if !samples.isEmpty { self.onSamples?(samples) }
        }
        guard status == noErr, let procID else { throw CaptureError.coreAudio(tr("reading the microphone"), status) }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(device, procID)
            self.procID = nil
            throw CaptureError.coreAudio(tr("starting the microphone"), status)
        }
        deviceID = device

        // Microphone unplugged or switched off during a recording: switch to another one.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceVanished() }
        aliveListener = listener
        AudioObjectAddPropertyListenerBlock(device, &Self.aliveAddress, control, listener)
    }

    private func close() {
        guard deviceID != kAudioObjectUnknown else { return }
        if let aliveListener {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.aliveAddress, control, aliveListener)
            self.aliveListener = nil
        }
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func deviceVanished() {
        DispatchQueue.main.async { [self] in
            guard running else { return }
            Log.write("microphone: “\(deviceName)” disappeared, switching to another microphone")
            close()
            do {
                try open()
            } catch {
                Log.write("microphone: no replacement microphone (\(error.localizedDescription))")
                onFailure?()
            }
        }
    }

    func stop() {
        running = false
        close()
    }
}

/// Capture of all the sound the computer plays (other participants' voices in a video call,
/// even with headphones), through a Core Audio "process tap". Only asks for the
/// "System Audio Recording" permission, not screen recording.
final class SystemAudioCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private let queue = DispatchQueue(label: "plume.system-audio", qos: .userInitiated)
    private let resampler = StreamResampler()
    var onSamples: (([Float]) -> Void)?
    private var outputListener: AudioObjectPropertyListenerBlock?
    /// False after `stop()`: a listener or timer still in flight restarts nothing.
    private var active = false
    private var formatWatch: DispatchSourceTimer?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Dedicated queue for the Core Audio setup calls. The first time, macOS suspends
    /// the tap creation until the user answers the permission prompt:
    /// none of this must run on the main thread.
    private let control = DispatchQueue(label: "plume.system-audio.control")

    /// Starts the capture in the background. Samples arrive as soon as the tap is ready
    /// (immediately, or after the user's consent the first time).
    func start() throws {
        control.async { [self] in
            active = true
            do {
                try startTap()
            } catch {
                Log.write("system audio: \(error.localizedDescription)")
                return
            }
            // Headphones plugged or unplugged in the middle of a meeting: recreate the tap on the new output.
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.active else { return }
                self.stopTap()
                try? self.startTap()
            }
            outputListener = listener
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, control, listener)

            // The output can change sample rate without changing device (Bluetooth headphones
            // switching to call mode): re-read the format and recreate the tap if it changed.
            let timer = DispatchSource.makeTimerSource(queue: control)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in
                guard let self, self.active, self.tapID != kAudioObjectUnknown else { return }
                var current = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                guard AudioObjectGetPropertyData(self.tapID, &address, 0, nil, &size, &current) == noErr,
                    current.mSampleRate != self.format.mSampleRate
                        || current.mChannelsPerFrame != self.format.mChannelsPerFrame
                else { return }
                Log.write("system audio: format changed, tap recreated")
                self.stopTap()
                try? self.startTap()
            }
            timer.resume()
            formatWatch = timer
        }
    }

    func stop() {
        control.async { [self] in
            active = false
            formatWatch?.cancel()
            formatWatch = nil
            if let outputListener {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, control, outputListener)
                self.outputListener = nil
            }
            stopTap()
        }
    }

    private func startTap() throws {
        // Global stereo tap; exclude ourselves so as not to capture our own sounds.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObjects())
        description.uuid = UUID()
        description.name = "Plume"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), tr("creating the tap"))
        tapID = tap

        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), tr("tap format"))

        // The tap is read through a private aggregate device, aligned on the real output.
        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Plume (system audio)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), tr("aggregate device"))
        aggregateID = device

        let tapFormat = format
        Log.write(
            "system audio: tap created (\(Int(tapFormat.mSampleRate)) Hz, \(tapFormat.mChannelsPerFrame) channels, "
                + "\(tapFormat.mBitsPerChannel) bits, flags \(tapFormat.mFormatFlags))")
        var described = false
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
                guard let self else { return }
                if !described {
                    described = true
                    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                    let layout = list.map { "\($0.mNumberChannels) channel(s) × \($0.mDataByteSize) bytes" }
                    Log.write("system audio: first buffer received [\(layout.joined(separator: ", "))]")
                }
                let samples = self.resampler.convert(bufferList: input, format: tapFormat)
                if !samples.isEmpty { self.onSamples?(samples) }
            }, tr("reading the tap"))
        try check(AudioDeviceStart(aggregateID, procID), tr("starting"))
    }

    private func stopTap() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            procID = nil
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            stopTap()
            throw CaptureError.coreAudio(step, status)
        }
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw CaptureError.coreAudio(tr("default output"), status) }

        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw CaptureError.coreAudio(tr("output identifier"), status) }
        return uid as String
    }

    /// Core Audio object of our own process, if it already exists.
    private static func ownProcessObjects() -> [AudioObjectID] {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return [] }
        return [object]
    }
}

/// A channel being recorded: in-memory buffer, backup file, sound level.
final class ChannelRecorder: @unchecked Sendable {
    let channel: AudioChannel
    let buffer = SampleBuffer()
    var onLevel: ((Float) -> Void)?
    private(set) var writer: WavWriter?
    private let sessionStart: Date
    private let lock = NSLock()
    private var firstSampleOffset: Double?

    init(channel: AudioChannel, sessionStart: Date) {
        self.channel = channel
        self.sessionStart = sessionStart
    }

    /// Offset of the first sample relative to the start of the session.
    var offset: Double {
        lock.lock()
        defer { lock.unlock() }
        return firstSampleOffset ?? 0
    }

    /// Attaches the backup file, first pouring in everything captured so far. A known offset
    /// is set before the pour: a pour over 5 s rewrites the header, and a header that counts
    /// samples must already carry their offset, or a crash recovery would place them at 0.
    func attach(_ writer: WavWriter) {
        lock.lock()
        defer { lock.unlock() }
        if let firstSampleOffset { writer.setOffset(firstSampleOffset) }
        let captured = buffer.all()
        if !captured.isEmpty { writer.append(captured) }
        self.writer = writer
    }

    /// `elapsed` (seconds since the session start) replaces the clock: tests only.
    func append(_ samples: [Float], elapsed: TimeInterval? = nil) {
        let rate = Double(SpeechEngine.sampleRate)
        let now = elapsed ?? Date().timeIntervalSince(sessionStart)
        lock.lock()
        if firstSampleOffset == nil {
            let first = max(0, now - Double(samples.count) / rate)
            firstSampleOffset = first
            writer?.setOffset(first)
        }
        let start = firstSampleOffset ?? 0

        // If the capture was interrupted (device change), fill with
        // silence so that timestamps stay aligned between channels.
        let expected = Int((now - start) * rate)
        let missing = expected - (buffer.count + samples.count)
        if missing > Int(rate / 2) {
            // At most thirty seconds of silence: after a long interruption (computer
            // sleep), shift the origin rather than fabricate hours of zeros.
            let padded = min(missing, Int(rate) * 30)
            if padded < missing {
                let shifted = start + Double(missing - padded) / rate
                firstSampleOffset = shifted
                writer?.setOffset(shifted)
            }
            let silence = [Float](repeating: 0, count: padded)
            buffer.append(silence)
            writer?.append(silence)
        }
        buffer.append(samples)
        writer?.append(samples)
        lock.unlock()
        onLevel?(AudioLevel.rms(samples[...]))
    }
}
