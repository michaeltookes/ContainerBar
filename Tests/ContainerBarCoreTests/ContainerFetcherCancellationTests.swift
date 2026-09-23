import Foundation
import Testing
@testable import ContainerBarCore

/// Cancellation handling in `ContainerFetcher.fetch` (CB-064 review): a
/// cancellation is not a connection failure and must not advance the
/// `ConsecutiveFailureGate`. Split into its own suite so `ContainerFetcherTests`
/// stays under the type-body-length guideline.
@Suite("ContainerFetcher Cancellation Tests")
struct ContainerFetcherCancellationTests {

    private static let testHost = DockerHost.local

    @Test("Cancelled fetch propagates and does not advance the failure gate")
    func cancelledFetchDoesNotCountAsFailure() async throws {
        let mock = MockDockerAPIClient()
        mock.setMockContainers([
            DockerContainer.mock(id: "c1", name: "nginx", state: .running)
        ])

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        // Prime prior data so the failure gate's threshold (2) is in play; a
        // failure with prior data is only surfaced on the second consecutive
        // failure, otherwise the stale cache is returned.
        _ = try await fetcher.fetch(includeStats: false, all: true)

        // Past the fetcher's 1s rate limit so the next fetch reaches the client.
        try await Task.sleep(for: .seconds(1.1))

        // A cancellation must propagate rather than being swallowed into a
        // cached result. Without the guard this would instead return the cache
        // (gate at 1 < threshold) and silently advance the gate.
        mock.setFailure(true, error: CancellationError())
        await #expect(throws: CancellationError.self) {
            _ = try await fetcher.fetch(includeStats: false, all: true)
        }

        // The gate is still at zero: the very next genuine transient failure
        // returns the cached result (1 < threshold) instead of surfacing. If
        // the cancellation had advanced the gate, this would throw instead.
        mock.setFailure(true, error: DockerAPIError.connectionFailed)
        let cached = try await fetcher.fetch(includeStats: false, all: true)
        #expect(cached.containers.map(\.id) == ["c1"])
    }

    @Test("Cancelling a large stats fetch stops the sliding-window refill")
    func cancelledStatsFetchStopsRefilling() async throws {
        // Regression guard (CB-068 review): the sliding-window limiter must not
        // keep enqueueing stats calls after the parent refresh is cancelled
        // (a host switch since CB-064). With `addTaskUnlessCancelled`, a
        // cancelled refresh drains the primed wave and stops instead of issuing
        // all N requests against a fetcher the store has already discarded.
        let runningCount = 25
        let mock = MockDockerAPIClient()
        var containers: [DockerContainer] = []
        var stats: [String: ContainerStats] = [:]
        for index in 1...runningCount {
            let id = "running-\(index)"
            containers.append(DockerContainer.mock(id: id, name: "svc-\(index)", state: .running))
            stats[id] = ContainerStats.mock(containerId: id)
        }
        mock.setMockContainers(containers)
        mock.setMockStats(stats)
        // Hold stats calls open so the primed wave is still in flight when we
        // cancel. Refill only happens after a call completes, so it cannot run
        // before the cancellation even if the test runner is descheduled.
        mock.holdStatsResponses()

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
        let task = Task.detached(priority: .userInitiated) {
            try await fetcher.fetch(includeStats: true, all: true)
        }
        await Task.yield()

        // Wait until the first wave of stats calls has entered the client. The
        // bounded barrier fails the test promptly if a limiter regression means
        // the expected wave is never scheduled.
        let firstWaveStatsCalls = ContainerFetcher.maxConcurrentStatsFetches
        guard await mock.waitForStatsCalls(atLeast: firstWaveStatsCalls) else {
            task.cancel()
            mock.releaseStatsResponses()
            _ = try? await task.value
            Issue.record("Timed out waiting for the first stats-fetch wave")
            return
        }

        task.cancel()
        guard await mock.waitForHeldStatsCancellations(atLeast: firstWaveStatsCalls) else {
            mock.releaseStatsResponses()
            _ = try? await task.value
            Issue.record("Timed out waiting for the held stats-fetch wave to observe cancellation")
            return
        }

        // No more than the primed wave was ever issued — the refill loop stopped
        // rather than firing all 25 doomed requests.
        mock.releaseStatsResponses()
        _ = try? await task.value

        let firstWaveCalls = 1 + firstWaveStatsCalls
        #expect(mock.statsCallCount <= firstWaveStatsCalls)
        #expect(mock.callCount <= firstWaveCalls)
    }
}
