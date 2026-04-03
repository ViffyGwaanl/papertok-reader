import Foundation

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
            return "Invalid URL: \(path)"
        case .httpError(let statusCode, _):
            return "HTTP error \(statusCode)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .connectionLost:
            return "Network connection lost"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
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
