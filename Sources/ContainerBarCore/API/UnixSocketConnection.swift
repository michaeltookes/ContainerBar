import Foundation
import Network
import Logging

/// Handles HTTP/1.1 communication over Unix domain sockets via Network.framework.
///
/// `NWConnection` with `NWEndpoint.unix(path:)` owns descriptor lifecycle and
/// cancellation, so the previous hand-rolled fd/generation/lock machinery is
/// gone. The connect/disconnect/send lifecycle lives in the shared
/// `NWConnectionTransport`; this type supplies the Unix-socket endpoint, error
/// taxonomy, connect-failure cleanup policy, and logging.
final class UnixSocketConnection: @unchecked Sendable {

    private let transport: NWConnectionTransport

    init(socketPath: String, resolvedHost: String = "localhost") {
        let logger = Logger(label: "com.containerbar.unixsocket")

        let connectTimeout = Self.connectTimeout

        self.transport = NWConnectionTransport(config: .init(
            resolvedHost: resolvedHost,
            // Unix disconnect bypasses `ioGate` so it can preempt a stalled
            // `sendRequest` (see NWConnectionTransport.disconnect and disconnect()).
            disconnectWaitsForGate: false,
            makeConnection: {
                let endpoint = NWEndpoint.unix(path: socketPath)
                // OS-level TCP connect timeout: defense-in-depth behind the
                // app-level deadline. Builds the params explicitly (rather than
                // `.tcp`) so the timeout can be set on the TCP options.
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.connectionTimeout = Int(connectTimeout)
                let params = NWParameters(tls: nil, tcp: tcpOptions)
                return NWConnection(to: endpoint, using: params)
            },
            mapStateFailure: { error in
                Self.mapStartError(error, socketPath: socketPath)
            },
            adoptionFailureError: {
                DockerAPIError.connectionFailed
            },
            mapSendFailure: { _ in
                DockerAPIError.connectionFailed
            },
            logConnectionEstablished: {
                logger.debug("Unix socket connected: \(socketPath)")
            },
            // Unix only cleans up when the failed connection is still current,
            // and cancels the failed connection specifically.
            shouldCleanupFailedConnection: Self.shouldCleanupFailedConnection,
            connectTimeout: connectTimeout,
            requestTimeout: Self.requestTimeout
        ))
    }

    /// App-level connect deadline; also drives the OS-level TCP
    /// `connectionTimeout`. A local Unix socket connects near-instantly, so this
    /// mainly guards a hung/half-open socket; kept at 15 s to match the TLS
    /// transport and stay well clear of a healthy connect.
    private static let connectTimeout: TimeInterval = 15
    /// App-level request deadline: bounds a daemon that accepts the connection
    /// and then never replies. Matches the TLS transport's 30 s.
    private static let requestTimeout: TimeInterval = 30

    deinit {
        disconnectForTeardown()
    }

    // MARK: - Connection Management

    /// Establish the Unix-socket connection.
    func connect() async throws {
        try await transport.connect()
    }

    /// Async-safe disconnect.
    func disconnect() async throws {
        // Do not wait for `ioGate`: a stalled `sendRequest` holds that gate
        // for send+receive, and disconnect must be able to preempt it by
        // cancelling the underlying NWConnection. The transport is configured
        // with `disconnectWaitsForGate: false` to express exactly that.
        try await transport.disconnect()
    }

    /// Synchronous teardown for `deinit` paths where awaiting is impossible.
    func disconnectForTeardown() {
        transport.disconnectForTeardown()
    }

    static func shouldCleanupFailedConnection(current: NWConnection?, failed: NWConnection) -> Bool {
        guard let current else {
            return false
        }
        return current === failed
    }

    // ENOENT comes through as a POSIX error from Network.framework when the
    // socket file is missing — mirror the previous implementation's behavior
    // by surfacing the more specific `socketNotFound` case.
    static func mapStartError(_ error: NWError, socketPath: String) -> DockerAPIError {
        if case .posix(let code) = error, code == .ENOENT {
            return .socketNotFound(socketPath)
        }
        return .connectionFailed
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response.
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await transport.sendRequest(request)
    }
}
