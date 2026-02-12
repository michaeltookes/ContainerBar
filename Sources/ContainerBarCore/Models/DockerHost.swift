import Foundation

/// Docker/Podman host connection configuration
public struct DockerHost: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var connectionType: ConnectionType
    public var runtime: ContainerRuntime
    public var isDefault: Bool

    // Connection details vary by type
    public var socketPath: String?
    public var host: String?
    public var port: Int?
    public var tlsEnabled: Bool
    public var sshUser: String?
    public var sshPort: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        connectionType: ConnectionType,
        runtime: ContainerRuntime = .docker,
        isDefault: Bool = false,
        socketPath: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        tlsEnabled: Bool = false,
        sshUser: String? = nil,
        sshPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.connectionType = connectionType
        self.runtime = runtime
        self.isDefault = isDefault
        self.socketPath = socketPath ?? (connectionType == .unixSocket ? runtime.defaultSocketPath : nil)
        self.host = host
        self.port = port
        self.tlsEnabled = tlsEnabled || connectionType == .tcpTLS
        self.sshUser = sshUser
        self.sshPort = sshPort ?? (connectionType == .ssh ? 22 : nil)
    }

    /// Creates a default local Docker host configuration
    public static var local: DockerHost {
        DockerHost(
            name: "Local Docker",
            connectionType: .unixSocket,
            runtime: .docker,
            isDefault: true,
            socketPath: ContainerRuntime.docker.defaultSocketPath
        )
    }

    /// Creates a default local Podman host configuration
    public static var localPodman: DockerHost {
        DockerHost(
            name: "Local Podman",
            connectionType: .unixSocket,
            runtime: .podman,
            isDefault: false,
            socketPath: ContainerRuntime.podman.defaultSocketPath
        )
    }
}

/// Connection type enumeration
public enum ConnectionType: String, Codable, Sendable, CaseIterable {
    case unixSocket = "unix"
    case tcpTLS = "tcp+tls"
    case ssh = "ssh"

    public var displayName: String {
        switch self {
        case .unixSocket: return "Unix Socket (Local)"
        case .tcpTLS: return "TCP + TLS (Remote)"
        case .ssh: return "SSH Tunnel (Remote)"
        }
    }

    public var requiresCredentials: Bool {
        switch self {
        case .unixSocket: return false
        case .tcpTLS, .ssh: return true
        }
    }
}

/// Docker system information
public struct DockerSystemInfo: Codable, Sendable {
    public let id: String
    public let containers: Int
    public let containersRunning: Int
    public let containersPaused: Int
    public let containersStopped: Int
    public let images: Int
    public let dockerVersion: String
    public let operatingSystem: String
    public let kernelVersion: String
    public let architecture: String
    public let memoryTotal: UInt64
    public let cpuCount: Int
    public let serverVersion: String

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case containers = "Containers"
        case containersRunning = "ContainersRunning"
        case containersPaused = "ContainersPaused"
        case containersStopped = "ContainersStopped"
        case images = "Images"
        case dockerVersion = "DockerRootDir"
        case operatingSystem = "OperatingSystem"
        case kernelVersion = "KernelVersion"
        case architecture = "Architecture"
        case memoryTotal = "MemTotal"
        case cpuCount = "NCPU"
        case serverVersion = "ServerVersion"
    }
}

#if DEBUG
extension DockerHost {
    /// Creates a mock remote host for testing
    public static func mockRemote(
        name: String = "Remote Server",
        host: String = "192.168.1.100",
        port: Int = 2376,
        runtime: ContainerRuntime = .docker
    ) -> DockerHost {
        DockerHost(
            name: name,
            connectionType: .tcpTLS,
            runtime: runtime,
            isDefault: false,
            host: host,
            port: port,
            tlsEnabled: true
        )
    }
}
#endif
