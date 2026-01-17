import Foundation

/// Protocol defining Docker API operations
public protocol DockerAPIClient: Sendable {
    /// Ping the Docker daemon to verify connectivity
    func ping() async throws

    /// List all containers
    /// - Parameter all: If true, include stopped containers
    /// - Returns: Array of Docker containers
    func listContainers(all: Bool) async throws -> [DockerContainer]

    /// Get detailed information about a specific container
    /// - Parameter id: Container ID or name
    /// - Returns: Container details
    func getContainer(id: String) async throws -> DockerContainer

    /// Get real-time statistics for a container
    /// - Parameters:
    ///   - id: Container ID or name
    ///   - stream: If true, stream continuous updates
    /// - Returns: Async stream of container statistics
    func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error>

    /// Start a stopped container
    /// - Parameter id: Container ID or name
    func startContainer(id: String) async throws

    /// Stop a running container
    /// - Parameters:
    ///   - id: Container ID or name
    ///   - timeout: Seconds to wait before killing
    func stopContainer(id: String, timeout: Int?) async throws

    /// Restart a container
    /// - Parameters:
    ///   - id: Container ID or name
    ///   - timeout: Seconds to wait before killing
    func restartContainer(id: String, timeout: Int?) async throws

    /// Remove a container
    /// - Parameters:
    ///   - id: Container ID or name
    ///   - force: Force removal of running container
    ///   - volumes: Remove associated volumes
    func removeContainer(id: String, force: Bool, volumes: Bool) async throws

    /// Get container logs
    /// - Parameters:
    ///   - id: Container ID or name
    ///   - tail: Number of lines from the end
    ///   - timestamps: Include timestamps
    /// - Returns: Log output as string
    func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String

    /// Get Docker system information
    /// - Returns: System information
    func getSystemInfo() async throws -> DockerSystemInfo
}

/// Container fetch result containing all fetched data
public struct ContainerFetchResult: Sendable {
    public let containers: [DockerContainer]
    public let stats: [String: ContainerStats]
    public let metrics: ContainerMetricsSnapshot

    public init(
        containers: [DockerContainer],
        stats: [String: ContainerStats],
        metrics: ContainerMetricsSnapshot
    ) {
        self.containers = containers
        self.stats = stats
        self.metrics = metrics
    }
}
