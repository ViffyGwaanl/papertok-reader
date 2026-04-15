import Testing
import Foundation
@testable import PTAIServices

@Suite("MaxTokensStrategy")
struct MaxTokensStrategyTests {
    @Test("user override takes precedence")
    func userOverrideTakesPrecedence() {
        let s = MaxTokensStrategy()
        let value = s.resolve(
            userOverride: 2_000,
            modelMaxOutput: 8_192,
            contextWindow: 128_000,
            estimatedPromptTokens: 500
        )
        #expect(value == 2_000)
    }

    @Test("user override clamped to model max output")
    func userOverrideClampedToModelMaxOutput() {
        let s = MaxTokensStrategy()
        let value = s.resolve(
            userOverride: 50_000,
            modelMaxOutput: 8_192,
            contextWindow: 128_000,
            estimatedPromptTokens: 500
        )
        #expect(value == 8_192)
    }

    @Test("without override uses contextWindow minus prompt minus margin")
    func withoutOverrideUsesContextWindowMinusPromptMinusMargin() {
        let s = MaxTokensStrategy(safetyMargin: 256)
        let value = s.resolve(
            userOverride: nil,
            modelMaxOutput: 100_000,
            contextWindow: 10_000,
            estimatedPromptTokens: 4_000
        )
        #expect(value == 10_000 - 4_000 - 256)
    }

    @Test("never returns zero or negative")
    func neverReturnsZeroOrNegative() {
        let s = MaxTokensStrategy(safetyMargin: 256)
        let value = s.resolve(
            userOverride: nil,
            modelMaxOutput: 8_192,
            contextWindow: 1_000,
            estimatedPromptTokens: 5_000
        )
        #expect(value >= 1)
    }

    @Test("respects model max output cap when headroom exceeds it")
    func respectsModelMaxOutputCap() {
        let s = MaxTokensStrategy(safetyMargin: 256)
        let value = s.resolve(
            userOverride: nil,
            modelMaxOutput: 4_096,
            contextWindow: 200_000,
            estimatedPromptTokens: 1_000
        )
        #expect(value == 4_096)
    }

    @Test("safety margin is applied")
    func safetyMarginIsApplied() {
        let wide = MaxTokensStrategy(safetyMargin: 0)
        let tight = MaxTokensStrategy(safetyMargin: 1_000)
        let a = wide.resolve(userOverride: nil, modelMaxOutput: 100_000, contextWindow: 10_000, estimatedPromptTokens: 1_000)
        let b = tight.resolve(userOverride: nil, modelMaxOutput: 100_000, contextWindow: 10_000, estimatedPromptTokens: 1_000)
        #expect(a - b == 1_000)
    }

    @Test("user override with zero or negative falls through to formula")
    func nonPositiveUserOverrideIsIgnored() {
        let s = MaxTokensStrategy(safetyMargin: 256)
        let value = s.resolve(
            userOverride: 0,
            modelMaxOutput: 8_192,
            contextWindow: 10_000,
            estimatedPromptTokens: 1_000
        )
        #expect(value == 8_192)
    }
}
