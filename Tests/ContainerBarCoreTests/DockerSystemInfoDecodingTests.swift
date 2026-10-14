import Foundation
import Testing
@testable import ContainerBarCore

/// `/info` must decode from the bodies real runtimes send, or the aggregate
/// memory denominator silently drops to its fallback (CB-069, Codex P1).
@Suite("DockerSystemInfo Decoding Tests")
struct DockerSystemInfoDecodingTests {

    private static let hostTotal: UInt64 = 17_179_869_184  // 16 GiB

    /// Shape of a Docker Engine 28 `/info` body (trimmed): `ServerVersion`,
    /// no `DockerVersion`, plus fields this type does not model.
    private static let dockerBody = """
    {
      "ID": "7c2f9a1e-3b4d-4e5f-8a6b-9c0d1e2f3a4b",
      "Containers": 4,
      "ContainersRunning": 3,
      "ContainersPaused": 0,
      "ContainersStopped": 1,
      "Images": 12,
      "Driver": "overlay2",
      "DockerRootDir": "/var/lib/docker",
      "MemoryLimit": true,
      "CgroupDriver": "cgroupfs",
      "CgroupVersion": "2",
      "KernelVersion": "6.10.14-linuxkit",
      "OperatingSystem": "Docker Desktop",
      "OSType": "linux",
      "Architecture": "aarch64",
      "NCPU": 8,
      "MemTotal": \(hostTotal),
      "Name": "docker-desktop",
      "ServerVersion": "28.3.0",
      "Runtimes": {"runc": {"path": "runc"}},
      "SecurityOptions": ["name=seccomp,profile=builtin", "name=cgroupns"]
    }
    """

    /// Shape of a Podman 5 compat-API `/info` body (trimmed).
    private static let podmanBody = """
    {
      "ID": "podman",
      "Containers": 5,
      "ContainersRunning": 5,
      "ContainersPaused": 0,
      "ContainersStopped": 0,
      "Images": 6,
      "Driver": "overlay",
      "KernelVersion": "6.12.5-200.fc41.aarch64",
      "OperatingSystem": "fedora",
      "OSType": "linux",
      "Architecture": "arm64",
      "NCPU": 4,
      "MemTotal": \(hostTotal),
      "Name": "localhost.localdomain",
      "ServerVersion": "5.3.1",
      "CgroupVersion": "2"
    }
    """

    private static func decode(_ body: String) throws -> DockerSystemInfo {
        try JSONDecoder().decode(DockerSystemInfo.self, from: Data(body.utf8))
    }

    @Test("Docker /info without DockerVersion decodes and yields MemTotal")
    func decodesDockerBody() throws {
        let info = try Self.decode(Self.dockerBody)
        #expect(info.memoryTotal == Self.hostTotal)
        #expect(info.serverVersion == "28.3.0")
        #expect(info.dockerVersion == "28.3.0")
        #expect(info.cpuCount == 8)
        #expect(info.containersRunning == 3)
    }

    @Test("Podman compat /info decodes and yields MemTotal")
    func decodesPodmanBody() throws {
        let info = try Self.decode(Self.podmanBody)
        #expect(info.memoryTotal == Self.hostTotal)
        #expect(info.serverVersion == "5.3.1")
        #expect(info.architecture == "arm64")
    }

    @Test("Only MemTotal is required")
    func onlyMemTotalRequired() throws {
        let info = try Self.decode("{\"MemTotal\": 1024}")
        #expect(info.memoryTotal == 1024)
        #expect(info.serverVersion.isEmpty)
        #expect(info.containers == 0)
        #expect(throws: DecodingError.self) { try Self.decode("{\"ServerVersion\": \"28.3.0\"}") }
    }

    @Test("Decoded Docker /info drives the denominator: unconstrained gives host, two 512 MiB limits give 1 GiB")
    func decodedInfoFeedsDenominator() throws {
        let host = try Self.decode(Self.dockerBody).memoryTotal
        let mib: UInt64 = 1024 * 1024
        #expect(AggregateMemoryLimit.denominator(limits: [host, host], hostMemoryTotal: host) == host)
        #expect(AggregateMemoryLimit.denominator(limits: [512 * mib, 512 * mib], hostMemoryTotal: host) == 1024 * mib)
    }
}
