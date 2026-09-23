import Foundation
import Testing
@testable import ContainerBarCore

@Suite("Mock Docker API Client Concurrency Tests")
struct MockDockerAPIClientConcurrencyTests {

    @Test("Mock client records concurrent stats fetches safely")
    func recordsConcurrentStatsFetchesSafely() async throws {
        // Use more running containers than maxConcurrentStatsFetches (10) so the
        // fetcher's sliding-window limiter drains and refills, exercising the
        // mock's lock-guarded call counting across the refill boundary. This
        // asserts all-running-get-stats semantics (CB-068), not the old cap:
        // before CB-068 this would have recorded only 10 stats calls.
        let runningCount = 15
        let mock = MockDockerAPIClient()
        let containers = (1...runningCount).map { index in
            DockerContainer.mock(id: "container-\(index)", name: "container-\(index)", state: .running)
        }
        let stats = Dictionary(uniqueKeysWithValues: containers.map { container in
            (container.id, ContainerStats.mock(containerId: container.id))
        })

        mock.setMockContainers(containers)
        mock.setMockStats(stats)

        let fetcher = ContainerFetcher(client: mock, host: .local)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        #expect(result.stats.count == runningCount)
        // 1 listContainers + one getContainerStats per running container.
        #expect(mock.callCount == runningCount + 1)
        #expect(mock.lastCalledMethod == "getContainerStats")
    }

    @Test("Stats fetch bounds concurrency while covering all running containers")
    func statsFetchBoundsConcurrency() async throws {
        // More running containers than the bound so an unbounded fan-out would
        // be observable as peak concurrency well above maxConcurrentStatsFetches.
        let runningCount = 25
        let mock = MockDockerAPIClient()
        var containers: [DockerContainer] = []
        var stats: [String: ContainerStats] = [:]
        for index in 1...runningCount {
            let id = "running-\(index)"
            containers.append(DockerContainer.mock(id: id, name: "svc-\(index)", state: .running))
            stats[id] = ContainerStats.mock(
                containerId: id,
                cpuPercent: 1.0,
                memoryUsageBytes: 10_000_000
            )
        }
        mock.setMockContainers(containers)
        mock.setMockStats(stats)
        // Delay each stats call so multiple fetches overlap and the peak-
        // concurrency high-water mark reflects real in-flight overlap.
        mock.responseDelay = .milliseconds(20)

        let fetcher = ContainerFetcher(client: mock, host: .local)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        // (a) Every running container gets stats — no silent truncation.
        #expect(result.stats.count == runningCount)
        // (b) Concurrency never exceeded the bound. With 25 containers an
        // unbounded fan-out would peak near 25; the limiter must hold it at
        // or below maxConcurrentStatsFetches.
        #expect(mock.peakConcurrentStatsFetches <= ContainerFetcher.maxConcurrentStatsFetches)
        // And the fetches genuinely overlapped (the bound was actually
        // exercised, not trivially satisfied by fully serial execution).
        #expect(mock.peakConcurrentStatsFetches >= 2)
    }
}
