import Testing
import Foundation
@testable import PTAIServices

@Suite("ModelContextWindowCatalog")
struct ModelContextWindowCatalogTests {
    @Test("gpt-4o returns expected limits")
    func gpt4oReturnsExpectedLimits() {
        let (cw, out) = ModelContextWindowCatalog.limits(for: "gpt-4o")
        #expect(cw == 128_000)
        #expect(out == 16_384)
    }

    @Test("claude sonnet returns expected limits")
    func claudeReturnsExpectedLimits() {
        let (cw, out) = ModelContextWindowCatalog.limits(for: "claude-3-5-sonnet-20241022")
        #expect(cw == 200_000)
        #expect(out == 8_192)
    }

    @Test("gemini flash returns expected limits")
    func geminiFlashReturnsExpectedLimits() {
        let (cw, out) = ModelContextWindowCatalog.limits(for: "gemini-2.0-flash")
        #expect(cw == 1_000_000)
        #expect(out == 8_192)
        let (cw2, out2) = ModelContextWindowCatalog.limits(for: "gemini-2.5-flash")
        #expect(cw2 == 1_000_000)
        #expect(out2 == 65_536)
    }

    @Test("unknown model returns fallback")
    func unknownModelReturnsFallback() {
        let limits = ModelContextWindowCatalog.limits(for: "totally-unknown-model")
        #expect(limits.contextWindow == 8_192)
        #expect(limits.maxOutput == 4_096)
    }

    @Test("prefix match handles versioned model ids")
    func prefixMatchHandlesVersionedModelIds() {
        let (cw, _) = ModelContextWindowCatalog.limits(for: "gpt-4o-2024-11-20")
        #expect(cw == 128_000)
        let (cw2, _) = ModelContextWindowCatalog.limits(for: "claude-sonnet-4-20250514")
        #expect(cw2 == 200_000)
    }
}
