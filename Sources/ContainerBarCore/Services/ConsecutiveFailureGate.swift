import Foundation

/// Tracks consecutive failures and determines when to surface errors to users.
///
/// This follows the CodexBar pattern of ignoring transient connection failures.
/// The gate will only surface errors after a configurable number of consecutive
/// failures, preventing UI flicker from brief network interruptions.
public final class ConsecutiveFailureGate: @unchecked Sendable {
    private let threshold: Int
    private var consecutiveFailures: Int = 0
    private let lock = NSLock()

    /// Creates a new failure gate
    /// - Parameter threshold: Number of consecutive failures before surfacing error (default: 2)
    public init(threshold: Int = 2) {
        self.threshold = threshold
    }

    /// Records a successful operation, resetting the failure counter
    public func recordSuccess() {
        lock.withLock {
            consecutiveFailures = 0
        }
    }

    /// Records a failure and returns whether the error should be surfaced
    /// - Parameter hadPriorData: Whether there was existing data before this failure
    /// - Returns: True if the error should be shown to the user
    public func shouldSurfaceError(onFailureWithPriorData hadPriorData: Bool) -> Bool {
        lock.withLock {
            consecutiveFailures += 1

            // If we have no prior data, always show the error immediately
            guard hadPriorData else {
                return true
            }

            // With prior data, only surface after threshold consecutive failures
            return consecutiveFailures >= threshold
        }
    }

    /// Returns the current number of consecutive failures
    public var failureCount: Int {
        lock.withLock {
            consecutiveFailures
        }
    }

    /// Resets the failure counter
    public func reset() {
        lock.withLock {
            consecutiveFailures = 0
        }
    }
}
