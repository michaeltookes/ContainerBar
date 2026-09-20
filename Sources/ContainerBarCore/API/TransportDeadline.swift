import Foundation
import Network

/// Races `operation` against a wall-clock deadline for `NWConnection`-backed
/// transports.
///
/// `NWConnection`'s send/receive/state completion callbacks are driven by
/// Network.framework, not by Swift concurrency, so the `withCheckedThrowingContinuation`
/// wrappers around them ignore `Task` cancellation — a hung connect or a daemon
/// that never replies would suspend forever. The only reliable way to unblock a
/// pending continuation is to cancel the underlying `NWConnection`, which forces
/// the callback to fire with an error.
///
/// This helper runs `operation` and a `Task.sleep(seconds)` concurrently:
/// - if `operation` finishes (or throws) first, the sleep is cancelled and its
///   result/error propagates unchanged (so a fast, real connect failure still
///   surfaces its own `DockerAPIError`, not a timeout);
/// - if the sleep wins, `connection.cancel()` unblocks the pending continuation
///   and the helper throws `DockerAPIError.networkTimeout`.
/// - if the caller cancels the parent task, `connection.cancel()` runs before
///   the task group unwinds so the pending Network continuation cannot wedge the
///   group.
///
/// Structured concurrency guarantees the group awaits the now-cancelled
/// `operation` child before returning, and `connection.cancel()` guarantees that
/// child completes, so this never leaks a suspended task.
func withDeadline<T: Sendable>(
    seconds: TimeInterval,
    connection: NWConnection,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let canceller = DeadlineConnectionCanceller(connection: connection)

    return try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: DeadlineOutcome<T>.self) { group in
            group.addTask {
                .completed(try await operation())
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return .timedOut
            }
            defer { group.cancelAll() }

            do {
                while let outcome = try await group.next() {
                    if Task.isCancelled {
                        canceller.cancel()
                        throw CancellationError()
                    }

                    switch outcome {
                    case .completed(let value):
                        return value
                    case .timedOut:
                        canceller.cancel()
                        throw DockerAPIError.networkTimeout
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    canceller.cancel()
                    throw CancellationError()
                }
                throw error
            }

            // The group always yields at least one outcome before finishing.
            throw DockerAPIError.networkTimeout
        }
    } onCancel: {
        canceller.cancel()
    }
}

/// Which of the two racing children finished first.
private enum DeadlineOutcome<T: Sendable>: Sendable {
    case completed(T)
    case timedOut
}

private struct DeadlineConnectionCanceller: @unchecked Sendable {
    let connection: NWConnection

    func cancel() {
        connection.cancel()
    }
}
