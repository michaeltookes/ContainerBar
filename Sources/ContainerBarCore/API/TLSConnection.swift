import Foundation
import Network
import Logging
import Security

/// Handles HTTP communication over TCP+TLS connections to remote Docker daemons
///
/// Uses Network.framework NWConnection for TLS-secured TCP connections.
/// Synchronization: `lock` protects `connection` state across connect/disconnect/send.
final class TLSConnection: @unchecked Sendable {

    private let host: String
    private let port: UInt16
    private let tlsOptions: NWProtocolTLS.Options
    private let logger = Logger(label: "com.containerbar.tls")
    private let lock = NSLock()
    private let ioGate = AsyncSerialGate()

    private var connection: NWConnection?
    private var _isConnected: Bool = false
    private var _isConnecting: Bool = false

    /// Creates a TLS connection to a remote Docker daemon
    /// - Parameters:
    ///   - host: Remote host address
    ///   - port: Remote port (default 2376)
    ///   - caCertPath: Path to CA certificate (PEM)
    ///   - clientCertPath: Path to client certificate (PEM)
    ///   - clientKeyPath: Path to client private key (PEM)
    init(host: String, port: Int = 2376, caCertPath: String?, clientCertPath: String?, clientKeyPath: String?) throws {
        self.host = host
        guard let validatedPort = UInt16(exactly: port) else {
            throw DockerAPIError.invalidConfiguration("TLS port must be between 0 and 65535")
        }
        self.port = validatedPort

        let tlsOptions = NWProtocolTLS.Options()

        if (clientCertPath == nil) != (clientKeyPath == nil) {
            throw DockerAPIError.invalidConfiguration("TLS client certificate and key must both be provided")
        }

        // Configure client identity if both cert and key are provided
        if let certPath = clientCertPath, let keyPath = clientKeyPath {
            let identity = try TLSCertificateLoader.loadIdentity(certPath: certPath, keyPath: keyPath)
            guard let secIdentity = sec_identity_create(identity) else {
                throw DockerAPIError.invalidConfiguration("Failed to create sec_identity from client certificate")
            }
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions,
                secIdentity
            )
        }

        // Configure CA certificate for server verification
        if let caPath = caCertPath {
            let caCert = try TLSCertificateLoader.loadCertificate(path: caPath)
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, trust, completionHandler in
                    let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    SecTrustSetAnchorCertificates(secTrust, [caCert] as CFArray)
                    SecTrustSetAnchorCertificatesOnly(secTrust, true)

                    var error: CFError?
                    let result = SecTrustEvaluateWithError(secTrust, &error)
                    completionHandler(result)
                },
                DispatchQueue.global(qos: .userInitiated)
            )
        }

        self.tlsOptions = tlsOptions
    }

    deinit {
        disconnectForTeardown()
    }

    // MARK: - Connection Management

    func isConnectedState() async throws -> Bool {
        try await ioGate.withExclusiveAccess {
            lock.withLock { _isConnected }
        }
    }

    /// Establish the TLS connection
    func connect() async throws {
        try await ioGate.withExclusiveAccess {
            try await connectLocked()
        }
    }

    /// Close the TLS connection
    func disconnect() async throws {
        try await ioGate.withExclusiveAccess {
            disconnectImmediately()
        }
    }

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
                if _isConnected {
                    return .ready
                }

                if _isConnecting {
                    return .wait
                }

                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: port)!
                let params = NWParameters(tls: tlsOptions, tcp: .init())
                let conn = NWConnection(host: nwHost, port: nwPort, using: params)
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
                        conn.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                conn.stateUpdateHandler = nil
                                continuation.resume()
                            case .failed(let error):
                                conn.stateUpdateHandler = nil
                                continuation.resume(throwing: DockerAPIError.tlsConnectionFailed(error.localizedDescription))
                            case .cancelled:
                                conn.stateUpdateHandler = nil
                                continuation.resume(throwing: DockerAPIError.connectionFailed)
                            default:
                                break
                            }
                        }
                        conn.start(queue: DispatchQueue.global(qos: .userInitiated))
                    }

                    let shouldMarkConnected = lock.withLock {
                        guard let currentConnection = connection, currentConnection === conn else {
                            return false
                        }

                        _isConnected = true
                        _isConnecting = false
                        return true
                    }

                    guard shouldMarkConnected else {
                        conn.cancel()
                        throw DockerAPIError.tlsConnectionFailed("Connection adoption failed")
                    }

                    logger.info("TLS connection established to \(host):\(port)")
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

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await ioGate.withExclusiveAccess {
            let conn: NWConnection? = lock.withLock { connection }
            guard let conn else {
                throw DockerAPIError.connectionFailed
            }

            let requestData = try request.toHTTPData(resolvedHost: host)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conn.send(content: requestData, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: DockerAPIError.tlsConnectionFailed("Send failed: \(error.localizedDescription)"))
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
