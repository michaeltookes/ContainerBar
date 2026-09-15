import Foundation
@testable import ContainerBarCore

/// Mock Docker API client for testing.
///
/// The unchecked Sendable conformance is limited to tests; all mutable state is
/// synchronized through `stateLock` so task-group stats fetches can share it.
public final class MockDockerAPIClient: DockerAPIClient, @unchecked Sendable {
    private let stateLock = NSLock()

    private var _mockContainers: [DockerContainer] = []
    private var _mockStats: [String: ContainerStats] = [:]
    private var _mockSystemInfo: DockerSystemInfo?
    private var _shouldFail = false
    private var _failureError: Error = DockerAPIError.connectionFailed
    private var _callCount = 0
    private var _lastCalledMethod: String?

    public var mockContainers: [DockerContainer] {
        get { stateLock.withLock { _mockContainers } }
        set { stateLock.withLock { _mockContainers = newValue } }
    }

    public var mockStats: [String: ContainerStats] {
        get { stateLock.withLock { _mockStats } }
        set { stateLock.withLock { _mockStats = newValue } }
    }

    public var mockSystemInfo: DockerSystemInfo? {
        get { stateLock.withLock { _mockSystemInfo } }
        set { stateLock.withLock { _mockSystemInfo = newValue } }
    }

    public var shouldFail: Bool {
        get { stateLock.withLock { _shouldFail } }
        set { stateLock.withLock { _shouldFail = newValue } }
    }

    public var failureError: Error {
        get { stateLock.withLock { _failureError } }
        set { stateLock.withLock { _failureError = newValue } }
    }

    public var callCount: Int {
        get { stateLock.withLock { _callCount } }
        set { stateLock.withLock { _callCount = newValue } }
    }

    public var lastCalledMethod: String? {
        get { stateLock.withLock { _lastCalledMethod } }
        set { stateLock.withLock { _lastCalledMethod = newValue } }
    }

    public init() {}

    private func recordCall(_ method: String) {
        stateLock.withLock {
            _callCount += 1
            _lastCalledMethod = method
        }
    }

    private func failureSnapshot() -> (shouldFail: Bool, error: Error) {
        stateLock.withLock {
            (_shouldFail, _failureError)
        }
    }

    public func ping() async throws {
        recordCall("ping")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
    }

    public func getSystemInfo() async throws -> DockerSystemInfo {
        recordCall("getSystemInfo")
        let snapshot = stateLock.withLock {
            (_shouldFail, _failureError, _mockSystemInfo)
        }
        if snapshot.0 {
            throw snapshot.1
        }
        guard let info = snapshot.2 else {
            throw DockerAPIError.invalidResponse
        }
        return info
    }

    public func listContainers(all: Bool) async throws -> [DockerContainer] {
        recordCall("listContainers")
        let snapshot = stateLock.withLock {
            (_shouldFail, _failureError, _mockContainers)
        }
        if snapshot.0 {
            throw snapshot.1
        }
        return snapshot.2
    }

    public func getContainer(id: String) async throws -> DockerContainer {
        recordCall("getContainer")
        let snapshot = stateLock.withLock {
            (_shouldFail, _failureError, _mockContainers)
        }
        if snapshot.0 {
            throw snapshot.1
        }
        guard let container = snapshot.2.first(where: { $0.id == id }) else {
            throw DockerAPIError.notFound("Container \(id)")
        }
        return container
    }

    public func getContainerStats(id: String) async throws -> ContainerStats {
        recordCall("getContainerStats")
        let snapshot = stateLock.withLock {
            (_shouldFail, _failureError, _mockStats[id])
        }
        if snapshot.0 {
            throw snapshot.1
        }
        guard let stats = snapshot.2 else {
            throw DockerAPIError.notFound("Stats for \(id)")
        }
        return stats
    }

    public func startContainer(id: String) async throws {
        recordCall("startContainer")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
    }

    public func stopContainer(id: String, timeout: Int?) async throws {
        recordCall("stopContainer")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
    }

    public func restartContainer(id: String, timeout: Int?) async throws {
        recordCall("restartContainer")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
    }

    public func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        recordCall("removeContainer")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
    }

    public func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        recordCall("getContainerLogs")
        let snapshot = failureSnapshot()
        if snapshot.shouldFail {
            throw snapshot.error
        }
        return "Mock log output for container \(id)"
    }
}
