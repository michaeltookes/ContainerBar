import Foundation
import Network
import Logging

/// Handles HTTP/1.1 communication over Unix domain sockets via Network.framework.
///
/// `NWConnection` with `NWEndpoint.unix(path:)` owns descriptor lifecycle and
/// cancellation, so the previous hand-rolled fd/generation/lock machinery is
/// gone. Synchronization mirrors `TLSConnection`: `lock` guards state
/// inspection, `ioGate` serializes concurrent connect/send/disconnect work.
final class UnixSocketConnection: @unchecked Sendable {

    private let socketPath: String
    private let logger = Logger(label: "com.containerbar.unixsocket")
    private let lock = NSLock()
    private let ioGate = AsyncSerialGate()

    private var connection: NWConnection?
    private var _isConnected = false
    private var _isConnecting = false

    init(socketPath: String) {
        self.socketPath = socketPath
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
        try await ioGate.withExclusiveAccess {
            self.disconnectImmediately()
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
                    lock.withLock {
                        connection?.cancel()
                        connection = nil
                        _isConnected = false
                        _isConnecting = false
                    }
                    throw error
                }
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

            // HTTP/1.1 requires a Host header; Unix sockets have no network
            // host, so "localhost" is the appropriate placeholder for Docker
            // 28.x.
            let requestData = try request.toHTTPData(resolvedHost: "localhost")

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
