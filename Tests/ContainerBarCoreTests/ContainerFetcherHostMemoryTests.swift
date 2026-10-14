import Foundation
import Testing
@testable import ContainerBarCore

/// Host-memory lookup caching, retry, and cancellation (CB-069 review).
@Suite("ContainerFetcher Host Memory Tests")
struct ContainerFetcherHostMemoryTests {

    private static let gib: UInt64 = 1024 * 1024 * 1024

    private static func systemInfo(memoryTotal: UInt64) -> DockerSystemInfo {
        DockerSystemInfo(
            id: "test-host", containers: 1, containersRunning: 1, containersPaused: 0,
            containersStopped: 0, images: 1, dockerVersion: "28.0.0", operatingSystem: "Test OS",
            kernelVersion: "6.8.0", architecture: "aarch64", memoryTotal: memoryTotal,
            cpuCount: 8, serverVersion: "28.0.0"
        )
    }

    @Test("A failed refresh of a cached total is retried after 30 s, not 5 minutes")
    func failedRefreshUsesRetryInterval() async throws {
        let mock = MockDockerAPIClient()
        mock.setMockSystemInfo(Self.systemInfo(memoryTotal: 16 * Self.gib))
        let fetcher = ContainerFetcher(client: mock, host: .local)
        let start = Date(timeIntervalSince1970: 1_000_000)

        #expect(try await fetcher.currentHostMemoryTotal(now: start) == 16 * Self.gib)
        #expect(mock.callCount == 1)

        // Within the 5-minute window the cached value is reused.
        _ = try await fetcher.currentHostMemoryTotal(now: start.addingTimeInterval(299))
        #expect(mock.callCount == 1)

        // The 5-minute refresh fails: the last good total is kept.
        mock.setSystemInfoError(DockerAPIError.connectionFailed)
        let failedAt = start.addingTimeInterval(301)
        #expect(try await fetcher.currentHostMemoryTotal(now: failedAt) == 16 * Self.gib)
        #expect(mock.callCount == 2)

        // Not yet 30 s after the failure: no new request.
        _ = try await fetcher.currentHostMemoryTotal(now: failedAt.addingTimeInterval(29))
        #expect(mock.callCount == 2)

        // 30 s after the failure: retried, and the new value is picked up.
        mock.setSystemInfoError(nil)
        mock.setMockSystemInfo(Self.systemInfo(memoryTotal: 32 * Self.gib))
        #expect(try await fetcher.currentHostMemoryTotal(now: failedAt.addingTimeInterval(31)) == 32 * Self.gib)
        #expect(mock.callCount == 3)

        // After that success the 5-minute interval applies again.
        _ = try await fetcher.currentHostMemoryTotal(now: failedAt.addingTimeInterval(31 + 60))
        #expect(mock.callCount == 3)
    }

    @Test("Cancellation during the /info request propagates and does not count as a fetch success or failure")
    func cancellationDuringInfoPropagates() async throws {
        let mock = MockDockerAPIClient()
        mock.setMockContainers([DockerContainer.mock(id: "c1", name: "nginx", state: .running)])
        mock.setMockStats(ContainerStats.mock(containerId: "c1"), forContainerID: "c1")
        let fetcher = ContainerFetcher(client: mock, host: .local)

        // Prime prior data so the failure gate (threshold 2) is in play.
        _ = try await fetcher.fetch(includeStats: false, all: true)

        mock.setSystemInfoError(CancellationError())
        await #expect(throws: CancellationError.self) {
            _ = try await fetcher.fetch(includeStats: true, all: true, bypassRateLimit: true)
        }

        // The cancelled fetch did not replace the cached result: the first
        // genuine failure still returns the primed cache (gate not advanced).
        mock.setSystemInfoError(nil)
        mock.setFailure(true, error: DockerAPIError.connectionFailed)
        let cached = try await fetcher.fetch(includeStats: false, all: true, bypassRateLimit: true)
        #expect(cached.containers.map(\.id) == ["c1"])
        #expect(cached.stats.isEmpty)
    }

    @Test("An already-cancelled refresh does not spend an /info request")
    func cancelledBeforeLookupThrows() async throws {
        let mock = MockDockerAPIClient()
        mock.setMockSystemInfo(Self.systemInfo(memoryTotal: 16 * Self.gib))
        let fetcher = ContainerFetcher(client: mock, host: .local)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fetcher.currentHostMemoryTotal()
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(mock.callCount == 0)
    }
}
