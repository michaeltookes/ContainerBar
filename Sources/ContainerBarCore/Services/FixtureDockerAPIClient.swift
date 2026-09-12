import Foundation

/// In-memory `DockerAPIClient` used for UI hunts and demos.
///
/// Serves a fixed set of containers and never opens a socket, tunnel, or TLS
/// connection. Lifecycle actions mutate only the in-memory state so QA runs
/// can exercise start/stop/restart/remove flows without touching a real
/// daemon. Seeded deterministically so hunts can assert on names and counts.
public actor FixtureDockerAPIClient: DockerAPIClient {
    public static let hostName = "Fixture Docker"

    private var containers: [DockerContainer]

    public init(containers: [DockerContainer] = FixtureDockerAPIClient.seedContainers()) {
        self.containers = containers
    }

    // MARK: - DockerAPIClient

    public func ping() async throws {}

    public func listContainers(all: Bool) async throws -> [DockerContainer] {
        containers.filter { all || $0.state.isActive }
    }

    public func getContainer(id: String) async throws -> DockerContainer {
        guard let container = find(id) else { throw DockerAPIError.notFound("container \(id)") }
        return container
    }

    public func getContainerStats(id: String) async throws -> ContainerStats {
        guard let container = find(id) else { throw DockerAPIError.notFound("container \(id)") }
        return Self.stats(for: container)
    }

    public func startContainer(id: String) async throws {
        try transition(id, to: .running, status: "Up 1 second")
    }

    public func stopContainer(id: String, timeout: Int?) async throws {
        try transition(id, to: .exited, status: "Exited (0) 1 second ago")
    }

    public func restartContainer(id: String, timeout: Int?) async throws {
        try transition(id, to: .running, status: "Up 1 second")
    }

    public func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        guard let index = containers.firstIndex(where: { $0.id == id || $0.names.contains("/" + id) }) else {
            throw DockerAPIError.notFound("container \(id)")
        }
        if containers[index].state.isActive && !force {
            throw DockerAPIError.conflict("container \(id) is running; use force")
        }
        containers.remove(at: index)
    }

    public func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        guard let container = find(id) else { throw DockerAPIError.notFound("container \(id)") }
        let name = container.names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? id
        let lines = (1...(tail ?? 20)).map { line -> String in
            let body = "[\(name)] fixture log line \(line)"
            return timestamps ? "2026-09-12T00:00:\(String(format: "%02d", line % 60))Z \(body)" : body
        }
        return lines.joined(separator: "\n")
    }

    public func getSystemInfo() async throws -> DockerSystemInfo {
        let running = containers.filter { $0.state == .running }.count
        let paused = containers.filter { $0.state == .paused }.count
        return DockerSystemInfo(
            id: "fixture-host",
            containers: containers.count,
            containersRunning: running,
            containersPaused: paused,
            containersStopped: containers.count - running - paused,
            images: 6,
            dockerVersion: "28.3.0",
            operatingSystem: "Fixture OS",
            kernelVersion: "6.8.0-fixture",
            architecture: "aarch64",
            memoryTotal: 16 * 1024 * 1024 * 1024,
            cpuCount: 8,
            serverVersion: "28.3.0"
        )
    }

    // MARK: - Helpers

    private func find(_ id: String) -> DockerContainer? {
        containers.first { $0.id == id || $0.id.hasPrefix(id) || $0.names.contains("/" + id) }
    }

    private func transition(_ id: String, to state: ContainerState, status: String) throws {
        guard let index = containers.firstIndex(where: { $0.id == id || $0.names.contains("/" + id) }) else {
            throw DockerAPIError.notFound("container \(id)")
        }
        let old = containers[index]
        containers[index] = DockerContainer(
            id: old.id,
            names: old.names,
            image: old.image,
            imageID: old.imageID,
            command: old.command,
            created: old.created,
            state: state,
            status: status,
            ports: old.ports,
            labels: old.labels,
            networkMode: old.networkMode,
            runtime: old.runtime,
            hostId: old.hostId
        )
    }

    // MARK: - Seed data

    /// Deterministic stats so sparkline and gauge views render non-zero values.
    static func stats(for container: DockerContainer) -> ContainerStats {
        let seed = container.id.unicodeScalars.reduce(UInt64(0)) { $0 + UInt64($1.value) } % 1000
        let limit: UInt64 = 2 * 1024 * 1024 * 1024
        let used = 64 * 1024 * 1024 + seed * 512 * 1024
        return ContainerStats(
            containerId: container.id,
            timestamp: Date(),
            cpuPercent: Double(seed % 40) + 1.5,
            cpuSystemUsage: 1_000_000_000 + seed * 10_000,
            cpuContainerUsage: 100_000_000 + seed * 1_000,
            onlineCPUs: 8,
            memoryUsageBytes: used,
            memoryLimitBytes: limit,
            memoryPercent: Double(used) / Double(limit) * 100,
            memoryCache: nil,
            networkRxBytes: 10_000_000 + seed * 1_000,
            networkTxBytes: 5_000_000 + seed * 500,
            networkRxPackets: 10_000 + seed,
            networkTxPackets: 5_000 + seed,
            blockReadBytes: 20_000_000,
            blockWriteBytes: 8_000_000
        )
    }

    public static func seedContainers() -> [DockerContainer] {
        let base = Date(timeIntervalSince1970: 1_757_600_000)
        func make(_ id: String, _ name: String, _ image: String, _ state: ContainerState,
                  _ status: String, ports: [PortMapping] = [], labels: [String: String] = [:]) -> DockerContainer {
            DockerContainer(
                id: id,
                names: ["/" + name],
                image: image,
                imageID: "sha256:" + String(repeating: id.first ?? "0", count: 12),
                command: "/entrypoint.sh",
                created: base.addingTimeInterval(-Double(id.count) * 3600),
                state: state,
                status: status,
                ports: ports,
                labels: labels,
                networkMode: "bridge"
            )
        }
        return [
            make("a1f0c9e2b3d4", "web", "nginx:1.27", .running, "Up 3 hours",
                 ports: [PortMapping(privatePort: 80, publicPort: 8080, type: "tcp", ip: "0.0.0.0")],
                 labels: ["com.docker.compose.project": "fixture"]),
            make("b2e1d0f3c4a5", "api", "ghcr.io/fixture/api:2.1", .running, "Up 3 hours",
                 ports: [PortMapping(privatePort: 3000, publicPort: 3000, type: "tcp", ip: "0.0.0.0")],
                 labels: ["com.docker.compose.project": "fixture"]),
            make("c3d2e1a4b5f6", "postgres", "postgres:16", .running, "Up 3 hours (healthy)",
                 ports: [PortMapping(privatePort: 5432, publicPort: nil, type: "tcp", ip: nil)],
                 labels: ["com.docker.compose.project": "fixture"]),
            make("d4c3b2a5e6f7", "redis", "redis:7-alpine", .paused, "Up 2 hours (Paused)"),
            make("e5b4a3c6d7f8", "worker", "ghcr.io/fixture/worker:2.1", .exited, "Exited (0) 40 minutes ago"),
            make("f6a5b4d7e8c9", "migrate", "ghcr.io/fixture/migrate:2.1", .exited, "Exited (1) 2 days ago")
        ]
    }
}

extension DockerHost {
    /// Host shown in the UI while the fixture client is active.
    public static var fixture: DockerHost {
        DockerHost(
            id: UUID(uuidString: "F1A7E000-0000-4000-8000-000000000001") ?? UUID(),
            name: FixtureDockerAPIClient.hostName,
            connectionType: .unixSocket,
            runtime: .docker,
            isDefault: true,
            socketPath: "/dev/null"
        )
    }
}

extension ContainerFetcher {
    /// Fetcher backed by the in-memory fixture client.
    public static func fixture(client: FixtureDockerAPIClient = FixtureDockerAPIClient()) -> ContainerFetcher {
        ContainerFetcher(client: client, host: .fixture)
    }
}
