import Foundation
import ContainerBarCore

/// Maps a connection-related `Error` to a user-facing message for the
/// dashboard's connection status / error banner.
func userFriendlyConnectionErrorMessage(for error: Error) -> String {
    if let dockerError = error as? DockerAPIError {
        switch dockerError {
        case .socketNotFound:
            return "Docker not running. Please start Docker Desktop."
        case .connectionFailed:
            return "Cannot connect to Docker. Make sure Docker is running."
        case .unauthorized:
            return "Access denied. Check Docker permissions."
        case .sshConnectionFailed(let message):
            return "SSH connection failed: \(message)"
        case .tlsConnectionFailed(let message):
            return "TLS connection failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Docker. Check if Docker is running on the selected host."
        default:
            return dockerError.localizedDescription
        }
    }

    return "Connection error: \(error.localizedDescription)"
}
