import Foundation
import PTCore
import PTAIServices

public struct AIChatRuntimePreferences {
    public enum ToolApprovalPolicy: String {
        case always
        case moderate
        case dangerous
        case never

        func requiresApproval(for riskLevel: ToolRiskLevel) -> Bool {
            switch self {
            case .always:
                return false
            case .moderate:
                return riskLevel == .moderate || riskLevel == .dangerous
            case .dangerous:
                return riskLevel == .dangerous
            case .never:
                return true
            }
        }
    }

    public let enabledToolNames: Set<String>
    public let approvalPolicy: ToolApprovalPolicy
    public let generationSettings: AIChatViewModel.ChatGenerationSettings
    public let defaultThinkingLevel: ThinkingLevel

    public static func load(
        defaults: UserDefaults,
        providerId: String,
        locale: Locale = .autoupdatingCurrent
    ) -> AIChatRuntimePreferences {
        let enabledToolNames = Set(defaults.stringArray(forKey: "ai_enabled_tools") ?? [])
        let approvalPolicy = ToolApprovalPolicy(
            rawValue: defaults.string(forKey: "ai_tool_approval_threshold") ?? ""
        ) ?? .moderate

        let defaultSettings = AIChatViewModel.ChatGenerationSettings.default
        let temperatureKey = "ai_temperature_\(providerId)"
        let maxTokensKey = "ai_max_tokens_\(providerId)"
        let topPKey = "ai_top_p_\(providerId)"
        let presencePenaltyKey = "ai_presence_penalty_\(providerId)"
        let frequencyPenaltyKey = "ai_frequency_penalty_\(providerId)"
        let stopSequencesKey = "ai_stop_sequences_\(providerId)"
        let systemPrompt = defaults.string(forKey: AppConfig.Keys.aiSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let temperature = defaults.object(forKey: temperatureKey) != nil
            ? defaults.double(forKey: temperatureKey)
            : defaultSettings.temperature
        let topP = defaults.object(forKey: topPKey) != nil
            ? defaults.double(forKey: topPKey)
            : defaultSettings.topP
        let presencePenalty = defaults.object(forKey: presencePenaltyKey) != nil
            ? defaults.double(forKey: presencePenaltyKey)
            : defaultSettings.presencePenalty
        let frequencyPenalty = defaults.object(forKey: frequencyPenaltyKey) != nil
            ? defaults.double(forKey: frequencyPenaltyKey)
            : defaultSettings.frequencyPenalty
        let maxTokens = Int(defaults.string(forKey: maxTokensKey) ?? "") ?? defaultSettings.maxTokens
        let stopSequences = parseStopSequences(defaults.string(forKey: stopSequencesKey))
        let generationSettings = AIChatViewModel.ChatGenerationSettings(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            stopSequences: stopSequences,
            systemPrompt: (systemPrompt?.isEmpty == false ? systemPrompt : nil) ?? defaultSettings.systemPrompt,
            perConversation: false
        )

        return AIChatRuntimePreferences(
            enabledToolNames: enabledToolNames,
            approvalPolicy: approvalPolicy,
            generationSettings: generationSettings,
            defaultThinkingLevel: resolveThinkingLevel(defaults: defaults, providerId: providerId)
        )
    }

    public static func persist(
        _ settings: AIChatViewModel.ChatGenerationSettings,
        defaults: UserDefaults,
        providerId: String
    ) {
        defaults.set(settings.temperature, forKey: "ai_temperature_\(providerId)")
        defaults.set(String(settings.maxTokens), forKey: "ai_max_tokens_\(providerId)")
        defaults.set(settings.topP, forKey: "ai_top_p_\(providerId)")
        defaults.set(settings.presencePenalty, forKey: "ai_presence_penalty_\(providerId)")
        defaults.set(settings.frequencyPenalty, forKey: "ai_frequency_penalty_\(providerId)")
        defaults.set(settings.stopSequences.joined(separator: "\n"), forKey: "ai_stop_sequences_\(providerId)")
        defaults.set(settings.systemPrompt, forKey: AppConfig.Keys.aiSystemPrompt)
    }

    public static func persistThinkingLevel(_ level: ThinkingLevel, defaults: UserDefaults) {
        defaults.set(level.rawValue, forKey: AppConfig.Keys.aiThinkingLevel)
    }

    public static func defaultThinkingLevel(
        defaults: UserDefaults,
        providerId: String
    ) -> ThinkingLevel {
        resolveThinkingLevel(defaults: defaults, providerId: providerId, useGlobalOverride: false)
    }

    private static func resolveThinkingLevel(
        defaults: UserDefaults,
        providerId: String,
        useGlobalOverride: Bool = true
    ) -> ThinkingLevel {
        if useGlobalOverride,
           let storedGlobal = ThinkingLevel(rawValue: defaults.string(forKey: AppConfig.Keys.aiThinkingLevel) ?? "") {
            return storedGlobal
        }

        let storedProviderLevel = defaults.string(forKey: "ai_reasoning_effort_\(providerId)") ?? "medium"
        switch storedProviderLevel {
        case "off":
            return .off
        case "minimal":
            return .minimal
        case "low":
            return .low
        case "high":
            return .high
        default:
            return .medium
        }
    }

    private static func parseStopSequences(_ raw: String?) -> [String] {
        guard let raw, raw.isEmpty == false else { return [] }
        return raw
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}
