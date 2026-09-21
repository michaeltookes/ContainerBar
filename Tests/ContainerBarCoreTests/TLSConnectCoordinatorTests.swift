import Foundation
import Testing
@testable import ContainerBarCore

@Suite("TLS Connect Coordinator Tests")
struct TLSConnectCoordinatorTests {

    @Test("ensureConnected coalesces concurrent connect attempts")
    func ensureConnectedCoalescesConcurrentConnects() async throws {
        let coordinator = TLSConnectCoordinator()
        let probe = TLSCoordinatorProbe()

        async let first: Void = coordinator.ensureConnected(
            isConnected: { await probe.isConnected() },
            connect: { try await probe.connect() }
        )
        try await Task.sleep(for: .milliseconds(10))
        async let second: Void = coordinator.ensureConnected(
            isConnected: { await probe.isConnected() },
            connect: { try await probe.connect() }
        )

        try await first
        try await second

        let snapshot = await probe.snapshot()
        #expect(snapshot.connectCalls == 1)
        #expect(snapshot.disconnectCalls == 0)
        #expect(snapshot.isConnected)
    }

    @Test("reconnect coalesces concurrent reconnect attempts")
    func reconnectCoalescesConcurrentReconnects() async throws {
        let coordinator = TLSConnectCoordinator()
        let probe = TLSCoordinatorProbe()
        await probe.markConnected()

        async let first: Void = coordinator.reconnect(
            disconnect: { try await probe.disconnect() },
            connect: { try await probe.connect() }
        )
        try await Task.sleep(for: .milliseconds(10))
        async let second: Void = coordinator.reconnect(
            disconnect: { try await probe.disconnect() },
            connect: { try await probe.connect() }
        )

        try await first
        try await second

        let snapshot = await probe.snapshot()
        #expect(snapshot.connectCalls == 1)
        #expect(snapshot.disconnectCalls == 1)
        #expect(snapshot.isConnected)
    }
}

private struct TLSCoordinatorSnapshot {
    let connectCalls: Int
    let disconnectCalls: Int
    let isConnected: Bool
}

private actor TLSCoordinatorProbe {
    private var connected = false
    private var connectCount = 0
    private var disconnectCount = 0

    func isConnected() -> Bool {
        connected
    }

    func markConnected() {
        connected = true
    }

    func connect() async throws {
        connectCount += 1
        try await Task.sleep(for: .milliseconds(100))
        connected = true
    }

    func disconnect() async throws {
        disconnectCount += 1
        connected = false
        try await Task.sleep(for: .milliseconds(100))
    }

    func snapshot() -> TLSCoordinatorSnapshot {
        TLSCoordinatorSnapshot(
            connectCalls: connectCount,
            disconnectCalls: disconnectCount,
            isConnected: connected
        )
    }
}
