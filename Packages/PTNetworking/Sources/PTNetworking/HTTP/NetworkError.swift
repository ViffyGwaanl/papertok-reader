import Foundation
import PTCore

public enum NetworkError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case noData
    case timeout
    case cancelled
    case connectionLost
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return AppLocalization.format(
                "errors.network.invalid_url_format",
                "Invalid URL: %@",
                path
            )
        case .httpError(let statusCode, _):
            return AppLocalization.format(
                "errors.network.http_error_format",
                "HTTP error %d",
                statusCode
            )
        case .decodingFailed(let error):
            return AppLocalization.format(
                "errors.network.decoding_failed_format",
                "Decoding failed: %@",
                error.localizedDescription
            )
        case .noData:
            return AppLocalization.string("errors.network.no_data", value: "No data received")
        case .timeout:
            return AppLocalization.string("errors.network.timeout", value: "Request timed out")
        case .cancelled:
            return AppLocalization.string("errors.network.cancelled", value: "Request was cancelled")
        case .connectionLost:
            return AppLocalization.string("errors.network.connection_lost", value: "Network connection lost")
        case .unknown(let error):
            return AppLocalization.format(
                "errors.network.unknown_format",
                "Unknown error: %@",
                error.localizedDescription
            )
        }
    }

    /// Map a URLError to a typed NetworkError.
    static func from(_ error: Error) -> NetworkError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            case .networkConnectionLost, .notConnectedToInternet:
                return .connectionLost
            default:
                return .unknown(urlError)
            }
        }
        return .unknown(error)
    }
}
