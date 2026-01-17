import Foundation
import DockerBarCore
import Logging

/// Main state container for Docker container data
///
/// This store follows the CodexBar @Observable pattern, providing reactive
/// state management for the container list, statistics, and connection status.
@MainActor
@Observable
public final class ContainerStore {
    // MARK: - Container Data

    /// List of all Docker containers
    public private(set) var containers: [DockerContainer] = []

    /// Statistics for each container, keyed by container ID
    public private(set) var stats: [String: ContainerStats] = [:]

    /// Aggregated metrics snapshot
    public private(set) var metricsSnapshot: ContainerMetricsSnapshot?

    // MARK: - Connection State

    /// Whether we have an active connection to Docker
    public private(set) var isConnected: Bool = false

    /// Error message if connection failed
    public private(set) var connectionError: String?

    /// Timestamp of last successful refresh
    public private(set) var lastRefreshAt: Date?

    // MARK: - Refresh State

    /// Whether a refresh is currently in progress
    public private(set) var isRefreshing: Bool = false

    /// Set of container IDs currently being acted upon
    public private(set) var actionInProgress: Set<String> = []

    // MARK: - Private Properties

    @ObservationIgnored
    private let failureGate = ConsecutiveFailureGate()

    @ObservationIgnored
    private var timerTask: Task<Void, Never>?

    @ObservationIgnored
    private let settings: SettingsStore

    @ObservationIgnored
    private let logger = Logger(label: "com.dockerbar.store.container")

    // MARK: - Initialization

    public init(settings: SettingsStore) {
        self.settings = settings
        startTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    // MARK: - Refresh

    /// Refresh container data from Docker daemon
    /// - Parameter force: If true, refresh even if already refreshing
    public func refresh(force: Bool = false) async {
        guard !isRefreshing || force else {
            logger.debug("Refresh skipped - already refreshing")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        logger.info("Refreshing container data")

        // For now, use mock data until API client is implemented
        // TODO: Replace with actual Docker API calls in Day 5
        // When real API is implemented, wrap this in do-catch for error handling
        let mockContainers = generateMockContainers()
        let mockStats = generateMockStats(for: mockContainers)

        self.containers = mockContainers
        self.stats = mockStats
        self.metricsSnapshot = buildMetricsSnapshot(containers: mockContainers, stats: mockStats)
        self.isConnected = true
        self.connectionError = nil
        self.lastRefreshAt = Date()
        self.failureGate.recordSuccess()

        logger.info("Refresh complete: \(mockContainers.count) containers")
    }

    // MARK: - Container Actions

    /// Start a stopped container
    public func startContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Starting container: \(id)")

        // TODO: Implement actual Docker API call
        // For now, just refresh after a delay to simulate the action
        try? await Task.sleep(for: .milliseconds(500))
        await refresh(force: true)
    }

    /// Stop a running container
    public func stopContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Stopping container: \(id)")

        // TODO: Implement actual Docker API call
        try? await Task.sleep(for: .milliseconds(500))
        await refresh(force: true)
    }

    /// Restart a container
    public func restartContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Restarting container: \(id)")

        // TODO: Implement actual Docker API call
        try? await Task.sleep(for: .milliseconds(500))
        await refresh(force: true)
    }

    // MARK: - Timer Management

    private func startTimer() {
        timerTask?.cancel()

        guard let interval = settings.refreshInterval.seconds else {
            logger.info("Auto-refresh disabled (manual mode)")
            return
        }

        logger.info("Starting auto-refresh with \(interval)s interval")

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// Restart the refresh timer with current settings
    public func restartTimer() {
        startTimer()
    }

    // MARK: - Private Helpers

    private func buildMetricsSnapshot(
        containers: [DockerContainer],
        stats: [String: ContainerStats]
    ) -> ContainerMetricsSnapshot {
        let statsList = Array(stats.values)
        let totalCPU = statsList.reduce(0.0) { $0 + $1.cpuPercent }
        let totalMemUsed = statsList.reduce(UInt64(0)) { $0 + $1.memoryUsageBytes }
        let totalMemLimit = statsList.reduce(UInt64(0)) { $0 + $1.memoryLimitBytes }

        return ContainerMetricsSnapshot(
            containers: statsList,
            totalCPUPercent: totalCPU,
            totalMemoryUsedBytes: totalMemUsed,
            totalMemoryLimitBytes: totalMemLimit,
            runningCount: containers.filter { $0.state == .running }.count,
            stoppedCount: containers.filter { $0.state == .exited }.count,
            pausedCount: containers.filter { $0.state == .paused }.count,
            totalCount: containers.count,
            updatedAt: Date()
        )
    }

    // MARK: - Mock Data (Temporary)

    /// Generate mock containers for testing until API is implemented
    private func generateMockContainers() -> [DockerContainer] {
        #if DEBUG
        return [
            .mock(id: "abc123", name: "nginx-proxy", state: .running, status: "Up 2 hours"),
            .mock(id: "def456", name: "postgres-db", image: "postgres:15", state: .running, status: "Up 3 days"),
            .mock(id: "ghi789", name: "redis-cache", image: "redis:alpine", state: .running, status: "Up 3 days"),
            .mock(id: "jkl012", name: "api-server", image: "node:18", state: .running, status: "Up 1 hour"),
            .mock(id: "mno345", name: "backup-service", image: "alpine", state: .exited, status: "Exited (0) 12 hours ago"),
        ]
        #else
        return []
        #endif
    }

    /// Generate mock stats for testing until API is implemented
    private func generateMockStats(for containers: [DockerContainer]) -> [String: ContainerStats] {
        #if DEBUG
        var stats: [String: ContainerStats] = [:]
        for container in containers where container.state == .running {
            stats[container.id] = .mock(
                containerId: container.id,
                cpuPercent: Double.random(in: 0.1...15.0),
                memoryUsageBytes: UInt64.random(in: 50_000_000...500_000_000)
            )
        }
        return stats
        #else
        return [:]
        #endif
    }
}
