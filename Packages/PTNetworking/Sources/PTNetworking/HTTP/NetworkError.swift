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
        case .invalidURL:
            return AppLocalization.string("errors.network.invalid_url")
        case .httpError(let statusCode, _):
            return localizedHTTPErrorMessage(for: statusCode)
        case .decodingFailed:
            return AppLocalization.string("errors.network.decoding_failed")
        case .noData:
            return AppLocalization.string("errors.network.no_data")
        case .timeout:
            return AppLocalization.string("errors.network.timeout")
        case .cancelled:
            return AppLocalization.string("errors.network.cancelled")
        case .connectionLost:
            return AppLocalization.string("errors.network.connection_lost")
        case .unknown(let error):
            return localizedUnknownMessage(for: error)
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
            case .networkConnectionLost:
                return .connectionLost
            default:
                return .unknown(urlError)
            }
        }
        return .unknown(error)
    }

    private func localizedHTTPErrorMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401:
            AppLocalization.string("errors.network.unauthorized")
        case 403:
            AppLocalization.string("errors.network.forbidden")
        case 404:
            AppLocalization.string("errors.network.not_found")
        default:
            AppLocalization.string("errors.network.server")
        }
    }

    private func localizedUnknownMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return AppLocalization.string("errors.network.server")
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return AppLocalization.string("errors.network.offline")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return AppLocalization.string("errors.network.dns")
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .serverCertificateUntrusted,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return AppLocalization.string("errors.network.tls")
        default:
            return AppLocalization.string("errors.network.server")
        }
    }
}
