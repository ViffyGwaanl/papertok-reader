import Foundation
import PTCore

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
        case .authenticationFailed(let msg):
            return String(
                format: AppLocalization.string(
                    "errors.ai.authentication_failed_format",
                    value: "Authentication failed: %@"
                ),
                locale: .autoupdatingCurrent,
                msg
            )
        case .rateLimited:
            return AppLocalization.string("errors.ai.rate_limited", value: "Rate limit reached")
        case .modelNotFound(let model):
            return String(
                format: AppLocalization.string(
                    "errors.ai.model_not_found_format",
                    value: "Model not found: %@"
                ),
                locale: .autoupdatingCurrent,
                model
            )
        case .contextLengthExceeded(let maxTokens):
            return String(
                format: AppLocalization.string(
                    "errors.ai.context_length_exceeded_format",
                    value: "Context length exceeded (%d)"
                ),
                locale: .autoupdatingCurrent,
                maxTokens
            )
        case .contentFiltered:
            return AppLocalization.string("errors.ai.content_filtered", value: "Content filtered")
        case .serverError(let statusCode, let message):
            return String(
                format: AppLocalization.string(
                    "errors.ai.server_error_format",
                    value: "Server error %d: %@"
                ),
                locale: .autoupdatingCurrent,
                statusCode,
                message ?? ""
            )
        case .streamingFailed(let error):
            return String(
                format: AppLocalization.string(
                    "errors.ai.streaming_failed_format",
                    value: "Streaming failed: %@"
                ),
                locale: .autoupdatingCurrent,
                error.localizedDescription
            )
        case .unsupportedCapability(let capability):
            return String(
                format: AppLocalization.string(
                    "errors.ai.unsupported_capability_format",
                    value: "Unsupported: %@"
                ),
                locale: .autoupdatingCurrent,
                capability.rawValue
            )
        }
    }
}
