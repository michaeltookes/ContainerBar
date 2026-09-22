import Foundation
import Testing
@testable import ContainerBarCore

/// Rate-limit bypass in `ContainerFetcher.fetch` (CB-064 review): a forced
/// refresh must reach the daemon even inside the 1s rate-limit window, so a
/// post-action refresh reflects the mutation instead of the cached pre-action
/// list. Split into its own suite so `ContainerFetcherTests` stays under the
/// type-body-length guideline.
@Suite("ContainerFetcher Rate-Limit Tests")
struct ContainerFetcherRateLimitTests {

    private static let testHost = DockerHost.local

    @Test("bypassRateLimit hits the daemon within the rate-limit window")
    func bypassRateLimitHitsDaemon() async throws {
        let mock = MockDockerAPIClient()
        mock.setMockContainers([
            DockerContainer.mock(id: "c1", name: "nginx", state: .running)
        ])

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        // First fetch populates the cache and sets lastFetchTime. With
        // includeStats: false the only client call is listContainers, so
        // callCount tracks the number of daemon round-trips.
        _ = try await fetcher.fetch(includeStats: false, all: true)
        #expect(mock.callCount == 1)

        // A second fetch inside the 1s window normally returns the cache
        // without touching the daemon.
        _ = try await fetcher.fetch(includeStats: false, all: true)
        #expect(mock.callCount == 1)

        // bypassRateLimit forces a real fetch even inside the window, so the
        // changed container list is observed rather than the cached one.
        mock.setMockContainers([
            DockerContainer.mock(id: "c1", name: "nginx", state: .running),
            DockerContainer.mock(id: "c2", name: "redis", state: .running)
        ])
        let result = try await fetcher.fetch(includeStats: false, all: true, bypassRateLimit: true)

        #expect(mock.callCount == 2)
        #expect(result.containers.map(\.id) == ["c1", "c2"])
    }
}
