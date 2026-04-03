import Foundation

public struct TokenUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.totalTokens = totalTokens
    }

    public func estimateCost(inputPricePer1M: Double, outputPricePer1M: Double) -> Double {
        Double(promptTokens) * inputPricePer1M / 1_000_000 + Double(completionTokens) * outputPricePer1M / 1_000_000
    }
}
