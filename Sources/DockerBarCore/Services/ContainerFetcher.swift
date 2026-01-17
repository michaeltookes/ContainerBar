import Foundation
import Logging

/// High-level service for fetching containers and their statistics
///
/// Provides a unified interface for fetching all container data,
/// handling errors gracefully with the ConsecutiveFailureGate pattern.
public actor ContainerFetcher {

    // MARK: - Properties

    private let client: DockerAPIClient
    private let failureGate: ConsecutiveFailureGate
    private let logger = Logger(label: "com.dockerbar.fetcher")

    private var lastFetchResult: ContainerFetchResult?
    private var lastFetchTime: Date?

    // MARK: - Configuration

    /// Minimum time between fetches to avoid hammering the API
    private let minFetchInterval: TimeInterval = 1.0

    /// Maximum number of concurrent stats fetches
    private let maxConcurrentStatsFetches = 10

    // MARK: - Initialization

    public init(client: DockerAPIClient) {
        self.client = client
        self.failureGate = ConsecutiveFailureGate(threshold: 2)
    }

    // MARK: - Factory Methods

    /// Create a fetcher for the local Docker daemon
    public static func local() throws -> ContainerFetcher {
        let client = try DockerAPIClientImpl.local()
        return ContainerFetcher(client: client)
    }

    /// Create a fetcher for a specific Docker host
    public static func forHost(_ host: DockerHost) throws -> ContainerFetcher {
        let client = try DockerAPIClientImpl(host: host)
        return ContainerFetcher(client: client)
    }

    // MARK: - Fetching

    /// Fetch all containers and their statistics
    /// - Parameters:
    ///   - includeStats: Whether to fetch stats for running containers
    ///   - all: Whether to include stopped containers
    /// - Returns: Fetch result with containers, stats, and metrics
    public func fetch(includeStats: Bool = true, all: Bool = true) async throws -> ContainerFetchResult {
        // Rate limiting
        if let lastTime = lastFetchTime,
           Date().timeIntervalSince(lastTime) < minFetchInterval {
            if let cachedResult = lastFetchResult {
                logger.debug("Returning cached result (rate limited)")
                return cachedResult
            }
        }

        logger.info("Fetching containers (all=\(all), includeStats=\(includeStats))")

        do {
            // Fetch container list
            let containers = try await client.listContainers(all: all)

            // Fetch stats for running containers
            var stats: [String: ContainerStats] = [:]
            if includeStats {
                stats = await fetchStatsForContainers(containers)
            }

            // Build metrics snapshot
            let metrics = buildMetricsSnapshot(containers: containers, stats: stats)

            // Record success
            failureGate.recordSuccess()

            let result = ContainerFetchResult(
                containers: containers,
                stats: stats,
                metrics: metrics
            )

            lastFetchResult = result
            lastFetchTime = Date()

            logger.info("Fetch complete: \(containers.count) containers")
            return result

        } catch {
            logger.error("Fetch failed: \(error.localizedDescription)")

            // Check if we should surface this error
            let hadPriorData = lastFetchResult != nil
            if failureGate.shouldSurfaceError(onFailureWithPriorData: hadPriorData) {
                throw error
            }

            // Return cached result if we have one
            if let cached = lastFetchResult {
                logger.warning("Returning stale cached result after transient failure")
                return cached
            }

            throw error
        }
    }

    /// Test connection to Docker daemon
    public func testConnection() async throws {
        logger.info("Testing Docker connection")
        try await client.ping()
        logger.info("Docker connection successful")
    }

    // MARK: - Container Actions

    public func startContainer(id: String) async throws {
        logger.info("Starting container: \(id)")
        try await client.startContainer(id: id)
    }

    public func stopContainer(id: String, timeout: Int? = 10) async throws {
        logger.info("Stopping container: \(id)")
        try await client.stopContainer(id: id, timeout: timeout)
    }

    public func restartContainer(id: String, timeout: Int? = 10) async throws {
        logger.info("Restarting container: \(id)")
        try await client.restartContainer(id: id, timeout: timeout)
    }

    public func removeContainer(id: String, force: Bool = false, volumes: Bool = false) async throws {
        logger.info("Removing container: \(id)")
        try await client.removeContainer(id: id, force: force, volumes: volumes)
    }

    public func getContainerLogs(id: String, tail: Int? = 100) async throws -> String {
        logger.info("Fetching logs for container: \(id)")
        return try await client.getContainerLogs(id: id, tail: tail, timestamps: false)
    }

    // MARK: - Private Helpers

    private func fetchStatsForContainers(_ containers: [DockerContainer]) async -> [String: ContainerStats] {
        let runningContainers = containers.filter { $0.state == .running }

        guard !runningContainers.isEmpty else {
            return [:]
        }

        // Limit concurrent stats fetches
        let containersToFetch = Array(runningContainers.prefix(maxConcurrentStatsFetches))

        // Fetch stats concurrently using TaskGroup
        return await withTaskGroup(of: (String, ContainerStats?).self) { group in
            for container in containersToFetch {
                group.addTask {
                    do {
                        let stream = try await self.client.getContainerStats(id: container.id, stream: false)
                        for try await stats in stream {
                            return (container.id, stats)
                        }
                        return (container.id, nil)
                    } catch {
                        self.logger.warning("Failed to fetch stats for \(container.displayName): \(error.localizedDescription)")
                        return (container.id, nil)
                    }
                }
            }

            var results: [String: ContainerStats] = [:]
            for await (id, stats) in group {
                if let stats {
                    results[id] = stats
                }
            }
            return results
        }
    }

    private func buildMetricsSnapshot(
        containers: [DockerContainer],
        stats: [String: ContainerStats]
    ) -> ContainerMetricsSnapshot {
        let statsList = Array(stats.values)

        let totalCPU = statsList.reduce(0.0) { $0 + $1.cpuPercent }
        let totalMemUsed = statsList.reduce(UInt64(0)) { $0 + $1.memoryUsageBytes }
        let totalMemLimit = statsList.reduce(UInt64(0)) { $0 + $1.memoryLimitBytes }

        let runningCount = containers.filter { $0.state == .running }.count
        let stoppedCount = containers.filter { $0.state == .exited || $0.state == .dead }.count
        let pausedCount = containers.filter { $0.state == .paused }.count

        return ContainerMetricsSnapshot(
            containers: statsList,
            totalCPUPercent: totalCPU,
            totalMemoryUsedBytes: totalMemUsed,
            totalMemoryLimitBytes: totalMemLimit,
            runningCount: runningCount,
            stoppedCount: stoppedCount,
            pausedCount: pausedCount,
            totalCount: containers.count,
            updatedAt: Date()
        )
    }
}

