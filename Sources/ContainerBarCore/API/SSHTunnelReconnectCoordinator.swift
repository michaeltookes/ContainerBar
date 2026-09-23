import Foundation

/// Coalesces concurrent SSH-tunnel reconnect attempts behind a single in-flight
/// task.
///
/// `ContainerFetcher.fetchStatsForContainers` fans out up to 10 concurrent
/// requests; when the tunnel has died each would call `reconnect()`. Without
/// coalescing every caller launched its own `ssh`, all but one were then torn
/// down by the next teardown, and the losing tasks surfaced a bare
/// `CancellationError` — which is not a `DockerAPIError`, so the retry layer
/// refused to retry it and the store reported a connection error even though a
/// reconnect had actually succeeded.
///
/// This mirrors `TLSConnectCoordinator.reconnect`'s single-flight structure, but
/// fits `SSHTunnelConnection`'s `NSLock`-based `@unchecked Sendable` model rather
/// than being an actor: `reconnectTask`/`reconnectTaskID` are guarded by an
/// `NSLock` and the task clears itself on completion, exactly like
/// `clearConnectTaskIfCurrent`.
final class SSHTunnelReconnectCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let onReuseInFlightTask: (@Sendable () async -> Void)?
    private var reconnectTask: Task<String, Error>?
    private var reconnectTaskID: UUID?

    init(onReuseInFlightTask: (@Sendable () async -> Void)? = nil) {
        self.onReuseInFlightTask = onReuseInFlightTask
    }

    /// Runs `operation` behind a single in-flight task. Every caller that
    /// arrives while a reconnect is running awaits the *same* task, so
    /// `operation` runs once and all callers receive the same result (or the
    /// same error). A fresh call after the previous task has completed starts a
    /// new `operation`.
    func reconnect(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        let taskSelection = lock.withLock { () -> (task: Task<String, Error>, reusedInFlightTask: Bool) in
            if let reconnectTask {
                return (reconnectTask, true)
            }

            let taskID = UUID()
            let task = Task<String, Error> { [weak self] in
                defer { self?.clearTaskIfCurrent(taskID) }
                return try await operation()
            }

            reconnectTask = task
            reconnectTaskID = taskID
            return (task, false)
        }

        if taskSelection.reusedInFlightTask {
            await onReuseInFlightTask?()
        }

        return try await taskSelection.task.value
    }

    /// Cancels any in-flight reconnect and clears it. Used by a deliberate
    /// `disconnect()` so a real teardown cancels the reconnect cleanly; awaiters
    /// then observe `CancellationError`, preserving genuine cancellation
    /// semantics.
    func cancelInFlight() {
        lock.withLock {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectTaskID = nil
        }
    }

    private func clearTaskIfCurrent(_ taskID: UUID) {
        lock.withLock {
            guard reconnectTaskID == taskID else {
                return
            }
            reconnectTask = nil
            reconnectTaskID = nil
        }
    }
}
