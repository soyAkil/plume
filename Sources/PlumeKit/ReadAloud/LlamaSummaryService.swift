import Foundation
import llama

/// A GGUF model run in process by llama.cpp.
///
/// Every llama.cpp call runs on one serial queue, never Swift's cooperative pool:
/// `llama_decode` blocks for seconds on a long selection. A batch running on the GPU
/// cannot be interrupted (the abort callback only works on the CPU), so the selection is
/// read in 512-token batches and cancellation is checked between them.
public final class LlamaSummaryService: SummaryService, @unchecked Sendable {
    public let entry: SummaryEngineEntry
    private let spec: LlamaModelSpec
    private let modelURL: URL
    private let queue = DispatchQueue(label: "studio.brigode.plume.llama", qos: .userInitiated)

    // Touched only on `queue`.
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampling = Sampling(topK: 40, topP: 0.95, minP: 0.05, temperature: 0.3)

    /// Tokens kept free for the summary (the longest budget is 8 sentences).
    static let outputReserve = 1024
    static let batchSize: Int32 = 512

    /// Plume's log, set by the app; llama.cpp warnings and errors only, which carry no text.
    /// Set it once at process start, before any load: llama.cpp threads read it unsynchronized.
    nonisolated(unsafe) public static var log: (@Sendable (String) -> Void)?

    private static let backend: Void = {
        llama_log_set({ level, text, _ in
            guard let text, let line = LlamaSummaryService.logLine(level: level, text: String(cString: text)) else { return }
            LlamaSummaryService.log?(line)
        }, nil)
        llama_backend_init()
    }()

