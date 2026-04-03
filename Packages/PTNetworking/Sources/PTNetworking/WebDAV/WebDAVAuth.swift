import Foundation

/// Authentication method for WebDAV connections.
public enum WebDAVAuth: Sendable {
    case basic(user: String, password: String)

    /// Returns the `Authorization` header value.
    func authorizationHeader() -> String {
        switch self {
        case .basic(let user, let password):
            let credentials = "\(user):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }
}
