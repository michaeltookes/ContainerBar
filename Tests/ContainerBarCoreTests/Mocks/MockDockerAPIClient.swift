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

    /// Optional per-call delay, applied inside `getContainerStats` so
    /// concurrent fetches genuinely overlap and the peak-concurrency
    /// instrumentation below is observable.
    private var _responseDelay: Duration?
    /// Number of `getContainerStats` calls currently in flight.
    private var _currentConcurrentStatsFetches = 0
    /// High-water mark of concurrent `getContainerStats` calls seen so far.
    private var _peakConcurrentStatsFetches = 0

    public var mockContainers: [DockerContainer] {
        stateLock.withLock { _mockContainers }
    }

    public var mockStats: [String: ContainerStats] {
        stateLock.withLock { _mockStats }
    }

    public var mockSystemInfo: DockerSystemInfo? {
        stateLock.withLock { _mockSystemInfo }
    }

    public var shouldFail: Bool {
        stateLock.withLock { _shouldFail }
    }

    public var failureError: Error {
        stateLock.withLock { _failureError }
    }

    public var callCount: Int {
        stateLock.withLock { _callCount }
    }

    public var lastCalledMethod: String? {
        stateLock.withLock { _lastCalledMethod }
    }

    public var responseDelay: Duration? {
        get { stateLock.withLock { _responseDelay } }
        set { stateLock.withLock { _responseDelay = newValue } }
    }

    /// Highest number of `getContainerStats` calls that were in flight at the
    /// same time. Used to assert the fetcher's concurrency bound.
    public var peakConcurrentStatsFetches: Int {
        stateLock.withLock { _peakConcurrentStatsFetches }
    }

    public init() {}

    public func setMockContainers(_ containers: [DockerContainer]) {
        stateLock.withLock {
            _mockContainers = containers
        }
    }

    public func appendMockContainers(_ containers: [DockerContainer]) {
        stateLock.withLock {
            _mockContainers.append(contentsOf: containers)
        }
    }

    public func updateMockContainers(_ update: (inout [DockerContainer]) -> Void) {
        stateLock.withLock {
            update(&_mockContainers)
        }
    }

    public func setMockStats(_ stats: [String: ContainerStats]) {
        stateLock.withLock {
            _mockStats = stats
        }
    }

    public func setMockStats(_ stats: ContainerStats, forContainerID id: String) {
        stateLock.withLock {
            _mockStats[id] = stats
        }
    }

    public func updateMockStats(_ update: (inout [String: ContainerStats]) -> Void) {
        stateLock.withLock {
            update(&_mockStats)
        }
    }

    public func setMockSystemInfo(_ systemInfo: DockerSystemInfo?) {
        stateLock.withLock {
            _mockSystemInfo = systemInfo
        }
    }

    public func setFailure(_ shouldFail: Bool, error: Error = DockerAPIError.connectionFailed) {
        stateLock.withLock {
            _shouldFail = shouldFail
            _failureError = error
        }
    }

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

    /// Register a `getContainerStats` call as in flight, update the peak
    /// high-water mark, and return the configured response delay — all under
    /// one lock so the peak reflects true concurrent overlap.
    private func beginStatsFetch() -> Duration? {
        stateLock.withLock {
            _currentConcurrentStatsFetches += 1
            _peakConcurrentStatsFetches = max(_peakConcurrentStatsFetches, _currentConcurrentStatsFetches)
            return _responseDelay
        }
    }

    private func endStatsFetch() {
        stateLock.withLock { _currentConcurrentStatsFetches -= 1 }
    }

    public func getContainerStats(id: String) async throws -> ContainerStats {
        recordCall("getContainerStats")
        let delay = beginStatsFetch()
        defer { endStatsFetch() }
        if let delay {
            try await Task.sleep(for: delay)
        }
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