    /// Warnings and errors only. CONT continues any level (the load progress is INFO plus a
    /// hundred CONT dots), so it is dropped too.
    static func logLine(level: ggml_log_level, text: String) -> String? {
        guard level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    public init(entry: SummaryEngineEntry, modelURL: URL) {
        self.entry = entry
        switch entry.kind {
        case .llama(let spec): self.spec = spec
        }
        self.modelURL = modelURL
    }

    /// Every queued block holds `self`, so this runs only once no llama.cpp call is pending.
    deinit {
        if let context {
            llama_synchronize(context)
            llama_free(context)
        }
        if let model { llama_model_free(model) }
    }

    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    public var isLoaded: Bool {
        get async { (try? await onQueue { self.model != nil }) ?? false }
    }

    public var inputBudget: Int {
        get async { spec.contextTokens - Self.outputReserve }
    }

    public func load() async throws {
        try await onQueue { try self.loadOnQueue() }
    }

    private func loadOnQueue() throws {
        guard model == nil else { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw ReadAloudError.engineNotInstalled }
        // After the file check: starting the backend takes seconds (Metal), for nothing if no model.
        _ = Self.backend
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let loaded = llama_model_load_from_file(modelURL.path, modelParams) else { throw ReadAloudError.loadFailed }
        // llama.cpp would silently fall back to ChatML for a model without a template.
        if case .embedded = spec.promptFormat, llama_model_chat_template(loaded, nil) == nil {
            llama_model_free(loaded)
            throw ReadAloudError.noChatTemplate
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(spec.contextTokens)
        contextParams.n_batch = UInt32(Self.batchSize)
        contextParams.n_ubatch = UInt32(Self.batchSize)
        // The C default (true) allocates a full-size sliding-window cache: too much for 8 GB Macs.
        contextParams.swa_full = false
        contextParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        guard let created = llama_init_from_model(loaded, contextParams) else {
            llama_model_free(loaded)
            throw ReadAloudError.loadFailed
        }
        model = loaded
        context = created
        vocab = llama_model_get_vocab(loaded)
        sampling = Sampling.resolve(metadata: { Self.metadata(loaded, $0) }, temperature: spec.temperature)
    }

    private static func metadata(_ model: OpaquePointer, _ key: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard llama_model_meta_val_str(model, key, &buffer, buffer.count) >= 0 else { return nil }
        return String(cString: buffer)
    }

    public func countTokens(_ text: String) async throws -> Int {
        try await onQueue {
            guard self.vocab != nil else { throw ReadAloudError.loadFailed }
            return self.tokenize(text, addSpecial: false, parseSpecial: false).count
        }
    }

    public func unload() async {
        _ = try? await onQueue {
            if let context = self.context {
                // `llama_decode` returns before the GPU is done; a stopped read leaves work in flight.
                llama_synchronize(context)
                llama_free(context)
            }
            if let model = self.model { llama_model_free(model) }
            self.context = nil
            self.model = nil
            self.vocab = nil
        }
    }

    public func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = CancelFlag()
            continuation.onTermination = { _ in cancelled.set() }
            queue.async {
                do {
                    try self.generate(request, cancelled: cancelled) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func generate(_ request: SummaryRequest, cancelled: CancelFlag, emit: (SummaryEvent) -> Void) throws {
        guard let context, let vocab else { throw ReadAloudError.loadFailed }
        // Qwen3.5 keeps recurrent state, and a stopped read can leave it half-written,
        // with its last decode still running on the GPU.
        llama_synchronize(context)
        llama_memory_clear(llama_get_memory(context), true)

        let pieces = try PromptRenderer.pieces(for: request, format: spec.promptFormat, applyTemplate: applyEmbeddedTemplate)
        var tokens: [llama_token] = []
        for (index, piece) in pieces.enumerated() {
            tokens += tokenize(piece.text, addSpecial: index == 0, parseSpecial: !piece.isSelection)
        }
        let maxTokens = 60 * request.maxSentences + 100
        guard tokens.count + maxTokens <= spec.contextTokens else { throw ReadAloudError.inputTooLong }

        var position = 0
        while position < tokens.count {
            if cancelled.isSet { throw CancellationError() }
            let count = min(Int(Self.batchSize), tokens.count - position)
            try decode(&tokens, from: position, count: count, context: context)
            // `llama_decode` only queues the batch on the GPU: wait for it, so progress reports
            // the reading itself and a stop takes effect after at most this batch.
            llama_synchronize(context)
            position += count
            emit(.readingInput(fraction: Double(position) / Double(tokens.count)))
        }

        let sampler = makeSampler()
        defer { llama_sampler_free(sampler) }
        var text = UTF8Accumulator()
        for step in 0..<maxTokens {
            if cancelled.isSet { break }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let piece = text.append(bytes(of: token))
            if !piece.isEmpty { emit(.text(piece)) }
            // The last token is never sampled from: no need to decode it.
            if step == maxTokens - 1 { break }
            var single = [token]
            try decode(&single, from: 0, count: 1, context: context)
        }
        let rest = text.finish()
        if !rest.isEmpty { emit(.text(rest)) }
    }

    private func decode(_ tokens: inout [llama_token], from start: Int, count: Int, context: OpaquePointer) throws {
        let status = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress! + start, Int32(count)))
        }
        guard status == 0 else { throw ReadAloudError.decodeFailed }
    }

    private func makeSampler() -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(sampling.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(sampling.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(sampling.minP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> [llama_token] {
        let length = Int32(text.utf8.count)
        let needed = -llama_tokenize(vocab, text, length, nil, 0, addSpecial, parseSpecial)
        guard needed > 0 else { return [] }
        var tokens = [llama_token](repeating: 0, count: Int(needed))
        let written = llama_tokenize(vocab, text, length, &tokens, needed, addSpecial, parseSpecial)
        return Array(tokens.prefix(Int(max(written, 0))))
    }

    /// Special tokens are rendered as text, so reasoning markers reach the cleaner instead
    /// of vanishing and leaving the thoughts to be spoken.
    private func bytes(of token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        return buffer.prefix(Int(max(count, 0))).map { UInt8(bitPattern: $0) }
    }

    private func applyEmbeddedTemplate(system: String, user: String) throws -> String {
        guard let model, let template = llama_model_chat_template(model, nil) else { throw ReadAloudError.noChatTemplate }
        return try Self.applyTemplate(String(cString: template), system: system, user: user)
    }

    /// llama.cpp's C formatter on a template string: no model needed, so a test can check that
    /// it recognizes a catalog model's template.
    static func applyTemplate(_ template: String, system: String, user: String) throws -> String {
        let texts: [String] = ["system", system, "user", user]
        let strings = texts.map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        var messages = [
            llama_chat_message(role: strings[0], content: strings[1]),
            llama_chat_message(role: strings[2], content: strings[3]),
        ]
        var capacity = Int32(2 * (system.utf8.count + user.utf8.count) + 4096)
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var length = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, capacity)
        guard length >= 0 else { throw ReadAloudError.unsupportedTemplate }
        if length > capacity {
            capacity = length
            buffer = [CChar](repeating: 0, count: Int(capacity))
            length = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, capacity)
        }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Set by the consumer when it stops iterating, read on the llama.cpp queue.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
