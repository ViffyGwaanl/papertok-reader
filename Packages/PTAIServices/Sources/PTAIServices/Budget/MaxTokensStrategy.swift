import Foundation

public struct MaxTokensStrategy: Sendable {
    public let safetyMargin: Int

    public init(safetyMargin: Int = 256) {
        self.safetyMargin = safetyMargin
    }

    public func resolve(
        userOverride: Int?,
        modelMaxOutput: Int,
        contextWindow: Int,
        estimatedPromptTokens: Int
    ) -> Int {
        let cap = max(1, modelMaxOutput)
        if let userOverride, userOverride > 0 {
            return min(userOverride, cap)
        }
        let headroom = contextWindow - estimatedPromptTokens - safetyMargin
        let bounded = min(cap, headroom)
        return max(1, bounded)
    }
}
