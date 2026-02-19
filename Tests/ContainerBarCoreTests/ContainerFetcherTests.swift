import Foundation
import Testing
@testable import ContainerBarCore

@Suite("ContainerFetcher Tests")
struct ContainerFetcherTests {

    /// Test host for use in tests
    private static let testHost = DockerHost.local

    @Test("Fetcher returns containers from client")
    func fetchReturnsContainers() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "test1", name: "nginx", state: .running),
            DockerContainer.mock(id: "test2", name: "redis", state: .running),
            DockerContainer.mock(id: "test3", name: "postgres", state: .exited),
        ]

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
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

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
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

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
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
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        try await fetcher.startContainer(id: "test123")

        #expect(mock.lastCalledMethod == "startContainer")
        #expect(mock.callCount == 1)
    }

    @Test("Fetcher stop container calls client")
    func stopContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        try await fetcher.stopContainer(id: "test123")

        #expect(mock.lastCalledMethod == "stopContainer")
    }

    @Test("Fetcher restart container calls client")
    func restartContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        try await fetcher.restartContainer(id: "test123")

        #expect(mock.lastCalledMethod == "restartContainer")
    }

    @Test("Fetcher remove container calls client")
    func removeContainerCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        try await fetcher.removeContainer(id: "test123", force: true)

        #expect(mock.lastCalledMethod == "removeContainer")
    }

    @Test("Fetcher get logs calls client")
    func getLogsCallsClient() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        let logs = try await fetcher.getContainerLogs(id: "test123", tail: 100)

        #expect(mock.lastCalledMethod == "getContainerLogs")
        #expect(logs.contains("test123"))
    }

    @Test("Fetcher test connection calls ping")
    func testConnectionCallsPing() async throws {
        let mock = MockDockerAPIClient()
        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        try await fetcher.testConnection()

        #expect(mock.lastCalledMethod == "ping")
    }

    @Test("Fetcher throws on connection failure")
    func throwsOnConnectionFailure() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

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

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)

        // First fetch
        _ = try await fetcher.fetch(includeStats: false, all: true)
        let firstCallCount = mock.callCount

        // Immediate second fetch should return cached
        _ = try await fetcher.fetch(includeStats: false, all: true)
        let secondCallCount = mock.callCount

        // Should not have made additional API call due to rate limiting
        #expect(secondCallCount == firstCallCount)
    }

    // MARK: - Container Count Change Tests

    @Test("Fetcher handles container count increase between fetches")
    func containerCountIncreaseBetweenFetches() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "nginx", state: .running),
            DockerContainer.mock(id: "c2", name: "redis", state: .running),
            DockerContainer.mock(id: "c3", name: "postgres", state: .exited),
        ]

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
        let firstResult = try await fetcher.fetch(includeStats: false, all: true)

        #expect(firstResult.containers.count == 3)
        #expect(firstResult.metrics.runningCount == 2)

        // Simulate 2 new containers appearing
        mock.mockContainers.append(contentsOf: [
            DockerContainer.mock(id: "c4", name: "grafana", state: .running),
            DockerContainer.mock(id: "c5", name: "prometheus", state: .running),
        ])

        // Wait past rate limit
        try await Task.sleep(for: .seconds(1.1))

        let secondResult = try await fetcher.fetch(includeStats: false, all: true)

        #expect(secondResult.containers.count == 5)
        #expect(secondResult.metrics.runningCount == 4)
        #expect(secondResult.metrics.stoppedCount == 1)
        #expect(secondResult.metrics.totalCount == 5)
    }

    @Test("Fetcher handles container count decrease between fetches")
    func containerCountDecreaseBetweenFetches() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "nginx", state: .running),
            DockerContainer.mock(id: "c2", name: "redis", state: .running),
            DockerContainer.mock(id: "c3", name: "postgres", state: .running),
            DockerContainer.mock(id: "c4", name: "grafana", state: .exited),
            DockerContainer.mock(id: "c5", name: "prometheus", state: .exited),
        ]

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
        let firstResult = try await fetcher.fetch(includeStats: false, all: true)

        #expect(firstResult.containers.count == 5)

        // Simulate 2 containers removed
        mock.mockContainers = Array(mock.mockContainers.prefix(3))

        try await Task.sleep(for: .seconds(1.1))

        let secondResult = try await fetcher.fetch(includeStats: false, all: true)

        #expect(secondResult.containers.count == 3)
        #expect(secondResult.metrics.runningCount == 3)
        #expect(secondResult.metrics.stoppedCount == 0)
    }

    @Test("Fetcher handles large container count with stats cap")
    func largeContainerCountFetch() async throws {
        let mock = MockDockerAPIClient()

        // 20 running + 5 stopped = 25 total (mimics Beelink host)
        var containers: [DockerContainer] = []
        for i in 1...20 {
            let id = "running\(i)"
            containers.append(DockerContainer.mock(id: id, name: "svc-\(i)", state: .running))
            mock.mockStats[id] = ContainerStats.mock(
                containerId: id,
                cpuPercent: 2.0,
                memoryUsageBytes: 50_000_000
            )
        }
        for i in 1...5 {
            containers.append(DockerContainer.mock(id: "stopped\(i)", name: "old-\(i)", state: .exited))
        }
        mock.mockContainers = containers

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        #expect(result.containers.count == 25)
        #expect(result.metrics.runningCount == 20)
        #expect(result.metrics.stoppedCount == 5)
        #expect(result.metrics.totalCount == 25)

        // Stats capped at maxConcurrentStatsFetches (10)
        #expect(result.stats.count == 10)
    }

    @Test("Metrics snapshot updates correctly when containers change")
    func metricsSnapshotUpdatesOnContainerChange() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
            DockerContainer.mock(id: "c2", name: "db", state: .running),
        ]
        mock.mockStats["c1"] = ContainerStats.mock(containerId: "c1", cpuPercent: 10.0, memoryUsageBytes: 100_000_000)
        mock.mockStats["c2"] = ContainerStats.mock(containerId: "c2", cpuPercent: 15.0, memoryUsageBytes: 200_000_000)

        let fetcher = ContainerFetcher(client: mock, host: Self.testHost)
        let firstResult = try await fetcher.fetch(includeStats: true, all: true)

        #expect(firstResult.metrics.totalCPUPercent == 25.0)
        #expect(firstResult.metrics.totalMemoryUsedBytes == 300_000_000)

        // Add 3 more containers with different stats
        mock.mockContainers.append(contentsOf: [
            DockerContainer.mock(id: "c3", name: "cache", state: .running),
            DockerContainer.mock(id: "c4", name: "worker", state: .running),
            DockerContainer.mock(id: "c5", name: "proxy", state: .running),
        ])
        mock.mockStats["c3"] = ContainerStats.mock(containerId: "c3", cpuPercent: 5.0, memoryUsageBytes: 50_000_000)
        mock.mockStats["c4"] = ContainerStats.mock(containerId: "c4", cpuPercent: 30.0, memoryUsageBytes: 400_000_000)
        mock.mockStats["c5"] = ContainerStats.mock(containerId: "c5", cpuPercent: 8.0, memoryUsageBytes: 80_000_000)

        try await Task.sleep(for: .seconds(1.1))

        let secondResult = try await fetcher.fetch(includeStats: true, all: true)

        #expect(secondResult.metrics.runningCount == 5)
        #expect(secondResult.metrics.totalCPUPercent == 68.0)
        #expect(secondResult.metrics.totalMemoryUsedBytes == 830_000_000)
    }
}
