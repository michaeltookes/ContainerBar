import Foundation
import Testing
@testable import ContainerBarCore

@Suite("SSH Tunnel Stderr Drain Tests")
struct SSHTunnelStderrDrainTests {

    /// Data written to the pipe is drained (forwarded to the sink and discarded),
    /// so the fixed-size stderr buffer can never back up.
    @Test("drain handler forwards written data to the sink")
    func drainHandlerForwardsData() async throws {
        let pipe = Pipe()
        let collector = DrainCollector()

        SSHTunnelStderrDrain.installDrainHandler(on: pipe.fileHandleForReading) { data in
            collector.append(data)
        }

        let payload = Data("channel 3: open failed: connect failed\n".utf8)
        pipe.fileHandleForWriting.write(payload)

        try await waitUntil { collector.count >= payload.count }
        #expect(collector.count == payload.count)
        #expect(collector.snapshot() == payload)

        SSHTunnelStderrDrain.removeDrainHandler(from: pipe.fileHandleForReading)
        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
    }

    /// After teardown the readability handler is removed, so a reconnect cannot
    /// leak a handler or fire on a stale pipe.
    @Test("teardown removes the readability handler")
    func teardownRemovesHandler() async throws {
        let pipe = Pipe()

        SSHTunnelStderrDrain.installDrainHandler(on: pipe.fileHandleForReading) { _ in }
        #expect(pipe.fileHandleForReading.readabilityHandler != nil)

        SSHTunnelStderrDrain.removeDrainHandler(from: pipe.fileHandleForReading)
        #expect(pipe.fileHandleForReading.readabilityHandler == nil)

        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
    }

    /// A large volume of writes is fully drained rather than filling the buffer —
    /// the regression this fix exists to prevent (ssh blocking on write(2) once
    /// the ~64 KB pipe fills).
    @Test("drain handler keeps up with a large volume of writes")
    func drainHandlerDrainsLargeVolume() async throws {
        let pipe = Pipe()
        let collector = DrainCollector()

        SSHTunnelStderrDrain.installDrainHandler(on: pipe.fileHandleForReading) { data in
            collector.append(data)
        }

        // ~256 KB, well past the 64 KB pipe buffer the bug wedges on.
        let line = Data(String(repeating: "channel N: open failed\n", count: 32).utf8)
        let iterations = 512
        let expected = line.count * iterations
        for _ in 0..<iterations {
            pipe.fileHandleForWriting.write(line)
        }

        try await waitUntil(timeout: .seconds(5)) { collector.count >= expected }
        #expect(collector.count == expected)

        SSHTunnelStderrDrain.removeDrainHandler(from: pipe.fileHandleForReading)
        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition not met before timeout")
    }
}

/// Thread-safe sink for data drained on the readabilityHandler's background queue.
private final class DrainCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }

    var count: Int {
        lock.withLock { storage.count }
    }

    func snapshot() -> Data {
        lock.withLock { storage }
    }
}
