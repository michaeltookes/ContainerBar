import Foundation
import Network

/// Shared connection lifecycle for the two `NWConnection`-backed transports
/// (`TLSConnection` and `UnixSocketConnection`).
///
/// Both transports carry an identical lifecycle: an `NSLock` guarding
/// `connection`/`_isConnected`/`_isConnecting`, an `AsyncSerialGate` (`ioGate`)
/// serializing connect/send work, a `connectLocked()` start/wait/ready loop, and
/// a send-then-`receiveHTTPResponse` request shape. This object owns that shared
/// machinery once; the per-transport differences (endpoint creation, error
/// taxonomy, disconnect gating, connect-failure cleanup, and the "connected"
/// log line) are injected via `Config`.
///
/// Concurrency: `@unchecked Sendable` with an `NSLock` guarding all mutable
/// state, exactly mirroring the transports it replaces. It is intentionally NOT
/// an actor — `disconnect()` must be able to preempt a stalled `sendRequest`
/// that holds `ioGate`, which an actor's serialized executor could not express.
final class NWConnectionTransport: @unchecked Sendable {

    /// Per-transport policy captured at construction. `makeConnection` and the
    /// other lifecycle closures are plain (not `@Sendable`) and may capture
    /// non-`Sendable` values such as `NWProtocolTLS.Options`; that is safe
    /// because this class is `@unchecked Sendable` and they run under
    /// `ioGate`/`lock`. The two error mappers are `@Sendable` because they are
    /// handed to Network.framework callbacks, which must not retain the
    /// transport.
    struct Config {
        /// Host sent in the HTTP `Host` header for outgoing requests.
        let resolvedHost: String
        /// TLS waits on `ioGate` before disconnecting; Unix bypasses it so a
        /// caller can preempt a stalled `sendRequest` (see `disconnect()`).
        let disconnectWaitsForGate: Bool
        /// Builds a fresh `NWConnection` for the transport's endpoint.
        let makeConnection: () -> NWConnection
        /// Maps an `NWError` from the `.failed` connection state to a transport
        /// specific `DockerAPIError`.
        let mapStateFailure: @Sendable (NWError) -> DockerAPIError
        /// Error thrown when a freshly-established connection can no longer be
        /// adopted (a newer connect replaced it).
        let adoptionFailureError: () -> DockerAPIError
        /// Maps an `NWError` from a failed `send` to a `DockerAPIError`.
        let mapSendFailure: @Sendable (NWError) -> DockerAPIError
        /// Emits the transport's "connection established" log line.
        let logConnectionEstablished: () -> Void
        /// Connect-failure cleanup policy. `nil` means "always clean up the
        /// current connection" (TLS). A predicate means "only clean up when the
        /// failed connection is still current" (Unix), and the failed
        /// connection — not whatever is current — is the one cancelled.
        let shouldCleanupFailedConnection: ((_ current: NWConnection?, _ failed: NWConnection) -> Bool)?
        /// App-level deadline (seconds) for driving a fresh connection to
        /// `.ready`. On expiry the `NWConnection` is cancelled and the operation
        /// throws `DockerAPIError.networkTimeout`. Defaults to 15 s — long enough
        /// for a slow TLS handshake over a LAN/VPN, short enough that a wrong
        /// port or a sleeping host does not wedge the refresh loop; tests inject
        /// a tiny value to exercise the deadline fast.
        var connectTimeout: TimeInterval = 15
        /// App-level deadline (seconds) for a single request (send +
        /// `receiveHTTPResponse`). On expiry the `NWConnection` is cancelled and
        /// the operation throws `DockerAPIError.networkTimeout`. Defaults to 30 s
        /// — comfortably above a normal Docker list/inspect round-trip while
        /// still bounding a daemon that accepts the connection and then never
        /// replies.
        var requestTimeout: TimeInterval = 30
    }

    private let config: Config
    private let lock = NSLock()
    private let ioGate = AsyncSerialGate()

    private var connection: NWConnection?
    private var _isConnected = false
    private var _isConnecting = false

    init(config: Config) {
        self.config = config
    }

    // MARK: - Connection Management

    /// Whether the transport currently holds a live connection. Evaluated inside
    /// `ioGate` so it observes a consistent, serialized view of the state.
    func isConnectedState() async throws -> Bool {
        try await ioGate.withExclusiveAccess {
            self.lock.withLock { self._isConnected }
        }
    }

    func connect() async throws {
        try await ioGate.withExclusiveAccess {
            try await self.connectLocked()
        }
    }

    func disconnect() async throws {
        if config.disconnectWaitsForGate {
            try await ioGate.withExclusiveAccess {
                self.disconnectImmediately()
            }
        } else {
            // Do not wait for `ioGate`: a stalled `sendRequest` holds that gate
            // for send+receive, and disconnect must be able to preempt it by
            // cancelling the underlying NWConnection.
            disconnectImmediately()
        }
    }

    /// Synchronous teardown for `deinit` paths where awaiting is impossible.
    func disconnectForTeardown() {
        disconnectImmediately()
    }

    private func connectLocked() async throws {
        enum ConnectAction {
            case start(NWConnection)
            case wait
            case ready
        }

        while true {
            let action = lock.withLock { () -> ConnectAction in
                if _isConnected { return .ready }
                if _isConnecting { return .wait }

                let conn = config.makeConnection()
                connection = conn
                _isConnecting = true
                return .start(conn)
            }

            switch action {
            case .ready:
                return
            case .wait:
                try await Task.sleep(for: .milliseconds(50))
            case .start(let conn):
                try await startConnection(conn)
                return
            }
        }
    }

