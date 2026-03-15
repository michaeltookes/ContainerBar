import Foundation

actor AsyncSerialGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withExclusiveAccess<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        guard !Task.isCancelled else {
            release()
            throw CancellationError()
        }
        defer { release() }
        return try await operation()
    }

    private func acquire() async throws {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let nextWaiter = waiters.first {
            waiters.removeFirst()
            nextWaiter.resume()
            return
        }

        isLocked = false
    }
}
