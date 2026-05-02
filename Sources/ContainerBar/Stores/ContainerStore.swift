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
    public internal(set) var actionInProgress: Set<String> = []

    // MARK: - Action Error State

    /// Represents an error from a container action (start/stop/restart/remove)
    public struct ActionError: Identifiable {
        public let id = UUID()
        public let message: String
        public let timestamp: Date = Date()
    }

    /// Most recent action error, displayed as a transient banner
    public internal(set) var lastActionError: ActionError?

    // MARK: - Private Properties

    @ObservationIgnored
    var fetcher: ContainerFetcher?

    @ObservationIgnored
    private var timerTask: Task<Void, Never>?

    @ObservationIgnored
    private var settingsObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private let settings: SettingsStore

    @ObservationIgnored
    let logger = Logger(label: "com.containerbar.store.container")

    @ObservationIgnored
    private let rateTracker = MetricsRateTracker()

    // MARK: - Initialization

    public init(settings: SettingsStore) {
        self.settings = settings
        initializeFetcher()
        startTimer()
        startSettingsObservation()
    }

    #if DEBUG
    /// Test-only initializer that accepts a pre-built fetcher and skips auto-refresh
    public init(settings: SettingsStore, fetcher: ContainerFetcher, startRefreshLoop: Bool = false) {
        self.settings = settings
        self.fetcher = fetcher
        if startRefreshLoop {
            startTimer()
        }
    }
    #endif

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

        rateTracker.reset()

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
        connectionError = nil

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

            rateTracker.update(
                history: &metricsHistory,
                snapshot: result.metrics,
                stats: result.stats
            )

            logger.info("Refresh complete: \(result.containers.count) containers")
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription)")
            self.connectionError = userFriendlyConnectionErrorMessage(for: error)
            self.isConnected = false
        }
    }

    // MARK: - Container Actions

    public func startContainer(id: String) async {
        await performContainerAction(id: id, progressive: "Starting", infinitive: "start") { fetcher in
            try await fetcher.startContainer(id: id)
        }
    }

    public func stopContainer(id: String) async {
        await performContainerAction(id: id, progressive: "Stopping", infinitive: "stop") { fetcher in
            try await fetcher.stopContainer(id: id)
        }
    }

    public func restartContainer(id: String) async {
        await performContainerAction(id: id, progressive: "Restarting", infinitive: "restart") { fetcher in
            try await fetcher.restartContainer(id: id)
        }
    }

    public func removeContainer(id: String, force: Bool = false) async {
        await performContainerAction(id: id, progressive: "Removing", infinitive: "remove") { fetcher in
            try await fetcher.removeContainer(id: id, force: force)
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

}
