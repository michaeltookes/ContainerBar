import Foundation

/// Protocol for container fetch strategies
///
/// Following the CodexBar strategy pattern, this allows different connection
/// types (Unix socket, TCP+TLS, SSH) to be handled uniformly.
public protocol ContainerFetchStrategy: Sendable {
    /// Unique identifier for this strategy
    var id: String { get }

    /// The connection type this strategy handles
    var kind: ConnectionType { get }

    /// Check if this strategy is available for the given host
    /// - Parameter host: The Docker host configuration
    /// - Returns: True if this strategy can be used
    func isAvailable(host: DockerHost) async -> Bool

    /// Create a Docker API client for the given host
    /// - Parameter host: The Docker host configuration
    /// - Returns: A configured Docker API client
    func createClient(host: DockerHost) throws -> DockerAPIClient
}

/// Source descriptor for Docker connections
/// Following the CodexBar Provider Descriptor pattern
public struct DockerSourceDescriptor: Sendable {
    public let id: DockerSource
    public let metadata: SourceMetadata
    public let branding: SourceBranding
    public let fetchPlan: SourceFetchPlan

    public init(
        id: DockerSource,
        metadata: SourceMetadata,
        branding: SourceBranding,
        fetchPlan: SourceFetchPlan
    ) {
        self.id = id
        self.metadata = metadata
        self.branding = branding
        self.fetchPlan = fetchPlan
    }
}

public enum DockerSource: String, CaseIterable, Sendable {
    case dockerLocal
    case dockerRemote
    case dockerSSH
}

public struct SourceMetadata: Sendable {
    public let displayName: String
    public let connectionLabel: String
    public let resourceLabel: String

    public init(displayName: String, connectionLabel: String, resourceLabel: String) {
        self.displayName = displayName
        self.connectionLabel = connectionLabel
        self.resourceLabel = resourceLabel
    }
}

public struct SourceBranding: Sendable {
    public let iconName: String
    public let color: SourceColor

    public init(iconName: String, color: SourceColor) {
        self.iconName = iconName
        self.color = color
    }
}

public struct SourceColor: Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Docker blue color
    public static let dockerBlue = SourceColor(red: 0.13, green: 0.59, blue: 0.95)
}

public struct SourceFetchPlan: Sendable {
    public let strategies: [any ContainerFetchStrategy]

    public init(strategies: [any ContainerFetchStrategy]) {
        self.strategies = strategies
    }
}
