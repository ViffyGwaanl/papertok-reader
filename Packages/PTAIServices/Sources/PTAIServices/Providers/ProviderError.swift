import Foundation

public enum ProviderError: Error, Sendable, LocalizedError {
    case authenticationFailed(String)
    case rateLimited(retryAfter: TimeInterval?)
    case modelNotFound(String)
    case contextLengthExceeded(maxTokens: Int)
    case contentFiltered
    case serverError(statusCode: Int, message: String?)
    case streamingFailed(Error)
    case unsupportedCapability(ModelCapability)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .rateLimited: return "Rate limit reached"
        case .modelNotFound(let m): return "Model not found: \(m)"
        case .contextLengthExceeded(let max): return "Context length exceeded (\(max))"
        case .contentFiltered: return "Content filtered"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "")"
        case .streamingFailed(let e): return "Streaming failed: \(e.localizedDescription)"
        case .unsupportedCapability(let c): return "Unsupported: \(c.rawValue)"
        }
    }
}
