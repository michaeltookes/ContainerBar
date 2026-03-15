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

    // MARK: - Private Helpers

    private func receiveHTTPResponse(conn: NWConnection) async throws -> Data {
        var accumulated = Data()
        let headerSeparator = Data("\r\n\r\n".utf8)
        var receiveError: Error?

        // Read until we have complete headers
        while true {
            let chunk: Data
            do {
                chunk = try await receiveChunk(conn: conn, length: 8192)
            } catch {
                receiveError = error
                break
            }

            guard !chunk.isEmpty else { break }
            accumulated.append(chunk)

            if accumulated.range(of: headerSeparator) != nil {
                break
            }
        }

        guard let headerEnd = accumulated.range(of: headerSeparator) else {
            if let receiveError {
                throw receiveError
            }
            throw DockerAPIError.invalidResponse
        }

        // Parse headers to determine body length
        let headerData = accumulated[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        let headers = parseTLSHeaders(headerString)
        let bodyStart = accumulated[headerEnd.upperBound...]

        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr) {
            // Read remaining body bytes
            var body = Data(bodyStart)
            while body.count < contentLength {
                let remaining = contentLength - body.count
                let chunk = try await receiveChunk(conn: conn, length: min(remaining, 8192))
                guard !chunk.isEmpty else {
                    throw DockerAPIError.tlsConnectionFailed("Connection closed before receiving complete HTTP body")
                }
                body.append(chunk)
            }
            return Data(accumulated[..<headerEnd.upperBound]) + body
        } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            // Read chunked body — read until we see "0\r\n\r\n"
            let endMarker = Data("0\r\n\r\n".utf8)
            var body = Data(bodyStart)
            while body.range(of: endMarker) == nil {
                let chunk = try await receiveChunk(conn: conn, length: 8192)
                guard !chunk.isEmpty else {
                    throw DockerAPIError.tlsConnectionFailed("Connection closed before receiving complete HTTP body")
                }
                body.append(chunk)
            }
            return Data(accumulated[..<headerEnd.upperBound]) + body
        }

        // No content-length or chunked — return what we have
        return accumulated
    }

    private func receiveChunk(conn: NWConnection, length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: 1, maximumLength: length) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: DockerAPIError.tlsConnectionFailed("Receive failed: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

}
