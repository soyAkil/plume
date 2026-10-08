import CryptoKit
import Foundation

/// Downloads one file into `<destination>.partial`, resuming with an HTTP range, then checks
/// its size and SHA-256 before renaming it.
struct ModelFileDownloader {
    let configuration: URLSessionConfiguration

    func fetch(from url: URL, to destination: URL, expected: ModelDownload, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { return }
        let partial = destination.appendingPathExtension("partial")
        var offset = (try? Self.size(of: partial)) ?? 0
        // Larger than the file: no range can fix it.
        if offset > expected.bytes {
            try? fm.removeItem(at: partial)
            offset = 0
        }
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        // Whole already (a quit during the checksum pass): a range from its end would get a 416.
        if offset < expected.bytes {
            var request = URLRequest(url: url)
            if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
            do {
                try await RangeDownload(file: partial, offset: offset, limit: expected.bytes, progress: progress)
                    .run(request, configuration: configuration)
            } catch ReadAloudError.checksumMismatch {
                try? fm.removeItem(at: partial)
                throw ReadAloudError.checksumMismatch
            }
        }
        let size = try Self.size(of: partial)
        // Cut short without a network error: a blip, so what arrived stays for a resume.
        if size < expected.bytes { throw URLError(.networkConnectionLost) }
        guard size == expected.bytes, try Self.sha256(of: partial) == expected.sha256 else {
            try? fm.removeItem(at: partial)
            throw ReadAloudError.checksumMismatch
        }
        try fm.moveItem(at: partial, to: destination)
    }

    static func size(of url: URL) throws -> Int64 {
        Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A data task appending to a file: `206` continues the partial file, `200` (the server
/// ignored the range) starts it over. More than `limit` bytes is a wrong file, stopped before
/// it fills the disk.
final class RangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let file: URL
    private var written: Int64
    private let limit: Int64
    private let progress: @Sendable (Int64) -> Void
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    init(file: URL, offset: Int64, limit: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.file = file
        self.written = offset
        self.limit = limit
        self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    self.continuation = continuation
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                    // A Cancel that came before the task existed had nothing to stop.
                    if cancelled { task.cancel() }
                }
            }
        } onCancel: {
            lock.withLock { () -> URLSessionDataTask? in
                cancelled = true
                return task
            }?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        do {
            // An announced size that is not the file's (a captive portal's page, another file)
            // fails before a byte is written: the partial stays as it was, for a resume.
            switch status {
            case 206:
                if let range = http?.value(forHTTPHeaderField: "Content-Range").flatMap(Self.contentRange),
                   range.start != written || range.total.map({ $0 != limit }) == true {
                    throw URLError(.badServerResponse)
                }
                handle = try FileHandle(forWritingTo: file)
                try handle?.seekToEnd()
            case 200:
                if response.expectedContentLength >= 0, response.expectedContentLength != limit {
                    throw URLError(.badServerResponse)
                }
                handle = try FileHandle(forWritingTo: file)
                try handle?.truncate(atOffset: 0)
                written = 0
            default:
                throw ReadAloudError.httpStatus(status)
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    /// `bytes <start>-<end>/<total>`; `total` is nil when unknown (`*`).
    static func contentRange(_ value: String) -> (start: Int64, total: Int64?)? {
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return nil }
        let rangeAndTotal = parts[1].split(separator: "/", maxSplits: 1)
        guard rangeAndTotal.count == 2, let dash = rangeAndTotal[0].firstIndex(of: "-"),
              let start = Int64(rangeAndTotal[0][..<dash])
        else { return nil }
        return (start, Int64(rangeAndTotal[1]))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do {
            if written + Int64(data.count) > limit { throw ReadAloudError.checksumMismatch }
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            progress(written)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        if let failure = failure ?? error { continuation?.resume(throwing: failure) } else { continuation?.resume() }
    }
}
