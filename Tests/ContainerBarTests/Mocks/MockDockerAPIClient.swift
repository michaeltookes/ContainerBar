import Foundation
@testable import ContainerBarCore

/// Mock Docker API client for ContainerStore testing
final class MockDockerAPIClient: DockerAPIClient, @unchecked Sendable {

    var mockContainers: [DockerContainer] = []
    var mockStats: [String: ContainerStats] = [:]
    var mockSystemInfo = DockerSystemInfo(
        id: "mock-host",
        containers: 0,
        containersRunning: 0,
        containersPaused: 0,
        containersStopped: 0,
        images: 0,
        dockerVersion: "27.0.0",
        operatingSystem: "macOS",
        kernelVersion: "24.0.0",
        architecture: "arm64",
        memoryTotal: 0,
        cpuCount: 8,
        serverVersion: "27.0.0"
    )
    var shouldFail = false
    var failureError: Error = DockerAPIError.connectionFailed
    var callCount = 0
    var lastCalledMethod: String?
    var calledMethods: [String] = []

    private func recordCall(_ method: String) {
        callCount += 1
        lastCalledMethod = method
        calledMethods.append(method)
    }

    func ping() async throws {
        recordCall("ping")
        if shouldFail { throw failureError }
    }

    func getSystemInfo() async throws -> DockerSystemInfo {
        recordCall("getSystemInfo")
        if shouldFail { throw failureError }
        return mockSystemInfo
    }

    func listContainers(all: Bool) async throws -> [DockerContainer] {
        recordCall("listContainers")
        if shouldFail { throw failureError }
        return mockContainers
    }

    func getContainer(id: String) async throws -> DockerContainer {
        recordCall("getContainer")
        if shouldFail { throw failureError }
        guard let container = mockContainers.first(where: { $0.id == id }) else {
            throw DockerAPIError.notFound("Container \(id)")
        }
        return container
    }

    func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error> {
        recordCall("getContainerStats")
        return AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            if self.shouldFail {
                continuation.finish(throwing: self.failureError)
            } else if let stats = self.mockStats[id] {
                continuation.yield(stats)
                continuation.finish()
            } else {
                continuation.finish()
            }
        }
    }

    func startContainer(id: String) async throws {
        recordCall("startContainer")
        if shouldFail { throw failureError }
    }

    func stopContainer(id: String, timeout: Int?) async throws {
        recordCall("stopContainer")
        if shouldFail { throw failureError }
    }

    func restartContainer(id: String, timeout: Int?) async throws {
        recordCall("restartContainer")
        if shouldFail { throw failureError }
    }

    func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        recordCall("removeContainer")
        if shouldFail { throw failureError }
    }

    func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        recordCall("getContainerLogs")
        if shouldFail { throw failureError }
        return "Mock log output for container \(id)"
    }
}
