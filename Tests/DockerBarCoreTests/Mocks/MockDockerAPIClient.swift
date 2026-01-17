import Foundation
@testable import DockerBarCore

/// Mock Docker API client for testing
public final class MockDockerAPIClient: DockerAPIClient, @unchecked Sendable {

    public var mockContainers: [DockerContainer] = []
    public var mockStats: [String: ContainerStats] = [:]
    public var mockSystemInfo: DockerSystemInfo?
    public var shouldFail = false
    public var failureError: Error = DockerAPIError.connectionFailed
    public var callCount = 0
    public var lastCalledMethod: String?

    public init() {}

    public func ping() async throws {
        callCount += 1
        lastCalledMethod = "ping"
        if shouldFail {
            throw failureError
        }
    }

    public func getSystemInfo() async throws -> DockerSystemInfo {
        callCount += 1
        lastCalledMethod = "getSystemInfo"
        if shouldFail {
            throw failureError
        }
        guard let info = mockSystemInfo else {
            throw DockerAPIError.invalidResponse
        }
        return info
    }

    public func listContainers(all: Bool) async throws -> [DockerContainer] {
        callCount += 1
        lastCalledMethod = "listContainers"
        if shouldFail {
            throw failureError
        }
        return mockContainers
    }

    public func getContainer(id: String) async throws -> DockerContainer {
        callCount += 1
        lastCalledMethod = "getContainer"
        if shouldFail {
            throw failureError
        }
        guard let container = mockContainers.first(where: { $0.id == id }) else {
            throw DockerAPIError.notFound("Container \(id)")
        }
        return container
    }

    public func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error> {
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

    public func startContainer(id: String) async throws {
        callCount += 1
        lastCalledMethod = "startContainer"
        if shouldFail {
            throw failureError
        }
    }

    public func stopContainer(id: String, timeout: Int?) async throws {
        callCount += 1
        lastCalledMethod = "stopContainer"
        if shouldFail {
            throw failureError
        }
    }

    public func restartContainer(id: String, timeout: Int?) async throws {
        callCount += 1
        lastCalledMethod = "restartContainer"
        if shouldFail {
            throw failureError
        }
    }

    public func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        callCount += 1
        lastCalledMethod = "removeContainer"
        if shouldFail {
            throw failureError
        }
    }

    public func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        callCount += 1
        lastCalledMethod = "getContainerLogs"
        if shouldFail {
            throw failureError
        }
        return "Mock log output for container \(id)"
    }
}
