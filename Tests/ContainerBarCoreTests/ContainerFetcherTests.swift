import Foundation
import Testing
@testable import ContainerBarCore

@Suite("ContainerFetcher Tests")
struct ContainerFetcherTests {

    @Test("Fetcher returns containers from client")
    func fetchReturnsContainers() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "test1", name: "nginx", state: .running),
            DockerContainer.mock(id: "test2", name: "redis", state: .running),
            DockerContainer.mock(id: "test3", name: "postgres", state: .exited),
        ]

        let fetcher = ContainerFetcher(client: mock)
        let result = try await fetcher.fetch(includeStats: false, all: true)

        #expect(result.containers.count == 3)
        #expect(result.metrics.runningCount == 2)
        #expect(result.metrics.stoppedCount == 1)
        #expect(result.metrics.totalCount == 3)
    }

    @Test("Fetcher fetches stats for running containers only")
    func fetchStatsForRunningOnly() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "running1", name: "nginx", state: .running),
            DockerContainer.mock(id: "stopped1", name: "redis", state: .exited),
        ]
        mock.mockStats["running1"] = ContainerStats.mock(containerId: "running1", cpuPercent: 5.0)

        let fetcher = ContainerFetcher(client: mock)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        #expect(result.stats.count == 1)
        #expect(result.stats["running1"]?.cpuPercent == 5.0)
        #expect(result.stats["stopped1"] == nil)
    }

    @Test("Fetcher builds metrics snapshot correctly")
    func metricsSnapshotBuilt() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
            DockerContainer.mock(id: "c2", name: "db", state: .running),
            DockerContainer.mock(id: "c3", name: "cache", state: .paused),
            DockerContainer.mock(id: "c4", name: "worker", state: .exited),
        ]
        mock.mockStats["c1"] = ContainerStats.mock(
            containerId: "c1",
            cpuPercent: 10.0,
            memoryUsageBytes: 100_000_000,
            memoryLimitBytes: 500_000_000
        )
        mock.mockStats["c2"] = ContainerStats.mock(
            containerId: "c2",
            cpuPercent: 20.0,
            memoryUsageBytes: 200_000_000,
            memoryLimitBytes: 500_000_000
        )

        let fetcher = ContainerFetcher(client: mock)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        #expect(result.metrics.runningCount == 2)
        #expect(result.metrics.pausedCount == 1)
        #expect(result.metrics.stoppedCount == 1)
        #expect(result.metrics.totalCPUPercent == 30.0)
        #expect(result.metrics.totalMemoryUsedBytes == 300_000_000)
    }

    @Test("Fetcher start container calls client")
    func startContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        try await fetcher.startContainer(id: "test123")

        #expect(mock.lastCalledMethod == "startContainer")
        #expect(mock.callCount == 1)
    }

    @Test("Fetcher stop container calls client")
    func stopContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        try await fetcher.stopContainer(id: "test123")

        #expect(mock.lastCalledMethod == "stopContainer")
    }

    @Test("Fetcher restart container calls client")
    func restartContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        try await fetcher.restartContainer(id: "test123")

        #expect(mock.lastCalledMethod == "restartContainer")
    }

    @Test("Fetcher remove container calls client")
    func removeContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        try await fetcher.removeContainer(id: "test123", force: true)

        #expect(mock.lastCalledMethod == "removeContainer")
    }

    @Test("Fetcher get logs calls client")
    func getLogsCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        let logs = try await fetcher.getContainerLogs(id: "test123", tail: 100)

        #expect(mock.lastCalledMethod == "getContainerLogs")
        #expect(logs.contains("test123"))
    }

    @Test("Fetcher test connection calls ping")
    func testConnectionCallsPing() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock)

        try await fetcher.testConnection()

        #expect(mock.lastCalledMethod == "ping")
    }

    @Test("Fetcher throws on connection failure")
    func throwsOnConnectionFailure() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        let fetcher = ContainerFetcher(client: mock)

        do {
            _ = try await fetcher.fetch(includeStats: false, all: true)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is DockerAPIError)
        }
    }

    @Test("Fetcher respects rate limiting")
    func respectsRateLimiting() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "test1", name: "nginx", state: .running)
        ]

        let fetcher = ContainerFetcher(client: mock)

        // First fetch
        _ = try await fetcher.fetch(includeStats: false, all: true)
        let firstCallCount = mock.callCount

        // Immediate second fetch should return cached
        _ = try await fetcher.fetch(includeStats: false, all: true)
        let secondCallCount = mock.callCount

        // Should not have made additional API call due to rate limiting
        #expect(secondCallCount == firstCallCount)
    }
}
