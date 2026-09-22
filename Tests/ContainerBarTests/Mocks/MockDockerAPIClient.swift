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

    // MARK: - Deterministic mid-flight gate
    //
    // When armed, the first `listContainers` call parks until `proceed()` is
    // called, and signals its arrival to any awaiter of `waitUntilEntered()`.
    // The gate auto-disarms after the first entry so a subsequent refresh
    // (e.g. a cancel-and-restart or a host switch) is not blocked. This lets a
    // test hold one refresh mid-fetch without brittle sleeps.
    private var _gateArmed = false
    private var _gateEntered = false
    private var _cancelledAfterGate = false
    private var _entryContinuation: CheckedContinuation<Void, Never>?
    private var _proceedContinuation: CheckedContinuation<Void, Never>?

    /// Whether the task that parked in the gate was cancelled by the time it
    /// was released — lets a test assert a concurrent refresh joined (did not
    /// cancel) the in-flight one.
    var cancelledAfterGate: Bool {
        stateLock.withLock { _cancelledAfterGate }
    }

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

    /// Arm the gate so the next `listContainers` parks until `proceed()`.
    func armGate() {
        stateLock.withLock {
            _gateArmed = true
            _gateEntered = false
            _cancelledAfterGate = false
            _entryContinuation = nil
            _proceedContinuation = nil
        }
    }

    /// Suspend until a gated `listContainers` call has entered the gate.
    func waitUntilEntered() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alreadyEntered = stateLock.withLock { () -> Bool in
                if _gateEntered { return true }
                _entryContinuation = cont
                return false
            }
            if alreadyEntered { cont.resume() }
        }
    }

    /// Release a parked `listContainers` call so it can complete.
    func proceed() {
        let cont = stateLock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiting = _proceedContinuation
            _proceedContinuation = nil
            return waiting
        }
        cont?.resume()
    }

    private func enterGateIfArmed() async {
        // Disarm on the first entry and capture any entry awaiter.
        let (shouldPark, entryCont) = stateLock.withLock { () -> (Bool, CheckedContinuation<Void, Never>?) in
            guard _gateArmed else { return (false, nil) }
            _gateArmed = false
            _gateEntered = true
            let waiting = _entryContinuation
            _entryContinuation = nil
            return (true, waiting)
        }
        guard shouldPark else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stateLock.withLock { _proceedContinuation = cont }
            entryCont?.resume()
        }
        let cancelled = Task.isCancelled
        stateLock.withLock { _cancelledAfterGate = cancelled }
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
        await enterGateIfArmed()
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
        try await maybeDelayResponse()
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