// MARK: - Retry Configuration

/// Configuration for retry behavior
public struct RetryConfig: Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let multiplier: Double

    public static let `default` = RetryConfig(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 10.0,
        multiplier: 2.0
    )

    public init(maxAttempts: Int, initialDelay: TimeInterval, maxDelay: TimeInterval, multiplier: Double) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
    }
}

// MARK: - Retry Helper

/// Retry an async operation with exponential backoff
public func withRetry<T>(
    config: RetryConfig = .default,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = config.initialDelay

    for attempt in 1...config.maxAttempts {
        do {
            return try await operation()
        } catch let error as DockerAPIError {
            lastError = error

            // Don't retry permanent errors
            guard error.isTransient else {
                throw error
            }

            // Don't delay on last attempt
            guard attempt < config.maxAttempts else {
                break
            }

            // Wait with exponential backoff
            try? await Task.sleep(for: .seconds(delay))

            // Increase delay for next attempt
            delay = min(delay * config.multiplier, config.maxDelay)
        } catch {
            lastError = error
            throw error
        }
    }

    throw lastError ?? DockerAPIError.connectionFailed
}

// MARK: - Error Extensions

extension DockerAPIError {
    /// Whether this error is transient and can be retried
    public var isTransient: Bool {
        switch self {
        case .connectionFailed, .networkTimeout, .serverError:
            return true
        case .unauthorized, .notFound, .invalidConfiguration, .invalidURL,
             .socketNotFound:
            return false
        case .conflict, .unexpectedStatus, .invalidResponse, .decodingError,
             .notImplemented:
            return false
        }
    }
}
