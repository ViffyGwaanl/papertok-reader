import Foundation
import Testing
@testable import PTAIServices
@testable import PTFeatures

@Suite("AIProviderDetailView capability badges")
struct AIProviderDetailViewBadgesTests {
    @Test("model picker renders tools badge for tool-capable model")
    func modelPickerRendersToolsBadgeForToolCapableModel() {
        let badges = AIProviderDetailView.badgesForModel(provider: .openai, model: "gpt-4o")
        #expect(badges.contains(.tools))
    }

    @Test("model picker renders vision badge for vision-capable model")
    func modelPickerRendersVisionBadgeForVisionCapableModel() {
        let badges = AIProviderDetailView.badgesForModel(provider: .openai, model: "gpt-4o")
        #expect(badges.contains(.vision))
    }

    @Test("model picker renders thinking badge for thinking-capable model")
    func modelPickerRendersThinkingBadgeForThinkingCapableModel() {
        let badges = AIProviderDetailView.badgesForModel(provider: .anthropic, model: "claude-sonnet-4-20250514")
        #expect(badges.contains(.thinking))
    }

    @Test("badges omit thinking for non-thinking-capable Claude model")
    func badgesOmitThinkingForHaikuModel() {
        let badges = AIProviderDetailView.badgesForModel(provider: .anthropic, model: "claude-3-haiku-20240307")
        #expect(badges.contains(.thinking) == false)
    }

    @Test("badges omit tools for ollama")
    func badgesOmitToolsForOllama() {
        let badges = AIProviderDetailView.badgesForModel(provider: .ollama, model: "llama3.1")
        #expect(badges.contains(.tools) == false)
    }

    @Test("badges include image generation for dall-e models")
    func badgesIncludeImageGenerationForDallE() {
        let badges = AIProviderDetailView.badgesForModel(provider: .openai, model: "dall-e-3")
        #expect(badges.contains(.imageGeneration))
    }
}
