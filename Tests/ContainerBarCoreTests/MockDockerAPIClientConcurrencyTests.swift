import Foundation
import Testing
@testable import ContainerBarCore

@Suite("Mock Docker API Client Concurrency Tests")
struct MockDockerAPIClientConcurrencyTests {

    @Test("Mock client records concurrent stats fetches safely")
    func recordsConcurrentStatsFetchesSafely() async throws {
        let mock = MockDockerAPIClient()
        let containers = (1...10).map { index in
            DockerContainer.mock(id: "container-\(index)", name: "container-\(index)", state: .running)
        }
        let stats = Dictionary(uniqueKeysWithValues: containers.map { container in
            (container.id, ContainerStats.mock(containerId: container.id))
        })

        mock.setMockContainers(containers)
        mock.setMockStats(stats)

        let fetcher = ContainerFetcher(client: mock, host: .local)
        let result = try await fetcher.fetch(includeStats: true, all: true)

        #expect(result.stats.count == 10)
        #expect(mock.callCount == 11)
        #expect(mock.lastCalledMethod == "getContainerStats")
    }
}
