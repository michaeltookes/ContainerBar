import Foundation
import ContainerBarCore
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

    /// Rolling history for sparkline charts
    public private(set) var metricsHistory: AggregatedMetricsHistory = AggregatedMetricsHistory()

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
    private var fetcher: ContainerFetcher?

    @ObservationIgnored
    private var timerTask: Task<Void, Never>?

    @ObservationIgnored
    private var settingsObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private let settings: SettingsStore

    @ObservationIgnored
    private let logger = Logger(label: "com.containerbar.store.container")

    // MARK: - Rate Calculation State

    @ObservationIgnored
    private var previousNetworkRx: UInt64 = 0

    @ObservationIgnored
    private var previousNetworkTx: UInt64 = 0

    @ObservationIgnored
    private var previousBlockRead: UInt64 = 0

    @ObservationIgnored
    private var previousBlockWrite: UInt64 = 0

    @ObservationIgnored
    private var previousTimestamp: Date?

    // MARK: - Initialization

    public init(settings: SettingsStore) {
        self.settings = settings
        initializeFetcher()
        startTimer()
        startSettingsObservation()
    }

    deinit {
        timerTask?.cancel()
        settingsObservationTask?.cancel()
    }

    // MARK: - Fetcher Initialization

    private func initializeFetcher() {
        do {
            if let host = settings.selectedHost {
                fetcher = try ContainerFetcher.forHost(host)
                logger.info("Fetcher initialized for host: \(host.name)")
            } else {
                fetcher = try ContainerFetcher.local()
                logger.info("Fetcher initialized for local Docker")
            }
        } catch {
            logger.error("Failed to initialize fetcher: \(error.localizedDescription)")
            connectionError = error.localizedDescription
        }
    }

    /// Reinitialize the fetcher (e.g., when settings change)
    public func reinitializeFetcher() {
        // Clear existing data when switching hosts
        containers = []
        stats = [:]
        metricsSnapshot = nil
        metricsHistory.clearAll()
        isConnected = false
        connectionError = nil
        lastRefreshAt = nil

        // Reset rate calculation state
        previousNetworkRx = 0
        previousNetworkTx = 0
        previousBlockRead = 0
        previousBlockWrite = 0
        previousTimestamp = nil

        // Reset the fetcher
        fetcher = nil
        initializeFetcher()

        // Reset refreshing state after initialization
        isRefreshing = false
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

        // If no fetcher, try to initialize
        if fetcher == nil {
            initializeFetcher()
        }

        guard let fetcher else {
            connectionError = "Docker connection not configured"
            isConnected = false
            return
        }

        do {
            let result = try await fetcher.fetch(
                includeStats: true,
                all: settings.showStoppedContainers
            )

            self.containers = result.containers
            self.stats = result.stats
            self.metricsSnapshot = result.metrics
            self.isConnected = true
            self.connectionError = nil
            self.lastRefreshAt = Date()

            // Update sparkline history
            updateMetricsHistory(from: result.metrics, stats: result.stats)

            logger.info("Refresh complete: \(result.containers.count) containers")
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription)")

            // User-friendly error messages
            let userMessage = userFriendlyErrorMessage(for: error)
            self.connectionError = userMessage
            self.isConnected = false
        }
    }

    // MARK: - Metrics History

    /// Update sparkline history with latest metrics
    private func updateMetricsHistory(from metrics: ContainerMetricsSnapshot, stats: [String: ContainerStats]) {
        let now = Date()

        // Update CPU and memory history
        metricsHistory.cpu.append(metrics.totalCPUPercent)
        metricsHistory.memory.append(metrics.memoryUsagePercent)

        // Calculate network rates (KB/s)
        let totalNetworkRx = stats.values.reduce(0) { $0 + $1.networkRxBytes }
        let totalNetworkTx = stats.values.reduce(0) { $0 + $1.networkTxBytes }
        let totalBlockRead = stats.values.reduce(0) { $0 + $1.blockReadBytes }
        let totalBlockWrite = stats.values.reduce(0) { $0 + $1.blockWriteBytes }

        if let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                // Safe subtraction to handle counter resets (saturating to 0)
                let rxDelta = totalNetworkRx >= previousNetworkRx ? totalNetworkRx - previousNetworkRx : 0
                let txDelta = totalNetworkTx >= previousNetworkTx ? totalNetworkTx - previousNetworkTx : 0
                let readDelta = totalBlockRead >= previousBlockRead ? totalBlockRead - previousBlockRead : 0
                let writeDelta = totalBlockWrite >= previousBlockWrite ? totalBlockWrite - previousBlockWrite : 0

                // Calculate rates in KB/s
                let rxRate = Double(rxDelta) / elapsed / 1024.0
                let txRate = Double(txDelta) / elapsed / 1024.0
                let readRate = Double(readDelta) / elapsed / 1024.0
                let writeRate = Double(writeDelta) / elapsed / 1024.0

                // Append rates (guaranteed non-negative due to saturating subtraction)
                metricsHistory.networkRxRate.append(max(0, rxRate))
                metricsHistory.networkTxRate.append(max(0, txRate))
                metricsHistory.diskReadRate.append(max(0, readRate))
                metricsHistory.diskWriteRate.append(max(0, writeRate))
            }
        }

        // Store current values for next calculation
        previousNetworkRx = totalNetworkRx
        previousNetworkTx = totalNetworkTx
        previousBlockRead = totalBlockRead
        previousBlockWrite = totalBlockWrite
        previousTimestamp = now
    }

    // MARK: - Container Actions

    /// Start a stopped container
    public func startContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Starting container: \(id)")

        guard let fetcher else {
            logger.error("No fetcher available")
            return
        }

        do {
            try await fetcher.startContainer(id: id)
            await refresh(force: true)
        } catch {
            logger.error("Failed to start container: \(error.localizedDescription)")
        }
    }

    /// Stop a running container
    public func stopContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Stopping container: \(id)")

        guard let fetcher else {
            logger.error("No fetcher available")
            return
        }

        do {
            try await fetcher.stopContainer(id: id)
            await refresh(force: true)
        } catch {
            logger.error("Failed to stop container: \(error.localizedDescription)")
        }
    }

    /// Restart a container
    public func restartContainer(id: String) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Restarting container: \(id)")

        guard let fetcher else {
            logger.error("No fetcher available")
            return
        }

        do {
            try await fetcher.restartContainer(id: id)
            await refresh(force: true)
        } catch {
            logger.error("Failed to restart container: \(error.localizedDescription)")
        }
    }

    /// Remove a container
    public func removeContainer(id: String, force: Bool = false) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("Removing container: \(id)")

        guard let fetcher else {
            logger.error("No fetcher available")
            return
        }

        do {
            try await fetcher.removeContainer(id: id, force: force)
            await refresh(force: true)
        } catch {
            logger.error("Failed to remove container: \(error.localizedDescription)")
        }
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

    // MARK: - Settings Observation

    private func startSettingsObservation() {
        settingsObservationTask?.cancel()

        settingsObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                withObservationTracking {
                    _ = self.settings.refreshInterval
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.restartTimer()
                    }
                }

                // Small delay to coalesce changes
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Error Handling

    private func userFriendlyErrorMessage(for error: Error) -> String {
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
            case .invalidResponse:
                return "Invalid response from Docker. Check if Docker is running on the selected host."
            default:
                return dockerError.localizedDescription
            }
        }

        // Generic error
        return "Connection error: \(error.localizedDescription)"
    }
}
