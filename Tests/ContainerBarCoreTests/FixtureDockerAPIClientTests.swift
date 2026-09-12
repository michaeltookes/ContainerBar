import Testing
import Foundation
@testable import ContainerBarCore

@Suite("FixtureDockerAPIClient")
struct FixtureDockerAPIClientTests {
    @Test("Seed exposes six containers with three running")
    func seedShape() async throws {
        let client = FixtureDockerAPIClient()
        let all = try await client.listContainers(all: true)
        let active = try await client.listContainers(all: false)
        #expect(all.count == 6)
        #expect(active.count == 4)
        #expect(all.map { $0.names.first } .contains("/web"))
        let info = try await client.getSystemInfo()
        #expect(info.containersRunning == 3)
        #expect(info.containersPaused == 1)
        #expect(info.containersStopped == 2)
    }

    @Test("Stop and start mutate only in-memory state")
    func lifecycle() async throws {
        let client = FixtureDockerAPIClient()
        try await client.stopContainer(id: "web", timeout: nil)
        #expect(try await client.getContainer(id: "web").state == .exited)
        try await client.startContainer(id: "web")
        #expect(try await client.getContainer(id: "web").state == .running)
        try await client.restartContainer(id: "worker", timeout: nil)
        #expect(try await client.getContainer(id: "worker").state == .running)
    }

    @Test("Remove refuses a running container unless forced")
    func remove() async throws {
        let client = FixtureDockerAPIClient()
        await #expect(throws: DockerAPIError.self) {
            try await client.removeContainer(id: "api", force: false, volumes: false)
        }
        try await client.removeContainer(id: "api", force: true, volumes: false)
        #expect(try await client.listContainers(all: true).count == 5)
        await #expect(throws: DockerAPIError.self) {
            _ = try await client.getContainer(id: "api")
        }
    }

    @Test("Stats and logs are deterministic for a container id")
    func statsAndLogs() async throws {
        let client = FixtureDockerAPIClient()
        let a = try await client.getContainerStats(id: "a1f0c9e2b3d4")
        let b = try await client.getContainerStats(id: "a1f0c9e2b3d4")
        #expect(a.cpuPercent == b.cpuPercent)
        #expect(a.memoryUsageBytes == b.memoryUsageBytes)
        #expect(a.memoryUsageBytes > 0)
        let logs = try await client.getContainerLogs(id: "web", tail: 3, timestamps: false)
        #expect(logs.split(separator: "\n").count == 3)
        #expect(logs.contains("[web]"))
    }

    @Test("Fixture fetcher reports the fixture host")
    func fetcher() async throws {
        let fetcher = ContainerFetcher.fixture()
        let result = try await fetcher.fetch(includeStats: true, all: true)
        #expect(result.containers.count == 6)
        #expect(result.containers.allSatisfy { $0.hostId == DockerHost.fixture.id.uuidString })
        #expect(result.stats.count == 3)
        #expect(result.metrics.runningCount == 3)
    }
}
