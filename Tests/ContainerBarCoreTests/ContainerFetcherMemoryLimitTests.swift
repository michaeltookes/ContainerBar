import Foundation
import Testing
@testable import ContainerBarCore

/// CB-069 repro: `ContainerFetcher.buildMetricsSnapshot` used to sum every
/// container's reported limit, so unconstrained containers (which report the
/// host total, or 0 on some Podman versions) inflated the denominator.
@Suite("ContainerFetcher Memory Limit Tests")
struct ContainerFetcherMemoryLimitTests {

    private static let gib: UInt64 = 1024 * 1024 * 1024
    private static let mib: UInt64 = 1024 * 1024
    private static let host: UInt64 = 16 * gib

    // MARK: - Fixtures

    private static func systemInfo(memoryTotal: UInt64) -> DockerSystemInfo {
        DockerSystemInfo(
            id: "test-host",
            containers: 3,
            containersRunning: 3,
            containersPaused: 0,
            containersStopped: 0,
            images: 1,
            dockerVersion: "28.0.0",
            operatingSystem: "Test OS",
            kernelVersion: "6.8.0",
            architecture: "aarch64",
            memoryTotal: memoryTotal,
            cpuCount: 8,
            serverVersion: "28.0.0"
        )
    }

    /// Decode a `/containers/{id}/stats` payload. `limitJSON` is the raw
    /// `memory_stats.limit` fragment, or nil to omit the key entirely.
    private static func decodedStats(id: String, usage: UInt64, limitJSON: String?) throws -> ContainerStats {
        let limitField = limitJSON.map { ", \"limit\": \($0)" } ?? ""
        let json = """
        {
          "read": "2026-01-17T12:00:00Z",
          "preread": "2026-01-17T11:59:59Z",
          "cpu_stats": {"cpu_usage": {"total_usage": 1010}, "system_cpu_usage": 20000, "online_cpus": 4},
          "precpu_stats": {"cpu_usage": {"total_usage": 1000}, "system_cpu_usage": 10000, "online_cpus": 4},
          "memory_stats": {"usage": \(usage)\(limitField)},
          "blkio_stats": {}
        }
        """
        let raw = try JSONDecoder().decode(DockerRawStats.self, from: Data(json.utf8))
        return try ContainerStats(from: raw, containerId: id)
    }

    /// A mock with one running container per stats entry and the given `/info`.
    private static func mock(stats: [ContainerStats], hostMemory: UInt64?) -> MockDockerAPIClient {
        let mock = MockDockerAPIClient()
        mock.setMockContainers(stats.map {
            DockerContainer.mock(id: $0.containerId, name: $0.containerId, state: .running)
        })
        for entry in stats {
            mock.setMockStats(entry, forContainerID: entry.containerId)
        }
        mock.setMockSystemInfo(hostMemory.map { systemInfo(memoryTotal: $0) })
        return mock
    }

    private static func snapshot(_ mock: MockDockerAPIClient) async throws -> ContainerMetricsSnapshot {
        let fetcher = ContainerFetcher(client: mock, host: .local)
        return try await fetcher.fetch(includeStats: true, all: true).metrics
    }

    // MARK: - Docker shape (unconstrained limit = host MemTotal)

