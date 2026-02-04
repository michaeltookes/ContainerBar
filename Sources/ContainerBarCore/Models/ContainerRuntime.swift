import Foundation

/// Container runtime type (Docker or Podman)
public enum ContainerRuntime: String, Codable, CaseIterable, Sendable, Equatable {
    case docker
    case podman

    /// User-friendly display name
    public var displayName: String {
        switch self {
        case .docker: return "Docker"
        case .podman: return "Podman"
        }
    }

    /// Default socket path for this runtime on macOS
    public var defaultSocketPath: String {
        switch self {
        case .docker:
            return "/var/run/docker.sock"
        case .podman:
            // Podman machine socket location on macOS
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(homeDir)/.local/share/containers/podman/machine/podman.sock"
        }
    }

    /// Alternative socket paths to check for this runtime
    public var alternativeSocketPaths: [String] {
        switch self {
        case .docker:
            return [
                "/var/run/docker.sock",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.docker/run/docker.sock"
            ]
        case .podman:
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            return [
                "\(homeDir)/.local/share/containers/podman/machine/podman.sock",
                "/var/run/podman/podman.sock",
                "/run/podman/podman.sock"
            ]
        }
    }

    /// Default socket path on Linux servers (for SSH connections)
    public var defaultRemoteSocketPath: String {
        switch self {
        case .docker:
            return "/var/run/docker.sock"
        case .podman:
            // Rootless Podman socket (most common for non-root SSH users)
            return "/run/user/1000/podman/podman.sock"
        }
    }

    /// SF Symbol name for runtime badge icon
    public var iconName: String {
        switch self {
        case .docker: return "shippingbox.fill"
        case .podman: return "seal.fill"
        }
    }

    /// Small badge icon for compact views
    public var badgeIconName: String {
        switch self {
        case .docker: return "d.circle.fill"
        case .podman: return "p.circle.fill"
        }
    }
}
