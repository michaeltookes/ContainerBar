import Foundation

/// Docker API error types
public enum DockerAPIError: Error, LocalizedError, Sendable {
    case connectionFailed
    case unauthorized
    case notFound(String)
    case conflict(String)
    case serverError(String)
    case invalidURL
    case invalidResponse
    case invalidConfiguration(String)
    case unexpectedStatus(Int)
    case networkTimeout
    case notImplemented(String)
    case decodingError(String)
    case socketNotFound(String)
    case sshConnectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Docker daemon"
        case .unauthorized:
            return "Unauthorized: Check your credentials"
        case .notFound(let resource):
            return "\(resource) not found"
        case .conflict(let message):
            return message
        case .serverError(let message):
            return "Docker daemon error: \(message)"
        case .invalidURL:
            return "Invalid Docker host URL"
        case .invalidResponse:
            return "Invalid response from Docker daemon"
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .unexpectedStatus(let code):
            return "Unexpected HTTP status: \(code)"
        case .networkTimeout:
            return "Connection timed out"
        case .notImplemented(let feature):
            return "\(feature) is not yet implemented"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        case .socketNotFound(let path):
            return "Docker socket not found at \(path)"
        case .sshConnectionFailed(let message):
            return "SSH connection failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Make sure Docker is running and accessible"
        case .unauthorized:
            return "Check your TLS certificates or credentials"
        case .notFound:
            return "The requested resource may have been removed"
        case .conflict:
            return "Try again or check the container state"
        case .serverError:
            return "Check Docker daemon logs for more information"
        case .invalidURL:
            return "Verify your Docker host configuration"
        case .invalidResponse:
            return "The Docker daemon may be incompatible"
        case .invalidConfiguration:
            return "Review your connection settings"
        case .unexpectedStatus:
            return "This may indicate an API version mismatch"
        case .networkTimeout:
            return "Check your network connection"
        case .notImplemented:
            return "This feature will be available in a future update"
        case .decodingError:
            return "This may indicate an API version mismatch"
        case .socketNotFound:
            return "Make sure Docker Desktop is running"
        case .sshConnectionFailed:
            return "Check your SSH credentials and ensure the remote host is accessible"
        }
    }
}

/// Container action error types
public enum ContainerActionError: Error, LocalizedError, Sendable {
    case containerNotRunning(String)
    case containerAlreadyRunning(String)
    case actionFailed(String, underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case .containerNotRunning(let name):
            return "Container '\(name)' is not running"
        case .containerAlreadyRunning(let name):
            return "Container '\(name)' is already running"
        case .actionFailed(let action, let underlying):
            if let underlying {
                return "Failed to \(action): \(underlying.localizedDescription)"
            }
            return "Failed to \(action)"
        }
    }
}
