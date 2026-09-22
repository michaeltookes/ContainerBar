import Foundation
import Testing
@testable import ContainerBarCore

@Suite("SSH Tunnel Reconnect Coordinator Tests")
struct SSHTunnelReconnectCoordinatorTests {

    /// Primary CB-067 defect-2 regression guard: N concurrent reconnects run the
    /// underlying start operation exactly once and every caller gets the same
    /// socket path, instead of each launching its own ssh.
    @Test("reconnect coalesces concurrent callers into one start")
    func reconnectCoalescesConcurrentCallers() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(result: "/tmp/coalesced.sock")

        async let first = coordinator.reconnect { try await probe.start() }
        try await Task.sleep(for: .milliseconds(10))
        async let second = coordinator.reconnect { try await probe.start() }
        try await Task.sleep(for: .milliseconds(10))
        async let third = coordinator.reconnect { try await probe.start() }

        let results = try await [first, second, third]

        #expect(await probe.startCount == 1)
        #expect(results == ["/tmp/coalesced.sock", "/tmp/coalesced.sock", "/tmp/coalesced.sock"])
    }

    /// A superseded/failed attempt must surface its `DockerAPIError` to every
    /// coalesced caller — never a bare `CancellationError` — so `withRetry`
    /// treats it as retryable.
    @Test("reconnect propagates a DockerAPIError to all coalesced callers")
    func reconnectPropagatesDockerAPIError() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(
            result: "/tmp/unused.sock",
            error: DockerAPIError.sshConnectionFailed("superseded")
        )

        let first = Task { try await coordinator.reconnect { try await probe.start() } }
        try await Task.sleep(for: .milliseconds(10))
        let second = Task { try await coordinator.reconnect { try await probe.start() } }

        for task in [first, second] {
            await #expect(throws: DockerAPIError.self) {
                _ = try await task.value
            }
        }
        #expect(await probe.startCount == 1)
    }

    /// A deliberate `disconnect()` cancels the in-flight reconnect; awaiters then
    /// observe `CancellationError`, preserving genuine cancellation semantics.
    @Test("cancelInFlight cancels the awaiter")
    func cancelInFlightCancelsAwaiter() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(result: "/tmp/never.sock", delay: .seconds(5))

        let task = Task {
            try await coordinator.reconnect { try await probe.start() }
        }
        try await Task.sleep(for: .milliseconds(20))
        coordinator.cancelInFlight()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    /// After a reconnect completes, a subsequent call starts a fresh operation —
    /// the coordinator clears its in-flight task rather than pinning the first
    /// result forever.
    @Test("reconnect starts a fresh operation after the previous completes")
    func reconnectStartsFreshAfterCompletion() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(result: "/tmp/fresh.sock", delay: .milliseconds(5))

        _ = try await coordinator.reconnect { try await probe.start() }
        _ = try await coordinator.reconnect { try await probe.start() }

        #expect(await probe.startCount == 2)
    }
}

/// Injectable stand-in for the "start a tunnel" operation, so the coalescing can
/// be exercised without launching a real ssh process.
private actor ReconnectProbe {
    private(set) var startCount = 0
    private let result: String
    private let error: DockerAPIError?
    private let delay: Duration

    init(result: String, error: DockerAPIError? = nil, delay: Duration = .milliseconds(50)) {
        self.result = result
        self.error = error
        self.delay = delay
    }

    func start() async throws -> String {
        startCount += 1
        try await Task.sleep(for: delay)
        if let error {
            throw error
        }
        return result
    }
}
