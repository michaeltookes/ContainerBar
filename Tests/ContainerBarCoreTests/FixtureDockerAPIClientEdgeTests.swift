import Testing
import Foundation
@testable import ContainerBarCore

/// Edge-case / mutation coverage for the CB-043 fixture client, complementing
/// the happy-path suite in `FixtureDockerAPIClientTests`. Focuses on
/// addressing modes, unknown-id error paths, state-transition idempotency,
/// and recomputed system info after mutation.
@Suite("FixtureDockerAPIClient edge cases")
struct FixtureDockerAPIClientEdgeTests {

    // MARK: - Addressing modes

    @Test("Reads resolve a container by short id prefix and by name")
    func readsResolveByPrefixAndName() async throws {
        let client = FixtureDockerAPIClient()
        // Full id, short prefix, and name all resolve the same container on reads.
        let byFull = try await client.getContainer(id: "a1f0c9e2b3d4")
        let byPrefix = try await client.getContainer(id: "a1f0")
        let byName = try await client.getContainer(id: "web")
        #expect(byFull.id == byPrefix.id)
        #expect(byFull.id == byName.id)

        let statsByPrefix = try await client.getContainerStats(id: "a1f0")
        #expect(statsByPrefix.containerId == "a1f0c9e2b3d4")
    }

    @Test("Lifecycle mutations resolve by full id or name but NOT by short prefix")
    func mutationsDoNotResolveByPrefix() async throws {
        let client = FixtureDockerAPIClient()
        // By name works.
        try await client.stopContainer(id: "web", timeout: nil)
        #expect(try await client.getContainer(id: "web").state == .exited)

        // By full id works.
        try await client.startContainer(id: "a1f0c9e2b3d4")
        #expect(try await client.getContainer(id: "web").state == .running)

        // By short prefix, mutation throws notFound even though reads accept it.
        // (Documented asymmetry: transition()/removeContainer() match only
        // exact id or name, while find() also matches a prefix.)
        await expectNotFound("stop by short id prefix") {
            try await client.stopContainer(id: "a1f0", timeout: nil)
        }
        #expect(try await client.getContainer(id: "web").state == .running)
    }

    // MARK: - Unknown-id error paths

    @Test("Every operation throws notFound for an unknown id")
    func unknownIdThrows() async throws {
        let client = FixtureDockerAPIClient()
        await expectNotFound("getContainer") { _ = try await client.getContainer(id: "nope") }
        await expectNotFound("getContainerStats") { _ = try await client.getContainerStats(id: "nope") }
        await expectNotFound("getContainerLogs") {
            _ = try await client.getContainerLogs(id: "nope", tail: 1, timestamps: false)
        }
        await expectNotFound("startContainer") { try await client.startContainer(id: "nope") }
        await expectNotFound("stopContainer") { try await client.stopContainer(id: "nope", timeout: nil) }
        await expectNotFound("restartContainer") { try await client.restartContainer(id: "nope", timeout: nil) }
        await expectNotFound("removeContainer") {
            try await client.removeContainer(id: "nope", force: true, volumes: false)
        }
    }

    // MARK: - Transition idempotency & counts

    @Test("Stopping an already-exited container is idempotent")
    func stopAlreadyExitedIsIdempotent() async throws {
        let client = FixtureDockerAPIClient()
        // `worker` seeds as exited.
        #expect(try await client.getContainer(id: "worker").state == .exited)
        try await client.stopContainer(id: "worker", timeout: nil)
        #expect(try await client.getContainer(id: "worker").state == .exited)
    }

    @Test("Restart forces a paused container to running")
    func restartFromPaused() async throws {
        let client = FixtureDockerAPIClient()
        // `redis` seeds as paused.
        #expect(try await client.getContainer(id: "redis").state == .paused)
        try await client.restartContainer(id: "redis", timeout: nil)
        #expect(try await client.getContainer(id: "redis").state == .running)
    }

    @Test("listContainers(all:false) returns running+paused and excludes exited")
    func activeFilterExcludesExited() async throws {
        let client = FixtureDockerAPIClient()
        let active = try await client.listContainers(all: false)
        let names = Set(active.compactMap { $0.names.first })
        #expect(active.count == 4)
        #expect(names.contains("/redis"))   // paused is active
        #expect(!names.contains("/worker")) // exited excluded
        #expect(!names.contains("/migrate"))
    }

    @Test("getSystemInfo recomputes state counts after a mutation")
    func systemInfoRecomputes() async throws {
        let client = FixtureDockerAPIClient()
        let before = try await client.getSystemInfo()
        #expect(before.containersRunning == 3)
        #expect(before.containersStopped == 2)

        try await client.stopContainer(id: "web", timeout: nil)

        let after = try await client.getSystemInfo()
        #expect(after.containers == 6)          // stop does not remove
        #expect(after.containersRunning == 2)
        #expect(after.containersStopped == 3)
        #expect(after.containersPaused == 1)
    }

    @Test("Removing a container shrinks all subsequent listings and system info")
    func removeUpdatesCountsAndListing() async throws {
        let client = FixtureDockerAPIClient()
        try await client.removeContainer(id: "worker", force: false, volumes: false) // exited: force not required
        let all = try await client.listContainers(all: true)
        let info = try await client.getSystemInfo()
        #expect(all.count == 5)
        #expect(info.containers == 5)
        #expect(!all.contains { $0.names.first == "/worker" })
    }

    // MARK: - Logs

    @Test("Logs default to 20 lines and honor the timestamps flag")
    func logsDefaultsAndTimestamps() async throws {
        let client = FixtureDockerAPIClient()
        let defaultLog = try await client.getContainerLogs(id: "web", tail: nil, timestamps: false)
        #expect(defaultLog.split(separator: "\n").count == 20)

        let stamped = try await client.getContainerLogs(id: "web", tail: 2, timestamps: true)
        let lines = stamped.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains("2026-09-12T00:00:") })
    }

    // MARK: - Determinism across instances

    @Test("Stats are identical across independent client instances")
    func statsDeterministicAcrossInstances() async throws {
        let first = try await FixtureDockerAPIClient().getContainerStats(id: "postgres")
        let second = try await FixtureDockerAPIClient().getContainerStats(id: "postgres")
        #expect(first.cpuPercent == second.cpuPercent)
        #expect(first.memoryUsageBytes == second.memoryUsageBytes)
        #expect(first.memoryPercent == second.memoryPercent)
    }

    // MARK: - Custom seed

    @Test("A custom container set replaces the default seed entirely")
    func customSeedIsRespected() async throws {
        let only = DockerContainer.mock(id: "solo123", name: "solo", state: .running)
        let client = FixtureDockerAPIClient(containers: [only])
        let all = try await client.listContainers(all: true)
        #expect(all.count == 1)
        #expect(all.first?.names.first == "/solo")
        let info = try await client.getSystemInfo()
        #expect(info.containers == 1)
        #expect(info.containersRunning == 1)
    }

    private func expectNotFound(
        _ operationName: String,
        performing operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(operationName) to throw DockerAPIError.notFound")
        } catch let error as DockerAPIError {
            guard case .notFound = error else {
                Issue.record("Expected \(operationName) to throw DockerAPIError.notFound, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected \(operationName) to throw DockerAPIError.notFound, got \(error)")
        }
    }
}
