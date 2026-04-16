import Foundation
import PTCore

/// Preferences for the auto title generation feature.
///
/// Backed by `UserDefaults` keys prefixed with `ai_title_gen_`.
public struct AITitleGenerationPreferences: Sendable {
    public let isEnabled: Bool
    public let useChatModel: Bool
    public let titleModelId: String
    public let maxWords: Int

    private static let enabledKey = "ai_title_gen_enabled"
    private static let useChatModelKey = "ai_title_gen_use_chat_model"
    private static let modelIdKey = "ai_title_gen_model_id"
    private static let maxWordsKey = "ai_title_gen_max_words"

    public static func load(defaults: UserDefaults = AppConfig.groupDefaults) -> AITitleGenerationPreferences {
        let isEnabled = defaults.object(forKey: enabledKey) != nil
            ? defaults.bool(forKey: enabledKey)
            : true
        let useChatModel = defaults.object(forKey: useChatModelKey) != nil
            ? defaults.bool(forKey: useChatModelKey)
            : true
        let modelId = defaults.string(forKey: modelIdKey) ?? ""
        let maxWords = defaults.object(forKey: maxWordsKey) != nil
            ? defaults.integer(forKey: maxWordsKey)
            : 8
        return AITitleGenerationPreferences(
            isEnabled: isEnabled,
            useChatModel: useChatModel,
            titleModelId: modelId,
            maxWords: max(4, min(20, maxWords))
        )
    }

    public static func persistEnabled(_ value: Bool, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: enabledKey)
    }

    public static func persistUseChatModel(_ value: Bool, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: useChatModelKey)
    }

    public static func persistModelId(_ value: String, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: modelIdKey)
    }

    public static func persistMaxWords(_ value: Int, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(max(4, min(20, value)), forKey: maxWordsKey)
    }
}
