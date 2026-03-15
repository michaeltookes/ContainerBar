import Foundation

/// Retry an async operation with exponential backoff
public func withRetry<T>(
    config: RetryConfig = .default,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = config.initialDelay

    for attempt in 1...config.maxAttempts {
        do {
            return try await operation()
        } catch let error as DockerAPIError {
            lastError = error

            guard error.isTransient else {
                throw error
            }

            guard attempt < config.maxAttempts else {
                break
            }

            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * config.multiplier, config.maxDelay)
        } catch {
            lastError = error
            throw error
        }
    }

    throw lastError ?? DockerAPIError.connectionFailed
}
