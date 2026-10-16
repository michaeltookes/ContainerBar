import Foundation
import Network
import Testing
@testable import ContainerBarCore

/// Holds the probe's connection so the test can watch it after the probe returns.
private final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _connection: NWConnection?

    var connection: NWConnection? {
        lock.withLock { _connection }
    }

    func store(_ connection: NWConnection) {
        lock.withLock { _connection = connection }
    }
}

/// Cancellation of an in-flight Local Network probe (CB-115). A host switch
/// cancels the refresh; the probe must stop contacting the old endpoint at once.
@Suite("Local Network Probe Tests")
struct LocalNetworkProbeTests {

    /// Waits until `connection` reports `.cancelled`, up to `limit`.
    private func waitForCancelled(_ connection: NWConnection, limit: Duration = .seconds(2)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limit)
        while clock.now < deadline {
            if case .cancelled = connection.state {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        if case .cancelled = connection.state {
            return true
        }
        return false
    }

    @Test("Cancelling the calling task cancels the connection and returns inconclusive, well before the timeout")
    func cancelInFlight() async {
        let box = ConnectionBox()
        // TEST-NET-1 (RFC 5737) is off-link, so no Local Network grant is
        // involved; a connect there normally hangs in preparing.
        let probe = NWLocalNetworkProbe(timeout: .seconds(30)) { host, port in
            let connection = NWConnection(host: host, port: port, using: .tcp)
            box.store(connection)
            return connection
        }

        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            await probe.probe(NetworkEndpoint(host: "192.0.2.1", port: 9))
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        let elapsed = clock.now - start

        #expect(result == .inconclusive)
        #expect(elapsed < .seconds(10))
        guard let connection = box.connection else {
            Issue.record("probe never built its connection")
            return
        }
        #expect(await waitForCancelled(connection))
    }

    @Test("A task cancelled before probing never starts a connection that outlives it")
    func cancelledBeforeStart() async {
        let box = ConnectionBox()
        let probe = NWLocalNetworkProbe(timeout: .seconds(30)) { host, port in
            let connection = NWConnection(host: host, port: port, using: .tcp)
            box.store(connection)
            return connection
        }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await probe.probe(NetworkEndpoint(host: "192.0.2.1", port: 9))
        }
        let result = await task.value

        #expect(result == .inconclusive)
        if let connection = box.connection {
            #expect(connection.state == .setup || connection.state == .cancelled)
        }
    }

    @Test("Timeout child ends the probe as inconclusive and cancels the connection")
    func timeoutCancelsConnection() async {
        let box = ConnectionBox()
        let probe = NWLocalNetworkProbe(timeout: .milliseconds(300)) { host, port in
            let connection = NWConnection(host: host, port: port, using: .tcp)
            box.store(connection)
            return connection
        }

        let result = await probe.probe(NetworkEndpoint(host: "192.0.2.1", port: 9))

        #expect(result == .inconclusive)
        if let connection = box.connection {
            #expect(await waitForCancelled(connection))
        }
    }

    @Test("Invalid port returns inconclusive without building a connection")
    func invalidPort() async {
        let box = ConnectionBox()
        let probe = NWLocalNetworkProbe(timeout: .seconds(1)) { host, port in
            let connection = NWConnection(host: host, port: port, using: .tcp)
            box.store(connection)
            return connection
        }
        #expect(await probe.probe(NetworkEndpoint(host: "192.0.2.1", port: 0)) == .inconclusive)
        #expect(box.connection == nil)
    }
}
