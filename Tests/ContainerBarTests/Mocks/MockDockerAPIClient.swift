import Foundation
@testable import ContainerBarCore

/// Mock Docker API client for ContainerStore testing
final class MockDockerAPIClient: DockerAPIClient, @unchecked Sendable {
    private let stateLock = NSLock()

    private var _mockContainers: [DockerContainer] = []
    private var _mockStats: [String: ContainerStats] = [:]
    private var _mockSystemInfo = DockerSystemInfo(
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
    private var _shouldFail = false
    private var _failureError: Error = DockerAPIError.connectionFailed
    private var _responseDelay: Duration?
    private var _callCount = 0
    private var _lastCalledMethod: String?
    private var _calledMethods: [String] = []

    var mockContainers: [DockerContainer] {
        get { stateLock.withLock { _mockContainers } }
        set { stateLock.withLock { _mockContainers = newValue } }
    }

    var mockStats: [String: ContainerStats] {
        get { stateLock.withLock { _mockStats } }
        set { stateLock.withLock { _mockStats = newValue } }
    }

    var mockSystemInfo: DockerSystemInfo {
        get { stateLock.withLock { _mockSystemInfo } }
        set { stateLock.withLock { _mockSystemInfo = newValue } }
    }

    var shouldFail: Bool {
        get { stateLock.withLock { _shouldFail } }
        set { stateLock.withLock { _shouldFail = newValue } }
    }

    var failureError: Error {
        get { stateLock.withLock { _failureError } }
        set { stateLock.withLock { _failureError = newValue } }
    }

    var responseDelay: Duration? {
        get { stateLock.withLock { _responseDelay } }
        set { stateLock.withLock { _responseDelay = newValue } }
    }

    var callCount: Int {
        get { stateLock.withLock { _callCount } }
        set { stateLock.withLock { _callCount = newValue } }
    }

    var lastCalledMethod: String? {
        get { stateLock.withLock { _lastCalledMethod } }
        set { stateLock.withLock { _lastCalledMethod = newValue } }
    }

    var calledMethods: [String] {
        get { stateLock.withLock { _calledMethods } }
        set { stateLock.withLock { _calledMethods = newValue } }
    }

    private func recordCall(_ method: String) {
        stateLock.withLock {
            _callCount += 1
            _lastCalledMethod = method
            _calledMethods.append(method)
        }
    }

    private func failureSnapshot() -> (shouldFail: Bool, error: Error) {
        stateLock.withLock {
            (_shouldFail, _failureError)
        }
    }

    private func statsSnapshot(for id: String) -> (shouldFail: Bool, error: Error, stats: ContainerStats?) {
        stateLock.withLock {
            (_shouldFail, _failureError, _mockStats[id])
        }
    }

    private func maybeDelayResponse() async throws {
        let responseDelay = stateLock.withLock { _responseDelay }
        if let responseDelay {
            try await Task.sleep(for: responseDelay)
        }
    }

    func ping() async throws {
        recordCall("ping")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
    }

    func getSystemInfo() async throws -> DockerSystemInfo {
        recordCall("getSystemInfo")
        try await maybeDelayResponse()
        let snapshot = stateLock.withLock { (_shouldFail, _failureError, _mockSystemInfo) }
        if snapshot.0 { throw snapshot.1 }
        return snapshot.2
    }

    func listContainers(all: Bool) async throws -> [DockerContainer] {
        recordCall("listContainers")
        try await maybeDelayResponse()
        let snapshot = stateLock.withLock { (_shouldFail, _failureError, _mockContainers) }
        if snapshot.0 { throw snapshot.1 }
        return snapshot.2
    }

    func getContainer(id: String) async throws -> DockerContainer {
        recordCall("getContainer")
        try await maybeDelayResponse()
        let snapshot = stateLock.withLock { (_shouldFail, _failureError, _mockContainers) }
        if snapshot.0 { throw snapshot.1 }
        guard let container = snapshot.2.first(where: { $0.id == id }) else {
            throw DockerAPIError.notFound("Container \(id)")
        }
        return container
    }

    func getContainerStats(id: String) async throws -> ContainerStats {
        recordCall("getContainerStats")
        let snapshot = statsSnapshot(for: id)
        if snapshot.shouldFail {
            throw snapshot.error
        }
        guard let stats = snapshot.stats else {
            throw DockerAPIError.notFound("Stats for \(id)")
        }
        return stats
    }

    func startContainer(id: String) async throws {
        recordCall("startContainer")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
    }

    func stopContainer(id: String, timeout: Int?) async throws {
        recordCall("stopContainer")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
    }

    func restartContainer(id: String, timeout: Int?) async throws {
        recordCall("restartContainer")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
    }

    func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        recordCall("removeContainer")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
    }

    func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        recordCall("getContainerLogs")
        try await maybeDelayResponse()
        let snapshot = failureSnapshot()
        if snapshot.shouldFail { throw snapshot.error }
        return "Mock log output for container \(id)"
    }
}
