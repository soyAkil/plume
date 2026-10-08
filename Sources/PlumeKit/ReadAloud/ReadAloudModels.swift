import FluidAudio
import Foundation

public enum DownloadItem: Equatable, Sendable {
    case voice
    case engine(String)
}

/// One download or deletion at a time, across the app and the command line. Taken without
/// waiting: a second taker fails at once with "A download is already running". `flock`
/// locks belong to an open file, so two opens in one process also exclude each other.
final class DownloadLock {
    private var descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent(".download.lock").path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw ReadAloudError.downloadRunning }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            descriptor = -1
            throw ReadAloudError.downloadRunning
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

/// The voice and the summary models in Plume's models folder: downloaded, verified and
/// deleted only when the user asks.
public final class ReadAloudModels: @unchecked Sendable {
    public typealias VoiceInstaller = @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> Void

    public let directory: URL
    private let configuration: URLSessionConfiguration
    private let urlFor: @Sendable (ModelDownload) -> URL
    private let freeSpace: @Sendable (URL) -> Int64?
    private let installVoice: VoiceInstaller

    public static var defaultDirectory: URL {
        PlumeSettings.supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    public init(
        directory: URL = ReadAloudModels.defaultDirectory, configuration: URLSessionConfiguration = .default,
        urlFor: @escaping @Sendable (ModelDownload) -> URL = { $0.url },
        freeSpace: @escaping @Sendable (URL) -> Int64? = ReadAloudModels.availableCapacity,
        installVoice: @escaping VoiceInstaller = ReadAloudModels.fluidAudioVoiceInstall
    ) {
        self.directory = directory
        self.configuration = configuration
        self.urlFor = urlFor
        self.freeSpace = freeSpace
        self.installVoice = installVoice
    }

    public var isVoiceInstalled: Bool { VoiceAssets.isInstalled(in: directory) }

    public func modelURL(for entry: SummaryEngineEntry) -> URL {
        switch entry.kind {
        case .llama(let spec): return directory.appendingPathComponent(spec.download.file)
        }
    }

    public func isInstalled(_ entry: SummaryEngineEntry) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: entry).path)
    }

    func mismatchMarker(for entry: SummaryEngineEntry) -> URL {
        modelURL(for: entry).appendingPathExtension("mismatch")
    }

    /// The last download of this engine failed its checksum, and why: the app does not resume it
    /// on its own at launch, only on the user's Resume.
    public func checksumMismatchMessage(_ entry: SummaryEngineEntry) -> String? {
        (try? Data(contentsOf: mismatchMarker(for: entry))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Bytes already downloaded for a paused engine download.
    public func partialBytes(_ entry: SummaryEngineEntry) -> Int64 {
        (try? ModelFileDownloader.size(of: modelURL(for: entry).appendingPathExtension("partial"))) ?? 0
    }

    public func download(
        _ item: DownloadItem, catalog: [SummaryEngineEntry] = SummaryEngineCatalog.all,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let lock = try DownloadLock(directory: directory)
        defer { lock.release() }
        switch item {
        case .voice:
            // Nothing to download needs no free space.
            if isVoiceInstalled { progress(1); return }
            try checkSpace(needed: VoiceAssets.approximateBytes)
            try await ensureVoice(progress: progress)
        case .engine(let id):
            guard let entry = SummaryEngineCatalog.entry(id: id, in: catalog), case .llama(let spec) = entry.kind else {
                throw ReadAloudError.unknownEngine
            }
            let voiceBytes = isVoiceInstalled ? 0 : VoiceAssets.approximateBytes
            let partial = modelURL(for: entry).appendingPathExtension("partial")
            let already = max((try? ModelFileDownloader.size(of: partial)) ?? 0, 0)
            // A partial larger than the file starts over (`ModelFileDownloader`).
            let remaining = already > spec.download.bytes ? spec.download.bytes : spec.download.bytes - already
            let engineBytes = isInstalled(entry) ? 0 : remaining
            // Installed, not merely downloaded: a whole partial still needs its check and rename.
            if voiceBytes == 0, isInstalled(entry) { progress(1); return }
            try checkSpace(needed: voiceBytes + engineBytes)
            let total = Double(voiceBytes + spec.download.bytes)
            // A new attempt clears an old mismatch: only a new mismatch writes it again, so a later
            // failure of another kind resumes at launch as usual.
            try? FileManager.default.removeItem(at: mismatchMarker(for: entry))
            do {
                if voiceBytes > 0 {
                    try await ensureVoice { progress($0 * Double(voiceBytes) / total) }
                }
                do {
                    try await ModelFileDownloader(configuration: configuration).fetch(
                        from: urlFor(spec.download), to: modelURL(for: entry), expected: spec.download
                    ) { done in progress((Double(voiceBytes) + Double(done)) / total) }
                } catch ReadAloudError.checksumMismatch where !Task.isCancelled {
                    // Remembered across launches, with its reason: a wrong pin must not
                    // re-download 3 GB at every start. Only the file's own mismatch: the voice's
                    // failures say nothing about this engine.
                    FileManager.default.createFile(
                        atPath: mismatchMarker(for: entry).path,
                        contents: Data(ReadAloudError.checksumMismatch.localizedDescription.utf8))
                    throw ReadAloudError.checksumMismatch
                }
            } catch {
                // The user's Cancel, during the voice or the file: delete what is left while the
                // lock is still ours. (Quitting kills the process instead, and the `.partial`
                // stays for a resume.)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: partial)
                    try? FileManager.default.removeItem(at: mismatchMarker(for: entry))
                }
                throw error
            }
            try? FileManager.default.removeItem(at: mismatchMarker(for: entry))
            progress(1)
        }
    }

    private func checkSpace(needed: Int64) throws {
        guard let free = freeSpace(directory) else { return }
        // 10% margin: CoreML compiles next to the files, and the system needs room too.
        if Double(free) < Double(needed) * 1.1 { throw ReadAloudError.notEnoughSpace(neededBytes: needed) }
    }

    private func ensureVoice(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isVoiceInstalled { progress(1); return }
        let folder = VoiceAssets.folder(in: directory)
        // Without the marker the folder may hold a bundle cut off mid-download, which
        // FluidAudio would take for complete. Callers hold the lock (`download`), so this never
        // removes a folder another process is still writing.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try await installVoice(directory, progress)
            // The marker vouches for every file: without one, loading would fetch it unasked.
            guard VoiceAssets.hasAllFiles(in: directory) else { throw ReadAloudError.checksumMismatch }
        } catch {
            // The voice cannot resume: its incomplete folder goes at the failure (or the
            // Cancel), never left for FluidAudio to mistake for complete.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(VoiceAssets.completeMarker).path, contents: nil)
    }

    /// Deletes one item and whatever partial download it has. Only on the user's request.
    public func delete(_ item: DownloadItem, catalog: [SummaryEngineEntry] = SummaryEngineCatalog.all) throws {
        let lock = try DownloadLock(directory: directory)
        defer { lock.release() }
        let fm = FileManager.default
        switch item {
        case .voice:
            try? fm.removeItem(at: VoiceAssets.folder(in: directory))
        case .engine(let id):
            guard let entry = SummaryEngineCatalog.entry(id: id, in: catalog) else { throw ReadAloudError.unknownEngine }
            try? fm.removeItem(at: modelURL(for: entry).appendingPathExtension("partial"))
            try? fm.removeItem(at: mismatchMarker(for: entry))
            try? fm.removeItem(at: modelURL(for: entry))
        }
    }

    /// Bytes used by every file in the models folder.
    public func usedBytes() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    public static let availableCapacity: @Sendable (URL) -> Int64? = { url in
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// The real voice download: the pinned revision (`VoiceAssets.pinRevision`, at process
    /// start), the variant the bench measured, and both voices' styles.
    public static let fluidAudioVoiceInstall: VoiceInstaller = { directory, progress in
        try await Supertonic3ResourceDownloader.ensureModels(directory: directory, veVariant: VoiceAssets.variant) {
            progress($0.fractionCompleted * 0.98)
        }
        for voice in VoiceCatalog.all {
            try await Supertonic3ResourceDownloader.downloadVoiceStyle(voice.style, directory: directory)
        }
        progress(1)
    }
}
