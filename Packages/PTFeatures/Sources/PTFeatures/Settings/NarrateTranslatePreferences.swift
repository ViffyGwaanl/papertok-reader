import Foundation
import PTCore

/// Preferences for narration (TTS) and translation settings.
///
/// Backed by `UserDefaults` keys prefixed with `narr_trans_`.
public struct NarrateTranslatePreferences: Sendable {
    public let targetLanguage: String
    public let translationUseChatModel: Bool
    public let translationModelId: String
    public let narrationBackend: String
    public let narrationVoiceId: String
    public let narrationSpeed: Double

    private static let targetLanguageKey = "narr_trans_target_language"
    private static let translationUseChatModelKey = "narr_trans_use_chat_model"
    private static let translationModelIdKey = "narr_trans_model_id"
    private static let narrationBackendKey = "narr_trans_backend"
    private static let narrationVoiceIdKey = "narr_trans_voice_id"
    private static let narrationSpeedKey = "narr_trans_speed"

    /// Supported target languages for translation.
    public static let supportedLanguages: [(id: String, name: String)] = [
        ("zh-Hans", "Simplified Chinese"),
        ("zh-Hant", "Traditional Chinese"),
        ("en", "English"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
    ]

    /// Available TTS backend identifiers.
    public static let availableBackends: [(id: String, name: String)] = [
        ("system", "System (On-device)"),
        ("openai", "OpenAI TTS"),
        ("azure", "Azure Neural TTS"),
    ]

    public static func load(defaults: UserDefaults = AppConfig.groupDefaults) -> NarrateTranslatePreferences {
        let targetLanguage = defaults.string(forKey: targetLanguageKey) ?? "zh-Hans"
        let useChatModel = defaults.object(forKey: translationUseChatModelKey) != nil
            ? defaults.bool(forKey: translationUseChatModelKey)
            : true
        let modelId = defaults.string(forKey: translationModelIdKey) ?? ""
        let backend = defaults.string(forKey: narrationBackendKey) ?? AppConfig.Defaults.defaultTTSBackend
        let voiceId = defaults.string(forKey: narrationVoiceIdKey) ?? ""
        let speed = defaults.object(forKey: narrationSpeedKey) != nil
            ? defaults.double(forKey: narrationSpeedKey)
            : 1.0
        return NarrateTranslatePreferences(
            targetLanguage: targetLanguage,
            translationUseChatModel: useChatModel,
            translationModelId: modelId,
            narrationBackend: backend,
            narrationVoiceId: voiceId,
            narrationSpeed: max(0.5, min(2.0, speed))
        )
    }

    public static func persistTargetLanguage(_ value: String, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: targetLanguageKey)
    }

    public static func persistTranslationUseChatModel(_ value: Bool, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: translationUseChatModelKey)
    }

    public static func persistTranslationModelId(_ value: String, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: translationModelIdKey)
    }

    public static func persistNarrationBackend(_ value: String, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: narrationBackendKey)
    }

    public static func persistNarrationVoiceId(_ value: String, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(value, forKey: narrationVoiceIdKey)
    }

    public static func persistNarrationSpeed(_ value: Double, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(max(0.5, min(2.0, value)), forKey: narrationSpeedKey)
    }
}
