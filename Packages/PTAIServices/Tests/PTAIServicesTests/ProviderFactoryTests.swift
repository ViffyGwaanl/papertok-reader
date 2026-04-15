import Foundation
import Testing
@testable import PTAIServices

@Suite("ProviderFactory")
struct ProviderFactoryTests {

    @Test("OpenAI provider is created with default base URL")
    func makeOpenAI() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .openai,
            config: ProviderConfig(apiKey: "sk-test")
        )
        #expect(provider is OpenAIProvider)
        #expect(provider.id == "openai")
    }

    @Test("Anthropic provider is created")
    func makeAnthropic() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .anthropic,
            config: ProviderConfig(apiKey: "sk-ant-test")
        )
        #expect(provider is AnthropicProvider)
    }

    @Test("Gemini provider is created")
    func makeGemini() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .gemini,
            config: ProviderConfig(apiKey: "gk-test")
        )
        #expect(provider is GeminiProvider)
        #expect(provider.supportedCapabilities.contains(.thinking))
    }

    @Test("Volcengine provider is created")
    func makeVolcengine() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .volcengine,
            config: ProviderConfig(apiKey: "vk-test")
        )
        #expect(provider is VolcengineProvider)
    }

    @Test("Azure requires baseURL and deploymentName")
    func azureRequiresBaseURLAndDeployment() {
        #expect(throws: ProviderFactoryError.self) {
            _ = try ProviderFactory.makeProvider(
                kind: .azure,
                config: ProviderConfig(apiKey: "k")
            )
        }

        #expect(throws: ProviderFactoryError.self) {
            _ = try ProviderFactory.makeProvider(
                kind: .azure,
                config: ProviderConfig(apiKey: "k", baseURL: URL(string: "https://foo.openai.azure.com")!)
            )
        }
    }

    @Test("Azure succeeds with full config")
    func makeAzureSucceeds() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .azure,
            config: ProviderConfig(
                apiKey: "k",
                baseURL: URL(string: "https://foo.openai.azure.com")!,
                deploymentName: "gpt-4o-deploy"
            )
        )
        #expect(provider is AzureProvider)
    }

    @Test("Custom requires baseURL")
    func customRequiresBaseURL() {
        #expect(throws: ProviderFactoryError.self) {
            _ = try ProviderFactory.makeProvider(
                kind: .custom,
                config: ProviderConfig(apiKey: "k")
            )
        }
    }

    @Test("Custom succeeds with baseURL")
    func makeCustomSucceeds() throws {
        let provider = try ProviderFactory.makeProvider(
            kind: .custom,
            config: ProviderConfig(
                apiKey: "k",
                baseURL: URL(string: "https://example.com")!,
                availableModels: ["model-a"]
            )
        )
        #expect(provider is CustomProvider)
    }

    @Test("defaultModels returns non-empty for known providers")
    func defaultModelsNonEmpty() {
        #expect(!ProviderFactory.defaultModels(for: .openai).isEmpty)
        #expect(!ProviderFactory.defaultModels(for: .anthropic).isEmpty)
        #expect(!ProviderFactory.defaultModels(for: .gemini).isEmpty)
        #expect(!ProviderFactory.defaultModels(for: .volcengine).isEmpty)
    }

    @Test("displayName returns expected strings")
    func displayNames() {
        #expect(ProviderFactory.displayName(for: .openai) == "OpenAI")
        #expect(ProviderFactory.displayName(for: .gemini) == "Google Gemini")
        #expect(ProviderFactory.displayName(for: .azure) == "Azure OpenAI")
    }

    @Test("SupportedProvider covers all expected cases")
    func supportedProviderCases() {
        let all = Set(SupportedProvider.allCases.map(\.rawValue))
        #expect(all == Set([
            "openai", "anthropic", "gemini", "azure", "volcengine",
            "siliconflow", "groq", "mistral", "ollama", "deepseek", "openrouter",
            "custom",
        ]))
    }

    @Test("OpenAI-compatible built-in providers expose default base URLs and curated models")
    func openAICompatibleBuiltInsHaveDefaults() throws {
        let cases: [(SupportedProvider, String, Bool)] = [
            (.siliconflow, "https://api.siliconflow.cn", false),
            (.groq, "https://api.groq.com/openai", false),
            (.mistral, "https://api.mistral.ai", false),
            (.ollama, "http://localhost:11434", true),
            (.deepseek, "https://api.deepseek.com", false),
            (.openrouter, "https://openrouter.ai/api", false),
        ]
        for (kind, expectedBase, allowEmptyModels) in cases {
            #expect(kind.isOpenAICompatible)
            #expect(kind.defaultOpenAICompatibleBaseURL?.absoluteString == expectedBase)
            let models = ProviderFactory.defaultModels(for: kind)
            if allowEmptyModels {
                #expect(models.isEmpty)
            } else {
                #expect(models.isEmpty == false, "Provider \(kind.rawValue) must ship default models")
            }
            let client = try ProviderFactory.makeProvider(
                kind: kind,
                config: ProviderConfig(apiKey: "test")
            )
            #expect(client.id == kind.rawValue)
        }
    }

    @Test("DeepSeek reasoner model is flagged as thinking-capable")
    func deepseekReasonerIsThinkingCapable() {
        // The catalog test-suite verifies the wiring end-to-end; here we just
        // confirm the curated DeepSeek default list contains the reasoner.
        let models = ProviderFactory.defaultModels(for: .deepseek)
        #expect(models.contains("deepseek-reasoner"))
    }
}
