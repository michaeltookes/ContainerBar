import Foundation
@testable import ContainerBarCore

/// Mock Docker API client for ContainerStore testing
final class MockDockerAPIClient: DockerAPIClient, @unchecked Sendable {

    var mockContainers: [DockerContainer] = []
    var mockStats: [String: ContainerStats] = [:]
    var shouldFail = false
    var failureError: Error = DockerAPIError.connectionFailed
    var callCount = 0
    var lastCalledMethod: String?

    func ping() async throws {
        callCount += 1
        lastCalledMethod = "ping"
        if shouldFail { throw failureError }
    }

    func getSystemInfo() async throws -> DockerSystemInfo {
        callCount += 1
        lastCalledMethod = "getSystemInfo"
        if shouldFail { throw failureError }
        throw DockerAPIError.invalidResponse
    }

    func listContainers(all: Bool) async throws -> [DockerContainer] {
        callCount += 1
        lastCalledMethod = "listContainers"
        if shouldFail { throw failureError }
        return mockContainers
    }

    func getContainer(id: String) async throws -> DockerContainer {
        callCount += 1
        lastCalledMethod = "getContainer"
        if shouldFail { throw failureError }
        guard let container = mockContainers.first(where: { $0.id == id }) else {
            throw DockerAPIError.notFound("Container \(id)")
        }
        return container
    }

    func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error> {
        callCount += 1
        lastCalledMethod = "getContainerStats"
        return AsyncThrowingStream { continuation in
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
        callCount += 1
        lastCalledMethod = "startContainer"
        if shouldFail { throw failureError }
    }

    func stopContainer(id: String, timeout: Int?) async throws {
        callCount += 1
        lastCalledMethod = "stopContainer"
        if shouldFail { throw failureError }
    }

    func restartContainer(id: String, timeout: Int?) async throws {
        callCount += 1
        lastCalledMethod = "restartContainer"
        if shouldFail { throw failureError }
    }

    func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        callCount += 1
        lastCalledMethod = "removeContainer"
        if shouldFail { throw failureError }
    }

    func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        callCount += 1
        lastCalledMethod = "getContainerLogs"
        if shouldFail { throw failureError }
        return "Mock log output for container \(id)"
    }
}
