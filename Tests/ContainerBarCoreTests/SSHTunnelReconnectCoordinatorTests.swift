import Foundation
import Testing
@testable import ContainerBarCore

@Suite("SSH Tunnel Reconnect Coordinator Tests")
struct SSHTunnelReconnectCoordinatorTests {

    /// Primary CB-067 defect-2 regression guard: N concurrent reconnects run the
    /// underlying start operation exactly once and every caller gets the same
    /// socket path, instead of each launching its own ssh.
    ///
    /// Deterministic via the probe's entry gate — `waitUntilEntered()` guarantees
    /// the first reconnect has entered and parked before the concurrent callers
    /// are issued, so they must join the in-flight task regardless of scheduling.
    @Test("reconnect coalesces concurrent callers into one start")
    func reconnectCoalescesConcurrentCallers() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(result: "/tmp/coalesced.sock")

        let first = Task { try await coordinator.reconnect { try await probe.start() } }
        await probe.waitUntilEntered()
        let second = Task { try await coordinator.reconnect { try await probe.start() } }
        let third = Task { try await coordinator.reconnect { try await probe.start() } }
        await probe.release()

        let results = try await [first.value, second.value, third.value]

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
        await probe.waitUntilEntered()
        let second = Task { try await coordinator.reconnect { try await probe.start() } }
        await probe.release()

        for task in [first, second] {
            await #expect(throws: DockerAPIError.self) {
                _ = try await task.value
            }
        }
        #expect(await probe.startCount == 1)
    }

    /// A deliberate `disconnect()` cancels the in-flight reconnect; awaiters then
    /// observe `CancellationError`, preserving genuine cancellation semantics.
    ///
    /// Deterministic: `waitUntilEntered()` confirms the reconnect task is
    /// registered before `cancelInFlight()`, and the probe parks in a
    /// cancellation-aware sleep so the cancel unblocks it.
    @Test("cancelInFlight cancels the awaiter")
    func cancelInFlightCancelsAwaiter() async throws {
        let coordinator = SSHTunnelReconnectCoordinator()
        let probe = ReconnectProbe(result: "/tmp/never.sock")

        let task = Task {
            try await coordinator.reconnect { try await probe.start() }
        }
        await probe.waitUntilEntered()
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
        let probe = ReconnectProbe(result: "/tmp/fresh.sock", autoRelease: true)

        _ = try await coordinator.reconnect { try await probe.start() }
        _ = try await coordinator.reconnect { try await probe.start() }

        #expect(await probe.startCount == 2)
    }
}

/// Injectable, deterministic stand-in for the "start a tunnel" operation, so the
/// coalescing can be exercised without launching a real ssh process.
///
/// `start()` records the invocation, signals that it has entered (so a test can
/// `waitUntilEntered()`), then parks until `release()` — or, with `autoRelease`,
/// returns immediately. The park is a cancellation-aware poll so `cancelInFlight`
/// unblocks it with `CancellationError`.
private actor ReconnectProbe {
    private(set) var startCount = 0
    private let result: String
    private let error: DockerAPIError?
    private let autoRelease: Bool

    private var entered = false
    private var released = false
    private var entryContinuation: CheckedContinuation<Void, Never>?

    init(result: String, error: DockerAPIError? = nil, autoRelease: Bool = false) {
        self.result = result
        self.error = error
        self.autoRelease = autoRelease
        self.released = autoRelease
    }

    func start() async throws -> String {
        startCount += 1
        entered = true
        entryContinuation?.resume()
        entryContinuation = nil

        while !released {
            try await Task.sleep(for: .milliseconds(5))
        }

        if let error {
            throw error
        }
        return result
    }

    /// Suspend until a call to `start()` has entered.
    func waitUntilEntered() async {
        if entered {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            entryContinuation = cont
        }
    }

    /// Let the parked `start()` complete.
    func release() {
        released = true
    }
}
