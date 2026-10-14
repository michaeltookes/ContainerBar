import Foundation
import ContainerBarCore

/// Maps a connection-related `Error` to a user-facing message for the
/// dashboard's connection status / error banner.
///
/// The copy is runtime- and transport-aware (CB-077): a Podman user is never
/// told to start Docker Desktop, and an SSH host is named in the message.
/// - Parameters:
///   - error: the error thrown while building the fetcher or talking to the
///     daemon.
///   - host: the selected host, or `nil` for the implicit local Docker host.
func userFriendlyConnectionErrorMessage(for error: Error, host: DockerHost? = nil) -> String {
    let host = host ?? .local
    let runtime = host.runtime.displayName

    if let dockerError = error as? DockerAPIError {
        switch dockerError {
        case .socketNotFound(let path):
            return "\(notRunningMessage(for: host.runtime)) No socket at \(path)."
        case .connectionFailed:
            if host.connectionType == .ssh {
                return "Can't reach \(host.name) over SSH."
            }
            return "Cannot connect to \(runtime). Make sure \(runtime) is running."
        case .unauthorized:
            return "Access denied. Check \(runtime) permissions."
        case .sshConnectionFailed(let message):
            return sshFailureMessage(hostName: host.name, stderr: message)
        case .tlsConnectionFailed(let message):
            return "TLS connection failed: \(message)"
        case .invalidResponse:
            return "Invalid response from \(runtime). Check if \(runtime) is running on the selected host."
        default:
            return dockerError.localizedDescription
        }
    }

    return "Connection error: \(error.localizedDescription)"
}

/// The "runtime is not running" sentence for a local socket that is missing.
func notRunningMessage(for runtime: ContainerRuntime) -> String {
    switch runtime {
    case .docker:
        return "Docker is not running. Start Docker and try again."
    case .podman:
        return "Podman is not running. Start the Podman machine and try again."
    }
}

/// "Can't reach <host> over SSH." plus the class of the first stderr line
/// (authentication, host key, refused), or that first line verbatim when it
/// matches none of them.
func sshFailureMessage(hostName: String, stderr: String) -> String {
    let base = "Can't reach \(hostName) over SSH."
    let firstLine = stderr
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .first { !$0.isEmpty } ?? ""

    switch SSHFailureClass(stderrLine: firstLine) {
    case .authentication:
        return "\(base) Authentication failed: check the SSH user and key."
    case .hostKey:
        return "\(base) Host key verification failed: verify the host key in ~/.ssh/known_hosts."
    case .refused:
        return "\(base) Connection refused."
    case .other:
        return firstLine.isEmpty ? base : "\(base) \(firstLine)"
    }
}

/// Coarse classification of an ssh stderr line, so the banner says what kind
/// of failure happened without echoing ssh's full diagnostic output.
enum SSHFailureClass: Equatable {
    case authentication
    case hostKey
    case refused
    case other

    init(stderrLine line: String) {
        let hostKeyMarkers = [
            "host key verification failed",
            "remote host identification has changed",
            "host key is known"
        ]
        let authMarkers = ["permission denied", "authentication failed", "too many authentication failures"]

        if hostKeyMarkers.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            self = .hostKey
        } else if authMarkers.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            self = .authentication
        } else if line.localizedCaseInsensitiveContains("connection refused") {
            self = .refused
        } else {
            self = .other
        }
    }
}