    @Test("Docker: three unconstrained containers on a 16 GiB host give a 16 GiB denominator, not 48")
    func dockerThreeUnconstrained() async throws {
        let stats = try (1...3).map {
            try Self.decodedStats(id: "c\($0)", usage: Self.gib, limitJSON: "\(Self.host)")
        }
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))

        #expect(metrics.totalMemoryLimitBytes == Self.host)
        #expect(metrics.totalMemoryUsedBytes == 3 * Self.gib)
        // Status-icon fraction is used / host.
        #expect(abs(metrics.memoryUsagePercent - 3.0 / 16.0 * 100) < 0.0001)
        #expect(abs(metrics.totalMemoryLimitMB / 1024 - 16.0) < 0.0001)
    }

    @Test("Docker: 256 MiB limited plus two unconstrained gives the host denominator and trips the 95% warning")
    func dockerMixedTripsWarning() async throws {
        let stats = [
            try Self.decodedStats(id: "limited", usage: 200 * Self.mib, limitJSON: "\(256 * Self.mib)"),
            try Self.decodedStats(id: "free1", usage: 8 * Self.gib, limitJSON: "\(Self.host)"),
            try Self.decodedStats(id: "free2", usage: 7 * Self.gib + 600 * Self.mib, limitJSON: "\(Self.host)")
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))

        #expect(metrics.totalMemoryLimitBytes == Self.host)
        #expect(Double(metrics.totalMemoryUsedBytes) / Double(Self.host) > 0.95)
        #expect(metrics.overallHealth == .warning)
    }

    // MARK: - Podman shape (unconstrained limit = 0 or absent)

    @Test("Podman: limited plus unconstrained reporting 0 or no limit gives the host denominator, usage still counted")
    func podmanMixedZeroAndMissing() async throws {
        let stats = [
            try Self.decodedStats(id: "limited", usage: 100 * Self.mib, limitJSON: "\(256 * Self.mib)"),
            try Self.decodedStats(id: "zero", usage: Self.gib, limitJSON: "0"),
            try Self.decodedStats(id: "absent", usage: Self.gib, limitJSON: nil)
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))

        #expect(metrics.totalMemoryLimitBytes == Self.host)
        #expect(metrics.totalMemoryUsedBytes == 2 * Self.gib + 100 * Self.mib)
        #expect(metrics.overallHealth == .healthy)
    }

    @Test("Podman: limited plus unconstrained reporting the host total gives the host denominator")
    func podmanMixedHostTotal() async throws {
        let stats = [
            try Self.decodedStats(id: "limited", usage: 100 * Self.mib, limitJSON: "\(256 * Self.mib)"),
            try Self.decodedStats(id: "free", usage: Self.gib, limitJSON: "\(Self.host)")
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))
        #expect(metrics.totalMemoryLimitBytes == Self.host)
    }

    @Test("Every container limited: denominator is the sum of the real limits")
    func allLimited() async throws {
        let stats = [
            try Self.decodedStats(id: "a", usage: 100 * Self.mib, limitJSON: "\(256 * Self.mib)"),
            try Self.decodedStats(id: "b", usage: 100 * Self.mib, limitJSON: "\(512 * Self.mib)")
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))
        #expect(metrics.totalMemoryLimitBytes == 768 * Self.mib)
    }

    @Test("Two containers capped at 512 MiB give a 1 GiB denominator, not the host")
    func twoCappedContainers() async throws {
        let stats = [
            try Self.decodedStats(id: "a", usage: 100 * Self.mib, limitJSON: "\(512 * Self.mib)"),
            try Self.decodedStats(id: "b", usage: 100 * Self.mib, limitJSON: "\(512 * Self.mib)")
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: Self.host))
        #expect(metrics.totalMemoryLimitBytes == Self.gib)
    }

    // MARK: - Failure path

    @Test("/info fails: denominator falls back to the de-duplicated sum, no crash")
    func infoFailsFallsBack() async throws {
        let stats = [
            try Self.decodedStats(id: "limited", usage: 100 * Self.mib, limitJSON: "\(256 * Self.mib)"),
            try Self.decodedStats(id: "free1", usage: Self.gib, limitJSON: "\(Self.host)"),
            try Self.decodedStats(id: "free2", usage: Self.gib, limitJSON: "\(Self.host)")
        ]
        // No system info set: the mock's getSystemInfo throws.
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: nil))

        #expect(metrics.totalMemoryLimitBytes == Self.host + 256 * Self.mib)
        #expect(metrics.totalMemoryLimitMB > 0)
    }

    @Test("/info reports MemTotal = 0 and every limit is 0: zero denominator, no division by zero")
    func infoZeroAllZeroLimits() async throws {
        let stats = [
            try Self.decodedStats(id: "a", usage: Self.gib, limitJSON: "0"),
            try Self.decodedStats(id: "b", usage: Self.gib, limitJSON: "0")
        ]
        let metrics = try await Self.snapshot(Self.mock(stats: stats, hostMemory: 0))

        #expect(metrics.totalMemoryLimitBytes == 0)
        #expect(metrics.memoryUsagePercent == 0)
        #expect(metrics.overallHealth == .unknown)
        #expect(metrics.totalMemoryUsedBytes == 2 * Self.gib)
    }

    @Test("Host memory is cached across refreshes")
    func hostMemoryIsCached() async throws {
        let stats = [try Self.decodedStats(id: "a", usage: Self.gib, limitJSON: "\(Self.host)")]
        let mock = Self.mock(stats: stats, hostMemory: Self.host)
        let fetcher = ContainerFetcher(client: mock, host: .local)

        _ = try await fetcher.fetch(includeStats: true, all: true)
        let afterFirst = mock.callCount
        // list + stats + info on the first refresh.
        #expect(afterFirst == 3)

        _ = try await fetcher.fetch(includeStats: true, all: true, bypassRateLimit: true)
        // list + stats only; /info is reused.
        #expect(mock.callCount == afterFirst + 2)
    }
}
