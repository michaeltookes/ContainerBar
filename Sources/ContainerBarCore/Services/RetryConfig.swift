import Foundation

/// Configuration for retry behavior
public struct RetryConfig: Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let multiplier: Double

    public static let `default` = RetryConfig(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 10.0,
        multiplier: 2.0
    )

    public init(maxAttempts: Int, initialDelay: TimeInterval, maxDelay: TimeInterval, multiplier: Double) {
        precondition(maxAttempts > 0, "RetryConfig.maxAttempts must be greater than zero")
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
    }
}
