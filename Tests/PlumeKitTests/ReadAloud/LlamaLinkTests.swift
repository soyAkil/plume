import Testing
import llama

/// The binary framework links and its defaults are the ones the design relies on.
@Suite("llama.cpp link")
struct LlamaLinkTests {
    @Test func theLibraryLinksWithTheExpectedDefaults() {
        let context = llama_context_default_params()
        #expect(context.n_ubatch == 512)
        #expect(context.swa_full == true)  // Plume turns it off; the default must still be what the spec says.
    }
}
