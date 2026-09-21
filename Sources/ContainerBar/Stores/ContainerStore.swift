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
    public internal(set) var containers: [DockerContainer] = []

    /// Statistics for each container, keyed by container ID
    public internal(set) var stats: [String: ContainerStats] = [:]

    /// Aggregated metrics snapshot
    public internal(set) var metricsSnapshot: ContainerMetricsSnapshot?

    /// Rolling history for sparkline charts
    public internal(set) var metricsHistory: AggregatedMetricsHistory = AggregatedMetricsHistory()

    // MARK: - Connection State

    /// Whether we have an active connection to Docker
    public internal(set) var isConnected: Bool = false

    /// Error message if connection failed
    public internal(set) var connectionError: String?

    /// Timestamp of last successful refresh
    public internal(set) var lastRefreshAt: Date?

    // MARK: - Refresh State

    /// Whether a refresh is currently in progress
    public internal(set) var isRefreshing: Bool = false

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
    var settingsObservationTask: Task<Void, Never>?

    /// The refresh currently in flight, if any. Held so a host switch can
    /// cancel it and so a non-forced refresh can join it (CB-064).
    @ObservationIgnored
    var refreshTask: Task<Void, Never>?

    /// Forced refresh started after one or more forced callers joined an
    /// already in-flight refresh. All joined forced callers await this same
    /// follow-up so only one cache-bypassing daemon request is made.
    @ObservationIgnored
    var pendingJoinedForcedRefresh: (joinedGeneration: Int, refreshGeneration: Int, task: Task<Void, Never>)?

    /// Monotonic stamp incremented on every refresh start and every host
    /// switch. A refresh only writes state while its stamp is still current,
    /// so a slow response from a superseded fetcher can never overwrite the
    /// live host's data (CB-064).
    @ObservationIgnored
    var refreshGeneration: Int = 0

    /// The selected host the live fetcher was last built for. Used by the
    /// settings observer to converge on real host changes while ignoring
    /// edits to other, non-selected hosts (CB-065).
    @ObservationIgnored
    var lastResolvedHost: DockerHost?

    /// The refresh interval the timer was last (re)started for, so a host
    /// edit does not needlessly reset the auto-refresh countdown.
    @ObservationIgnored
    var lastRefreshInterval: RefreshInterval?

    @ObservationIgnored
    let settings: SettingsStore

    @ObservationIgnored
    let logger = Logger(label: "com.containerbar.store.container")

    @ObservationIgnored
    let rateTracker = MetricsRateTracker()

    // MARK: - Initialization

    /// Builds a fetcher for the selected host (`nil` means local Docker).
    public typealias FetcherFactory = @MainActor (DockerHost?) throws -> ContainerFetcher

    @ObservationIgnored
    let fetcherFactory: FetcherFactory

    /// Production factory: real Unix socket, SSH, or TLS client per host.
    public static let defaultFetcherFactory: FetcherFactory = { host in
        if let host {
            return try ContainerFetcher.forHost(host)
        }
        return try ContainerFetcher.local()
    }

    public init(settings: SettingsStore, fetcherFactory: @escaping FetcherFactory = ContainerStore.defaultFetcherFactory) {
        self.settings = settings
        self.fetcherFactory = fetcherFactory
        initializeFetcher()
        lastResolvedHost = settings.selectedHost
        lastRefreshInterval = settings.refreshInterval
        startTimer()
        startSettingsObservation()
    }

    #if DEBUG
    /// Test-only initializer that accepts a pre-built fetcher and skips auto-refresh
    public init(settings: SettingsStore, fetcher: ContainerFetcher, startRefreshLoop: Bool = false) {
        self.settings = settings
        self.fetcherFactory = ContainerStore.defaultFetcherFactory
        self.fetcher = fetcher
        lastResolvedHost = settings.selectedHost
        lastRefreshInterval = settings.refreshInterval
        if startRefreshLoop {
            startTimer()
        }
    }

    /// Test-only initializer that drives the fetcher through an injected
    /// factory (so a host switch rebuilds against a new mock) while keeping
    /// the auto-refresh timer and settings observation opt-in, so tests stay
    /// deterministic.
    public init(
        settings: SettingsStore,
        fetcherFactory: @escaping FetcherFactory,
        startRefreshLoop: Bool,
        observeSettings: Bool
    ) {
        self.settings = settings
        self.fetcherFactory = fetcherFactory
        initializeFetcher()
        lastResolvedHost = settings.selectedHost
        lastRefreshInterval = settings.refreshInterval
        if startRefreshLoop {
            startTimer()
        }
        if observeSettings {
            startSettingsObservation()
        }
    }
    #endif

    deinit {
        timerTask?.cancel()
        settingsObservationTask?.cancel()
        refreshTask?.cancel()
    }

    // MARK: - Fetcher Initialization

    func initializeFetcher() {
        do {
            let host = settings.selectedHost
            fetcher = try fetcherFactory(host)
            logger.info("Fetcher initialized for host: \(host?.name ?? "Local Docker")")
        } catch {
            logger.error("Failed to initialize fetcher: \(error.localizedDescription)")
            connectionError = error.localizedDescription
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
        lastRefreshInterval = settings.refreshInterval
    }

}
