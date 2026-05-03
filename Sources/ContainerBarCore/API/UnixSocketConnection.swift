import Foundation
import Network
import Logging

/// Handles HTTP/1.1 communication over Unix domain sockets via Network.framework.
///
/// `NWConnection` with `NWEndpoint.unix(path:)` owns descriptor lifecycle and
/// cancellation, so the previous hand-rolled fd/generation/lock machinery is
/// gone. Synchronization mirrors `TLSConnection`: `lock` guards state
/// inspection, while `ioGate` serializes connect/send work.
final class UnixSocketConnection: @unchecked Sendable {

    private let socketPath: String
    private let resolvedHost: String
    private let logger = Logger(label: "com.containerbar.unixsocket")
    private let lock = NSLock()
    private let ioGate = AsyncSerialGate()

    private var connection: NWConnection?
    private var _isConnected = false
    private var _isConnecting = false

    init(socketPath: String, resolvedHost: String = "localhost") {
        self.socketPath = socketPath
        self.resolvedHost = resolvedHost
    }

    deinit {
        disconnectForTeardown()
    }

    // MARK: - Connection Management

    /// Establish the Unix-socket connection.
    func connect() async throws {
        try await ioGate.withExclusiveAccess {
            try await self.connectLocked()
        }
    }

    /// Async-safe disconnect.
    func disconnect() async throws {
        // Do not wait for `ioGate`: a stalled `sendRequest` holds that gate
        // for send+receive, and disconnect must be able to preempt it by
        // cancelling the underlying NWConnection.
        disconnectImmediately()
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

                let endpoint = NWEndpoint.unix(path: socketPath)
                let conn = NWConnection(to: endpoint, using: .tcp)
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
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        conn.stateUpdateHandler = { [socketPath] state in
                            switch state {
                            case .ready:
                                conn.stateUpdateHandler = nil
                                continuation.resume()
                            case .failed(let error):
                                conn.stateUpdateHandler = nil
                                continuation.resume(throwing: Self.mapStartError(error, socketPath: socketPath))
                            case .cancelled:
                                conn.stateUpdateHandler = nil
                                continuation.resume(throwing: DockerAPIError.connectionFailed)
                            default:
                                break
                            }
                        }
                        conn.start(queue: DispatchQueue.global(qos: .userInitiated))
                    }

                    let adopted = lock.withLock { () -> Bool in
                        guard let current = connection, current === conn else {
                            return false
                        }
                        _isConnected = true
                        _isConnecting = false
                        return true
                    }

                    guard adopted else {
                        conn.cancel()
                        throw DockerAPIError.connectionFailed
                    }

                    logger.debug("Unix socket connected: \(socketPath)")
                    return
                } catch {
                    let shouldCancelFailedConnection = lock.withLock { () -> Bool in
                        guard Self.shouldCleanupFailedConnection(current: connection, failed: conn) else {
                            return false
                        }

                        connection = nil
                        _isConnected = false
                        _isConnecting = false
                        return true
                    }
                    if shouldCancelFailedConnection {
                        conn.cancel()
                    }
                    throw error
                }
            }
        }
    }

    static func shouldCleanupFailedConnection(current: NWConnection?, failed: NWConnection) -> Bool {
        guard let current else {
            return false
        }
        return current === failed
    }

    private func disconnectImmediately() {
        lock.withLock {
            connection?.cancel()
            connection = nil
            _isConnected = false
            _isConnecting = false
        }
    }

    // ENOENT comes through as a POSIX error from Network.framework when the
    // socket file is missing — mirror the previous implementation's behavior
    // by surfacing the more specific `socketNotFound` case.
    private static func mapStartError(_ error: NWError, socketPath: String) -> DockerAPIError {
        if case .posix(let code) = error, code == .ENOENT {
            return .socketNotFound(socketPath)
        }
        return .connectionFailed
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response.
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await ioGate.withExclusiveAccess {
            let conn: NWConnection? = self.lock.withLock { self.connection }
            guard let conn else {
                throw DockerAPIError.connectionFailed
            }

            let requestData = try request.toHTTPData(resolvedHost: resolvedHost)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conn.send(content: requestData, completion: .contentProcessed { error in
                    if error != nil {
                        continuation.resume(throwing: DockerAPIError.connectionFailed)
                    } else {
                        continuation.resume()
                    }
                })
            }

            let responseData = try await receiveHTTPResponse(conn: conn)
            return try parseTLSHTTPResponse(responseData)
        }
    }
}
