import CryptoKit
import FluidAudio
import Foundation
import Testing
@testable import PlumeKit

/// Serves canned responses per host, so parallel tests never share one.
final class StubProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)
    nonisolated(unsafe) static var handlers: [String: (handler: Handler, delay: TimeInterval)] = [:]
    static let lock = NSLock()
    private let stopped = CancelFlag()

    /// `delay` answers later from another queue, never blocking the shared loading thread.
    static func register(_ host: String, delay: TimeInterval = 0, _ handler: @escaping Handler) {
        lock.withLock { handlers[host] = (handler, delay) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let entry = Self.lock.withLock({ Self.handlers[request.url?.host ?? ""] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let answer = { [self] in
            guard !stopped.isSet else { return }
            let (status, headers, body) = entry.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if entry.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + entry.delay, execute: answer)
        } else {
            answer()
        }
    }
    override func stopLoading() { stopped.set() }
}

@Suite("Read-aloud models")
struct ReadAloudModelsTests {
    let body = Data((0..<1_000).map { UInt8($0 % 251) })
    let host = "models-\(UUID().uuidString.lowercased()).invalid"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")

    var entry: SummaryEngineEntry {
        let sha = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return SummaryEngineEntry(
            id: "test-engine", name: "Test", blurb: "Faster", tier: .fast,
            license: EngineLicense(name: "MIT", url: URL(string: "https://example.com")!),
            kind: .llama(LlamaModelSpec(
                download: ModelDownload(repo: "test/repo", revision: String(repeating: "a", count: 40), file: "test.gguf", bytes: Int64(body.count), sha256: sha),
                promptFormat: .explicit(template: "{system}{user}"), contextTokens: 4096, temperature: 0.3,
                reasoningMarkers: [ReasoningMarkers(open: "<think>", close: "</think>")])))
    }

    func models(freeSpace: Int64? = 1 << 40, installVoice: ReadAloudModels.VoiceInstaller? = nil) -> ReadAloudModels {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let host = self.host
        return ReadAloudModels(
            directory: folder, configuration: configuration,
            urlFor: { URL(string: "https://\(host)/\($0.file)")! },
            freeSpace: { _ in freeSpace },
            installVoice: installVoice ?? { directory, progress in
                try FakeVoiceFiles.write(in: directory)
                progress(1)
            })
    }

    func serveWhole() {
        let body = self.body
        StubProtocol.register(host) { _ in (200, ["Content-Length": "\(body.count)"], body) }
    }

    /// A real server answers 416 to a range starting at or past the end.
    func serveWholeRefusingRanges() {
        let body = self.body
        StubProtocol.register(host) { request in
            request.value(forHTTPHeaderField: "Range") == nil ? (200, [:], body) : (416, [:], Data())
        }
    }

    func writePartial(_ data: Data, for models: ReadAloudModels) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: models.modelURL(for: entry).appendingPathExtension("partial"))
    }

    @Test func downloadingAnEngineInstallsTheVoiceFirst() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models()
        let fractions = Fractions()
        try await models.download(.engine(entry.id), catalog: [entry]) { fractions.append($0) }
        #expect(models.isVoiceInstalled)
        #expect(models.isInstalled(entry))
        #expect(try Data(contentsOf: models.modelURL(for: entry)) == body)
        #expect(fractions.values == fractions.values.sorted())
        #expect(fractions.values.last == 1)
    }

    @Test func resumesWithARangeRequest() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let body = self.body
        StubProtocol.register(host) { request in
            guard let range = request.value(forHTTPHeaderField: "Range") else { return (200, [:], body) }
            #expect(range == "bytes=400-")
            return (206, ["Content-Range": "bytes 400-999/1000"], body.subdata(in: 400..<1000))
        }
        let models = models()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try body.prefix(400).write(to: models.modelURL(for: entry).appendingPathExtension("partial"))
        #expect(models.partialBytes(entry) == 400)
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(try Data(contentsOf: models.modelURL(for: entry)) == body)
    }

    @Test func restartsWhenTheServerIgnoresTheRange() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 400).write(to: models.modelURL(for: entry).appendingPathExtension("partial"))
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(try Data(contentsOf: models.modelURL(for: entry)) == body)
    }

    /// Review focus: a 200 with the wrong bytes of the right size installs nothing.
    @Test func aWrongFileIsRejectedAndRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        StubProtocol.register(host) { _ in (200, [:], Data(repeating: 0x3C, count: 1_000)) }
        let models = models()
        await #expect(throws: ReadAloudError.checksumMismatch) {
            try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        }
        #expect(!models.isInstalled(entry))
        #expect(!FileManager.default.fileExists(atPath: models.modelURL(for: entry).appendingPathExtension("partial").path))
        #expect(models.checksumMismatchMessage(entry) == ReadAloudError.checksumMismatch.localizedDescription)
        // A new attempt that fails differently clears the mark: it resumes at launch as usual.
        StubProtocol.register(host) { _ in (503, [:], Data()) }
        await #expect(throws: ReadAloudError.httpStatus(503)) {
            try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        }
        #expect(models.checksumMismatchMessage(entry) == nil)
        // A good download leaves no mark either.
        serveWhole()
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(models.checksumMismatchMessage(entry) == nil)
    }

    @Test func refusesWithoutEnoughSpace() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models(freeSpace: 10)
        await #expect(throws: ReadAloudError.notEnoughSpace(neededBytes: VoiceAssets.approximateBytes + 1_000)) {
            try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        }
        #expect(!models.isVoiceInstalled)
    }

    @Test func oneDownloadAtATime() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models()
        let held = try DownloadLock(directory: folder)
        await #expect(throws: ReadAloudError.downloadRunning) {
            try await models.download(.voice) { _ in }
        }
        held.release()
        try await models.download(.voice) { _ in }
        #expect(models.isVoiceInstalled)
    }

    @Test func anIncompleteVoiceIsRedownloadedFromScratch() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let stale = VoiceAssets.folder(in: folder).appendingPathComponent("weight.bin.partial")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: stale.path, contents: Data(count: 5))
        try await models().download(.voice) { _ in }
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(VoiceAssets.isInstalled(in: folder))
    }

    /// Cancel is the running task's cancellation: it deletes what it left while it still holds
    /// the lock (a separate "discard" could never take the lock during the download).
    @Test func cancellingDeletesThePartialFile() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let body = self.body
        StubProtocol.register(host, delay: 2) { _ in (200, [:], body) }
        let entry = self.entry
        let models = models()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = models.modelURL(for: entry).appendingPathExtension("partial")
        try Data(count: 400).write(to: partial)
        let task = Task { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(models.partialBytes(entry) == 0)
        #expect(!models.isInstalled(entry))
        _ = try DownloadLock(directory: folder)  // released
    }

    /// A failure during the voice part of an engine download: the voice is absent (folder
    /// gone), the engine has nothing on disk yet and can be resumed later.
    @Test func aVoiceFailureLeavesNoVoiceFolder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models(installVoice: { directory, _ in
            let voice = VoiceAssets.folder(in: directory)
            try FileManager.default.createDirectory(at: voice, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: voice.appendingPathComponent("weight.bin.partial").path, contents: Data(count: 5))
            throw URLError(.networkConnectionLost)
        })
        await #expect(throws: URLError.self) { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: VoiceAssets.folder(in: folder).path))
        #expect(!models.isVoiceInstalled)
        #expect(!models.isInstalled(entry))
    }

    /// An installer that returns without every file (the repository changed under the pin):
    /// no marker, so loading never fetches the rest on its own.
    @Test func aVoiceMissingAFileIsNotMarkedInstalled() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let models = models(installVoice: { directory, progress in
            try FakeVoiceFiles.write(in: directory)
            try FileManager.default.removeItem(at: VoiceAssets.styleURL(.m2, in: directory))
            progress(1)
        })
        await #expect(throws: ReadAloudError.checksumMismatch) { try await models.download(.voice) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: VoiceAssets.folder(in: folder).path))
        #expect(!models.isVoiceInstalled)
    }

    /// Quitting during the checksum pass leaves a whole `.partial`: no request, just the check.
    @Test func aCompletePartialIsVerifiedWithoutARequest() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWholeRefusingRanges()
        let models = models()
        try writePartial(body, for: models)
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(try Data(contentsOf: models.modelURL(for: entry)) == body)
        #expect(models.partialBytes(entry) == 0)
    }

    /// The usual case of a quit during the checksum pass: the voice is installed by then, so
    /// nothing is left to download, yet the partial still needs its check and its rename.
    @Test func aCompletePartialIsVerifiedWhenTheVoiceIsInstalled() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWholeRefusingRanges()
        let models = models()
        try FakeVoiceFiles.write(in: folder)
        FileManager.default.createFile(atPath: VoiceAssets.folder(in: folder).appendingPathComponent(VoiceAssets.completeMarker).path, contents: nil)
        try writePartial(body, for: models)
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(models.isInstalled(entry))
        #expect(models.partialBytes(entry) == 0)
        #expect(models.checksumMismatchMessage(entry) == nil)
    }

    @Test func aPartialLargerThanTheFileStartsOver() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWholeRefusingRanges()
        let models = models()
        try writePartial(Data(count: 1_500), for: models)
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        #expect(try Data(contentsOf: models.modelURL(for: entry)) == body)
    }

    /// A body that ends early without a network error is a blip, not a damaged file: what
    /// arrived stays for a resume, and nothing blocks the resume at launch.
    @Test func aBodyCutShortStaysResumable() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let half = body.prefix(500)
        StubProtocol.register(host) { _ in (200, [:], half) }
        let models = models()
        await #expect(throws: URLError.self) { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        #expect(models.partialBytes(entry) == 500)
        #expect(models.checksumMismatchMessage(entry) == nil)
        #expect(!models.isInstalled(entry))
    }

    /// A server sending more than the pinned size stops at once instead of filling the disk.
    @Test func aBodyLongerThanTheFileIsRejected() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let longer = body + Data(count: 500)
        StubProtocol.register(host) { _ in (200, [:], longer) }
        let models = models()
        let fractions = Fractions()
        await #expect(throws: ReadAloudError.checksumMismatch) {
            try await models.download(.engine(entry.id), catalog: [entry]) { fractions.append($0) }
        }
        #expect(fractions.values.allSatisfy { $0 <= 1 })  // nothing written past the size
        #expect(!models.isInstalled(entry))
        #expect(models.partialBytes(entry) == 0)
        #expect(models.checksumMismatchMessage(entry) != nil)
    }

    /// A captive portal's page announces its own size: refused before a byte is written, and
    /// the earlier partial stays as it was for a resume.
    @Test func aResponseOfTheWrongSizeLeavesThePartialUntouched() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = Data("<html>Log in to the Wi-Fi</html>".utf8)
        StubProtocol.register(host) { _ in (200, ["Content-Length": "\(page.count)"], page) }
        let models = models()
        try writePartial(body.prefix(400), for: models)
        let error = await #expect(throws: URLError.self) { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        #expect(error?.code == .badServerResponse)
        #expect(try Data(contentsOf: models.modelURL(for: entry).appendingPathExtension("partial")) == body.prefix(400))
        #expect(models.checksumMismatchMessage(entry) == nil)
    }

    /// Another file's range, or not the range asked for.
    @Test(arguments: ["bytes 400-999/2000", "bytes 0-999/1000"])
    func aWrongContentRangeLeavesThePartialUntouched(contentRange: String) async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let rest = body.subdata(in: 400..<1000)
        StubProtocol.register(host) { _ in (206, ["Content-Range": contentRange], rest) }
        let models = models()
        try writePartial(body.prefix(400), for: models)
        let error = await #expect(throws: URLError.self) { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        #expect(error?.code == .badServerResponse)
        #expect(try Data(contentsOf: models.modelURL(for: entry).appendingPathExtension("partial")) == body.prefix(400))
        #expect(models.checksumMismatchMessage(entry) == nil)
    }

    /// Cancel during the voice part of an engine download removes the engine's earlier
    /// partial too: the user cancelled the engine, it must not show as paused.
    @Test func cancellingDuringTheVoiceDeletesTheEnginePartial() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let entry = self.entry
        let models = models(installVoice: { directory, _ in
            try FileManager.default.createDirectory(at: VoiceAssets.folder(in: directory), withIntermediateDirectories: true)
            try await Task.sleep(for: .seconds(60))  // until cancelled
        })
        try writePartial(Data(count: 400), for: models)
        let task = Task { try await models.download(.engine(entry.id), catalog: [entry]) { _ in } }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(models.partialBytes(entry) == 0)
        #expect(!FileManager.default.fileExists(atPath: VoiceAssets.folder(in: folder).path))
        _ = try DownloadLock(directory: folder)  // released
    }

    /// Nothing to download needs no free space.
    @Test func anInstalledItemNeedsNoSpace() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let models = models(freeSpace: 10)
        try FakeVoiceFiles.write(in: folder)
        FileManager.default.createFile(atPath: VoiceAssets.folder(in: folder).appendingPathComponent(VoiceAssets.completeMarker).path, contents: nil)
        try body.write(to: models.modelURL(for: entry))
        try await models.download(.voice) { _ in }
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
    }

    @Test func deletingRemovesOnlyItsItem() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        serveWhole()
        let models = models()
        try await models.download(.engine(entry.id), catalog: [entry]) { _ in }
        try models.delete(.engine(entry.id), catalog: [entry])
        #expect(!models.isInstalled(entry))
        #expect(models.isVoiceInstalled)
        try models.delete(.voice)
        #expect(!models.isVoiceInstalled)
    }
}

final class Fractions: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func append(_ value: Double) { lock.withLock { stored.append(value) } }
    var values: [Double] { lock.withLock { stored } }
}

/// The voice files a real install leaves (FluidAudio's list for the pinned variant and both
/// voices' styles), empty, without the completion marker.
enum FakeVoiceFiles {
    static func write(in modelsDirectory: URL) throws {
        let folder = VoiceAssets.folder(in: modelsDirectory)
        let files = ModelNames.Supertonic3.requiredFiles(veVariant: VoiceAssets.variant).map { folder.appendingPathComponent($0) }
            + [Supertonic3Voice.f1, .m2].map { VoiceAssets.styleURL($0, in: modelsDirectory) }
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: Data(count: 10))
        }
    }
}
