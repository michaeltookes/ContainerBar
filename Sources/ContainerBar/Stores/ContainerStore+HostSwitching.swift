import Foundation
import ContainerBarCore

// MARK: - Refresh, host switching, and settings convergence
//
// CB-064: `refresh` is generation-fenced and cancel-and-restart. Every refresh
// is stamped with `refreshGeneration`; it only writes store state while its
// stamp is still current, so a slow response from a superseded fetcher can
// never overwrite the live host's data, and `isRefreshing` only clears when the
// latest refresh finishes.
//
// CB-065: every host-lifecycle mutation (dashboard switch, Settings "set
// active", remove, edit, hunt-mode seed) flows through the same
// `switchHost()`, driven by a single settings observer, instead of duplicated
// orchestration at the call sites.
@MainActor
extension ContainerStore {

    // MARK: - Refresh

    /// Refresh container data from Docker daemon.
    /// - Parameter force: when `true`, cancel any in-flight refresh and start a
    ///   fresh one (cancel-and-restart). When `false`, join an in-flight
    ///   refresh if there is one rather than starting a second overlapping
    ///   fetch.
    public func refresh(force: Bool = false) async {
        if !force, let inFlight = refreshTask {
            logger.debug("Refresh joining in-flight refresh")
            await inFlight.value
            return
        }
        await startRefresh().value
    }

    /// Begin a new refresh: supersede any in-flight one, bump the generation,
    /// and record the task so callers can join it. Runs synchronously on the
    /// main actor up to creating the task, so state writes cannot interleave.
    @discardableResult
    func startRefresh() -> Task<Void, Never> {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        // Cancel the superseded refresh. It will observe the generation bump
        // and drop its result even if cancellation does not interrupt it.
        refreshTask?.cancel()

        isRefreshing = true

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(generation: generation)
        }
        refreshTask = task
        return task
    }

    private func performRefresh(generation: Int) async {
        guard isCurrentRefresh(generation) else { return }

        connectionError = nil
        logger.debug("Refreshing container data (gen \(generation))")

        if fetcher == nil {
            initializeFetcher()
        }

        guard isCurrentRefresh(generation) else { return }

        guard let fetcher else {
            connectionError = "Docker connection not configured"
            isConnected = false
            finishRefresh(generation)
            return
        }

        do {
            let result = try await fetcher.fetch(
                includeStats: true,
                all: settings.showStoppedContainers
            )

            // A host switch or a newer refresh may have superseded us while the
            // fetch was in flight; if so, drop this stale response entirely.
            guard isCurrentRefresh(generation) else {
                logger.debug("Dropping stale refresh result (gen \(generation), now \(refreshGeneration))")
                return
            }

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

            logger.debug("Refresh complete: \(result.containers.count) containers")
        } catch {
            guard isCurrentRefresh(generation) else { return }
            logger.error("Refresh failed: \(error.localizedDescription)")
            self.connectionError = userFriendlyConnectionErrorMessage(for: error)
            self.isConnected = false
        }

        finishRefresh(generation)
    }

    /// Whether `generation` is still the live refresh generation. A superseded
    /// refresh returns `false` and must not write any store state.
    private func isCurrentRefresh(_ generation: Int) -> Bool {
        generation == refreshGeneration
    }

    /// Clear the in-flight markers, but only for the latest refresh. A
    /// superseded refresh never reaches here, so `isRefreshing` stays `true`
    /// through a cancel-and-restart until the newest refresh completes.
    private func finishRefresh(_ generation: Int) {
        guard isCurrentRefresh(generation) else { return }
        isRefreshing = false
        refreshTask = nil
    }

    // MARK: - Host Switching

    /// Switch the live connection to the currently selected host: cancel any
    /// in-flight refresh (fencing its result via the generation bump inside
    /// `startRefresh`), clear the previous host's data, rebuild the fetcher,
    /// and start a fresh refresh. This is the single convergence point for
    /// every host-lifecycle mutation (CB-065).
    public func switchHost() {
        logger.info("Switching host, reinitializing fetcher")
        clearHostState()
        fetcher = nil
        initializeFetcher()
        lastResolvedHost = settings.selectedHost
        startRefresh()
    }

    /// Clear all per-host data so the UI does not show the previous host's
    /// containers while the new host's first refresh is in flight.
    private func clearHostState() {
        containers = []
        stats = [:]
        metricsSnapshot = nil
        metricsHistory.clearAll()
        isConnected = false
        connectionError = nil
        lastRefreshAt = nil
        rateTracker.reset()
    }

    // MARK: - Settings Observation

    /// Observe the settings that affect the live connection and the refresh
    /// timer, and converge on them. Uses the existing 100 ms
    /// `withObservationTracking` polling pattern (CB-073 tracks replacing it);
    /// this only extends the tracked keys.
    func startSettingsObservation() {
        settingsObservationTask?.cancel()

        settingsObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                withObservationTracking {
                    // Reading `selectedHost` also reads `selectedHostId` and
                    // the `hosts` array, so any host mutation re-fires
                    // `onChange`; `handleSettingsChange` then decides whether
                    // it actually changed the resolved host.
                    _ = self.settings.refreshInterval
                    _ = self.settings.selectedHost
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.handleSettingsChange()
                    }
                }

                // Small delay to coalesce changes
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Converge the live connection and timer on the current settings. Only
    /// switches the host when the *resolved* selected host actually changed, so
    /// editing or removing a non-selected host does not reinitialize the
    /// fetcher, and only restarts the timer when the interval changed.
    func handleSettingsChange() {
        let resolvedHost = settings.selectedHost
        if resolvedHost != lastResolvedHost {
            switchHost()
        }

        if settings.refreshInterval != lastRefreshInterval {
            restartTimer()
        }
    }
}
