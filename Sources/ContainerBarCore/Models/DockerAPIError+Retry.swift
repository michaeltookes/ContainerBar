import Foundation

extension DockerAPIError {
    /// Whether this error is transient and can be retried
    public var isTransient: Bool {
        switch self {
        case .connectionFailed, .networkTimeout, .serverError, .sshConnectionFailed, .tlsConnectionFailed:
            return true
        case .unauthorized, .notFound, .invalidConfiguration, .invalidURL, .socketNotFound:
            return false
        case .conflict, .unexpectedStatus, .invalidResponse, .decodingError, .notImplemented:
            return false
        }
    }
}
