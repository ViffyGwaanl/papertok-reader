import Foundation

public enum ModelContextWindowCatalog {
    public static let fallback: (contextWindow: Int, maxOutput: Int) = (8_192, 4_096)

    public static func limits(for modelId: String) -> (contextWindow: Int, maxOutput: Int) {
        let id = modelId.lowercased()

        if id.hasPrefix("gpt-4o") || id.hasPrefix("gpt-4.1") || id.hasPrefix("gpt-4-turbo") {
            return (128_000, 16_384)
        }
        if id.hasPrefix("gpt-3.5-turbo") {
            return (16_385, 4_096)
        }
        if id.hasPrefix("claude-3-5-sonnet") || id.hasPrefix("claude-3.5-sonnet") || id.hasPrefix("claude-sonnet-4") {
            return (200_000, 8_192)
        }
        if id.hasPrefix("claude-3-5-haiku") || id.hasPrefix("claude-3.5-haiku") {
            return (200_000, 8_192)
        }
        if id.hasPrefix("claude-3-opus") {
            return (200_000, 4_096)
        }
        if id.hasPrefix("gemini-2.5-flash") {
            return (1_000_000, 65_536)
        }
        if id.hasPrefix("gemini-2.0-flash") || id.hasPrefix("gemini-2.5-pro") ||
           id.hasPrefix("gemini-1.5-pro") || id.hasPrefix("gemini-1.5-flash") {
            return (1_000_000, 8_192)
        }
        return fallback
    }
}
