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
}