    /// Drives a freshly-created connection to `.ready`, then adopts it. On any
    /// failure the transport's connect-failure cleanup policy is applied.
    private func startConnection(_ conn: NWConnection) async throws {
        do {
            // Bound the connect: `NWConnection`'s completion callbacks are not
            // Task-cancellable, so the deadline cancels `conn` on expiry, which
            // resumes the pending `awaitConnectionReady` continuation with an
            // error, and surfaces `DockerAPIError.networkTimeout`.
            try await withDeadline(seconds: config.connectTimeout, connection: conn) {
                try await self.awaitConnectionReady(conn)
            }

            guard adoptConnection(conn) else {
                conn.cancel()
                throw config.adoptionFailureError()
            }

            config.logConnectionEstablished()
        } catch {
            cleanUpFailedConnection(conn)
            throw error
        }
    }

    /// Starts `conn` and suspends until it reaches `.ready`, `.failed`, or
    /// `.cancelled`, mapping the terminal states to `DockerAPIError`s.
    private func awaitConnectionReady(_ conn: NWConnection) async throws {
        // Capture only the mapper so the state handler does not retain the
        // transport for as long as the connection lives.
        let mapStateFailure = config.mapStateFailure
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: mapStateFailure(error))
                case .waiting(let error):
                    // `.waiting` means the connection cannot currently be
                    // established (ECONNREFUSED / EHOSTUNREACH / wrong port), and
                    // `NWConnection` would otherwise sit here retrying forever
                    // without ever resuming the continuation — wedging the whole
                    // connect path behind `ioGate`. This is a polling menu-bar
                    // app that reconnects on the next refresh, so failing fast
                    // and letting the next poll retry is correct here: clear the
                    // handler, cancel the connection, and surface the mapped
                    // failure rather than suspending indefinitely.
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    continuation.resume(throwing: mapStateFailure(error))
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: DockerAPIError.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    /// Marks `conn` as the live connection if it is still the current one.
    private func adoptConnection(_ conn: NWConnection) -> Bool {
        lock.withLock {
            guard let current = connection, current === conn else {
                return false
            }
            _isConnected = true
            _isConnecting = false
            return true
        }
    }

    /// Applies the transport's connect-failure cleanup policy under `lock`.
    private func cleanUpFailedConnection(_ failed: NWConnection) {
        if let predicate = config.shouldCleanupFailedConnection {
            // Unix policy: only reset state when the failed connection is still
            // current, and cancel the failed connection specifically.
            let shouldCancel = lock.withLock { () -> Bool in
                guard predicate(connection, failed) else { return false }
                connection = nil
                _isConnected = false
                _isConnecting = false
                return true
            }
            if shouldCancel {
                failed.cancel()
            }
        } else {
            // TLS policy: unconditionally cancel whatever is current and reset.
            lock.withLock {
                connection?.cancel()
                connection = nil
                _isConnected = false
                _isConnecting = false
            }
        }
    }

    private func disconnectImmediately() {
        lock.withLock {
            connection?.cancel()
            connection = nil
            _isConnected = false
            _isConnecting = false
        }
    }

    // MARK: - HTTP Operations

    /// Sends an HTTP request and reads the complete response, serialized behind
    /// `ioGate` so a connect/disconnect cannot race the send/receive pair.
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await ioGate.withExclusiveAccess {
            let conn: NWConnection? = self.lock.withLock { self.connection }
            guard let conn else {
                throw HTTPRequestNotSentError()
            }

            let requestData = try request.toHTTPData(resolvedHost: self.config.resolvedHost)
            let mapSendFailure = self.config.mapSendFailure
            let requestTimeout = Self.resolvedRequestTimeout(
                defaultTimeout: self.config.requestTimeout,
                minimumRequestTimeout: request.minimumRequestTimeout,
                disablesRequestTimeout: request.disablesRequestTimeout
            )
            let sendAndReceive: @Sendable () async throws -> HTTPResponse = {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    conn.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(throwing: mapSendFailure(error))
                        } else {
                            continuation.resume()
                        }
                    })
                }

                return try await receiveHTTPResponse(conn: conn)
            }

            // Bound finite requests (send + receive). A daemon that accepts the
            // connection and then never replies would hang `receiveHTTPResponse`
            // forever behind `ioGate`; on expiry the deadline cancels `conn`,
            // which fails the pending send/receive callback, and throws
            // `DockerAPIError.networkTimeout`. Requests that intentionally wait
            // indefinitely still get cancellation cleanup via `withConnectionCancellation`.
            do {
                if let requestTimeout {
                    return try await withDeadline(seconds: requestTimeout, connection: conn, operation: sendAndReceive)
                }
                return try await withConnectionCancellation(connection: conn, operation: sendAndReceive)
            } catch DockerAPIError.networkTimeout {
                // The deadline cancelled `conn`; drop it now so the next request
                // reconnects instead of failing once on a dead connection.
                self.cleanUpFailedConnection(conn)
                throw DockerAPIError.networkTimeout
            } catch is CancellationError {
                self.cleanUpFailedConnection(conn)
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    self.cleanUpFailedConnection(conn)
                    throw CancellationError()
                }
                throw error
            }
        }
    }

    static func resolvedRequestTimeout(
        defaultTimeout: TimeInterval,
        minimumRequestTimeout: TimeInterval?,
        disablesRequestTimeout: Bool = false
    ) -> TimeInterval? {
        guard disablesRequestTimeout == false else {
            return nil
        }
        guard let minimumRequestTimeout else {
            return defaultTimeout
        }
        return max(defaultTimeout, minimumRequestTimeout)
    }
}
