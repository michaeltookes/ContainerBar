import Foundation
import Network
import Testing
@testable import ContainerBarCore

/// Deterministic liveness tests for `NWConnectionTransport` (CB-062).
///
/// Each test stands up an in-process `NWListener` on `127.0.0.1` on an
/// OS-assigned port so nothing depends on a real Docker daemon or the network.
/// A plain-TCP `NWConnectionTransport` (the smallest composable unit — the same
/// machinery `TLSConnection`/`UnixSocketConnection` wrap, minus TLS/Unix
/// specifics) is pointed at the listener with injected tiny timeouts so the
/// deadline fires in milliseconds. Every awaited transport call is additionally
/// wrapped in `withTestTimeout` so a regression that reintroduces the hang fails
/// the test instead of hanging the whole `swift test` run.
@Suite("NWConnectionTransport Liveness Tests")
struct NWConnectionTransportLivenessTests {

    // MARK: - Test 1: request deadline (the core CB-062 regression guard)

    @Test("Request deadline throws networkTimeout against a silent endpoint")
    func requestDeadlineFiresOnSilentServer() async throws {
        let server = try InProcessTCPServer(behavior: .blackHole)
        let port = try await server.start()
        defer { server.stop() }

        let transport = Self.makeTCPTransport(
            host: "127.0.0.1",
            port: port,
            connectTimeout: 2.0,
            requestTimeout: 0.2
        )
        defer { transport.disconnectForTeardown() }

        try await withTestTimeout(5.0) { try await transport.connect() }

        let start = Date()
        do {
            _ = try await withTestTimeout(5.0) {
                try await transport.sendRequest(HTTPRequest(method: "GET", path: "/_ping"))
            }
            Issue.record("Expected a networkTimeout but sendRequest returned a response")
        } catch let error as DockerAPIError {
            guard case .networkTimeout = error else {
                Issue.record("Expected .networkTimeout, got \(error)")
                return
            }
        } catch {
            Issue.record("sendRequest did not time out within the test safety bound: \(error)")
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 4.0, "request should time out near the 0.2s deadline, took \(elapsed)s")
        // The deadline cancelled the connection, so the transport must not
        // still claim to be connected — the next request should reconnect.
        #expect(try await transport.isConnectedState() == false)
    }

    // MARK: - Test 2: connect fast-fail (proves .waiting handling + connect bound)

    @Test("Connect to a refused endpoint fails fast instead of hanging")
    func connectToRefusedPortFailsFast() async throws {
        // Reserve a loopback port and fully close its listener (awaiting the
        // `.cancelled` state) so the port has no listener and the connect is
        // refused — ECONNREFUSED surfaces as `.waiting`/`.failed`. Awaiting the
        // teardown removes the accept race; a reassignment of an ephemeral port
        // to an unrelated process microseconds later is effectively impossible
        // inside one test process.
        let probe = try InProcessTCPServer(behavior: .blackHole)
        let deadPort = try await probe.start()
        await probe.closeAndWait()

        let transport = Self.makeTCPTransport(
            host: "127.0.0.1",
            port: deadPort,
            connectTimeout: 2.0,
            requestTimeout: 2.0
        )
        defer { transport.disconnectForTeardown() }

        let start = Date()
        do {
            try await withTestTimeout(5.0) { try await transport.connect() }
            Issue.record("Expected connect to fail against a port with no listener")
        } catch is DockerAPIError {
            // Any DockerAPIError is acceptable: the `.waiting` handler maps the
            // refusal via mapStateFailure, and the connect deadline is the backstop.
        } catch {
            Issue.record("connect did not fail fast within the safety bound: \(error)")
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 4.0, "connect should fail promptly (not hang), took \(elapsed)s")
    }

    // MARK: - Test 3: happy path (deadline does not fire on a fast response)

    @Test("Healthy fast response is parsed and returned without a timeout")
    func happyPathReturnsParsedResponse() async throws {
        let responseBytes = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK".utf8)
        let server = try InProcessTCPServer(behavior: .respond(responseBytes))
        let port = try await server.start()
        defer { server.stop() }

        let transport = Self.makeTCPTransport(
            host: "127.0.0.1",
            port: port,
            connectTimeout: 2.0,
            requestTimeout: 2.0
        )
        defer { transport.disconnectForTeardown() }

        try await withTestTimeout(5.0) { try await transport.connect() }

        let response = try await withTestTimeout(5.0) {
            try await transport.sendRequest(HTTPRequest(method: "GET", path: "/_ping"))
        }

        #expect(response.statusCode == 200)
        #expect(String(data: response.body, encoding: .utf8) == "OK")
    }

    // MARK: - Helpers

    /// Builds a plain-TCP `NWConnectionTransport` with injectable deadlines — the
    /// same shared machinery the two production transports wrap, with a trivial
    /// error taxonomy so the tests exercise the liveness paths, not TLS/Unix.
    private static func makeTCPTransport(
        host: String,
        port: UInt16,
        connectTimeout: TimeInterval,
        requestTimeout: TimeInterval
    ) -> NWConnectionTransport {
        NWConnectionTransport(config: .init(
            resolvedHost: host,
            disconnectWaitsForGate: true,
            makeConnection: {
                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: port)!
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.connectionTimeout = max(1, Int(connectTimeout))
                return NWConnection(host: nwHost, port: nwPort, using: NWParameters(tls: nil, tcp: tcpOptions))
            },
            mapStateFailure: { _ in DockerAPIError.connectionFailed },
            adoptionFailureError: { DockerAPIError.connectionFailed },
            mapSendFailure: { _ in DockerAPIError.connectionFailed },
            logConnectionEstablished: {},
            shouldCleanupFailedConnection: nil,
            connectTimeout: connectTimeout,
            requestTimeout: requestTimeout
        ))
    }
}

/// Test-only safety bound: races `operation` against a sleep so a regression
/// that hangs the transport surfaces as a thrown `TestTimeoutError` (failing the
/// test) rather than hanging the entire `swift test` run.
private func withTestTimeout<T: Sendable>(
    _ seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TestTimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TestTimeoutError()
        }
        return result
    }
}

private struct TestTimeoutError: Error {}

/// Minimal in-process TCP server on loopback for hermetic transport tests.
private final class InProcessTCPServer: @unchecked Sendable {
    enum Behavior {
        /// Accept the connection and start it, but never send a byte back.
        case blackHole
        /// Accept the connection and, on the first inbound read, send `data`.
        case respond(Data)
    }

    private let listener: NWListener
    private let behavior: Behavior
    private let queue = DispatchQueue(label: "com.containerbar.test.tcpserver")
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(behavior: Behavior) throws {
        self.behavior = behavior
        self.listener = try NWListener(using: .tcp)
    }

    /// Starts the listener and resolves with its OS-assigned port once ready.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil
                    if let port = listener?.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: DockerAPIError.connectionFailed)
                    }
                case .failed(let error):
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        listener.cancel()
    }

    /// Fully tears the listener down and waits for `.cancelled`, so a port
    /// reserved this way reliably refuses subsequent connects (no accept race).
    func closeAndWait() async {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { [weak listener] state in
                if case .cancelled = state {
                    listener?.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            listener.cancel()
        }
    }

    private func handle(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.start(queue: queue)

        switch behavior {
        case .blackHole:
            // Intentionally never send; the client's receive should hit its deadline.
            break
        case .respond(let data):
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }
}
