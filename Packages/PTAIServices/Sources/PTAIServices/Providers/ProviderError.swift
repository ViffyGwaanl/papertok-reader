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
            return localizedAuthenticationMessage(detail: msg)
        case .rateLimited:
            return AppLocalization.string("errors.ai.rate_limited")
        case .modelNotFound:
            return AppLocalization.string("errors.ai.model_unavailable")
        case .contextLengthExceeded:
            return AppLocalization.string("errors.ai.context_too_long")
        case .contentFiltered:
            return AppLocalization.string("errors.ai.content_filtered")
        case .serverError(let statusCode, let message):
            return localizedServerMessage(statusCode: statusCode, message: message)
        case .streamingFailed:
            return AppLocalization.string("errors.ai.streaming_interrupted")
        case .unsupportedCapability:
            return AppLocalization.string("errors.ai.unsupported_capability")
        }
    }

    private func localizedAuthenticationMessage(detail: String) -> String {
        let normalized = detail.lowercased()
        if normalized.contains("missing") || normalized.contains("not found") || normalized.contains("no api key") {
            return AppLocalization.string("errors.ai.no_api_key")
        }
        return AppLocalization.string("errors.ai.invalid_api_key")
    }

    private func localizedServerMessage(statusCode: Int, message: String?) -> String {
        switch statusCode {
        case 401, 403:
            return AppLocalization.string("errors.ai.invalid_api_key")
        case 404:
            return AppLocalization.string("errors.ai.model_unavailable")
        case 429:
            return AppLocalization.string("errors.ai.rate_limited")
        default:
            if let message, message.isEmpty == false {
                return AppLocalization.string("errors.ai.service_unavailable")
            }
            return AppLocalization.string("errors.ai.no_response")
        }
    }
}
