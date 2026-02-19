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

    private var connection: NWConnection?
    private var _isConnected: Bool = false

    /// Whether the connection is currently active
    var isConnected: Bool {
        lock.withLock { _isConnected }
    }

    /// Creates a TLS connection to a remote Docker daemon
    /// - Parameters:
    ///   - host: Remote host address
    ///   - port: Remote port (default 2376)
    ///   - caCertPath: Path to CA certificate (PEM)
    ///   - clientCertPath: Path to client certificate (PEM)
    ///   - clientKeyPath: Path to client private key (PEM)
    init(host: String, port: Int = 2376, caCertPath: String?, clientCertPath: String?, clientKeyPath: String?) throws {
        self.host = host
        self.port = UInt16(port)

        let tlsOptions = NWProtocolTLS.Options()

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
        disconnect()
    }

    // MARK: - Connection Management

    /// Establish the TLS connection
    func connect() async throws {
        // Skip if already connected
        if isConnected { return }

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let params = NWParameters(tls: tlsOptions, tcp: .init())
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)

        lock.withLock {
            self.connection = conn
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: DockerAPIError.sshConnectionFailed("TLS connection failed: \(error)"))
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: DockerAPIError.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
        }

        lock.withLock { _isConnected = true }
        logger.info("TLS connection established to \(host):\(port)")
    }

    /// Close the TLS connection
    func disconnect() {
        lock.withLock {
            connection?.cancel()
            connection = nil
            _isConnected = false
        }
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        let conn: NWConnection? = lock.withLock { connection }
        guard let conn else {
            throw DockerAPIError.connectionFailed
        }

        // Build and send HTTP request
        let httpString = request.toHTTPString()
        guard let requestData = httpString.data(using: .utf8) else {
            throw DockerAPIError.invalidConfiguration("Could not encode request")
        }

        // Send
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: requestData, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DockerAPIError.sshConnectionFailed("TLS send failed: \(error)"))
                } else {
                    continuation.resume()
                }
            })
        }

        // Receive response headers + body
        let responseData = try await receiveHTTPResponse(conn: conn)
        return try parseHTTPResponse(responseData)
    }

    // MARK: - Private Helpers

    private func receiveHTTPResponse(conn: NWConnection) async throws -> Data {
        var accumulated = Data()
        let headerSeparator = Data("\r\n\r\n".utf8)

        // Read until we have complete headers
        while true {
            let chunk = try await receiveChunk(conn: conn, length: 8192)
            guard !chunk.isEmpty else { break }
            accumulated.append(chunk)

            if accumulated.range(of: headerSeparator) != nil {
                break
            }
        }

        guard let headerEnd = accumulated.range(of: headerSeparator) else {
            throw DockerAPIError.invalidResponse
        }

        // Parse headers to determine body length
        let headerData = accumulated[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        let headers = parseHeaders(headerString)
        let bodyStart = accumulated[headerEnd.upperBound...]

        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr) {
            // Read remaining body bytes
            var body = Data(bodyStart)
            while body.count < contentLength {
                let remaining = contentLength - body.count
                let chunk = try await receiveChunk(conn: conn, length: min(remaining, 8192))
                guard !chunk.isEmpty else { break }
                body.append(chunk)
            }
            return Data(accumulated[..<headerEnd.upperBound]) + body
        } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            // Read chunked body — read until we see "0\r\n\r\n"
            let endMarker = Data("0\r\n\r\n".utf8)
            var body = Data(bodyStart)
            while body.range(of: endMarker) == nil {
                let chunk = try await receiveChunk(conn: conn, length: 8192)
                guard !chunk.isEmpty else { break }
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
                    continuation.resume(throwing: DockerAPIError.sshConnectionFailed("TLS receive failed: \(error)"))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    private func parseHeaders(_ headerString: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key.lowercased()] = value
        }
        return headers
    }

    private func parseHTTPResponse(_ data: Data) throws -> HTTPResponse {
        let headerSeparator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: headerSeparator) else {
            throw DockerAPIError.invalidResponse
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        // Parse status line
        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw DockerAPIError.invalidResponse
        }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw DockerAPIError.invalidResponse
        }

        let headers = parseHeaders(headerString)
        var body = Data(data[headerEnd.upperBound...])

        // Decode chunked body if needed
        if headers["transfer-encoding"]?.lowercased() == "chunked" {
            body = decodeChunkedBody(body)
        }

        return HTTPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    private func decodeChunkedBody(_ data: Data) -> Data {
        var result = Data()
        var remaining = data

        while true {
            guard let lineEnd = remaining.range(of: Data("\r\n".utf8)) else { break }

            let sizeLine = remaining[..<lineEnd.lowerBound]
            guard let sizeString = String(data: sizeLine, encoding: .utf8),
                  let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else {
                break
            }

            remaining = Data(remaining[lineEnd.upperBound...])

            if chunkSize == 0 { break }

            guard remaining.count >= chunkSize else { break }

            result.append(remaining[..<remaining.index(remaining.startIndex, offsetBy: chunkSize)])

            // Skip chunk data + trailing CRLF
            if remaining.count > chunkSize + 2 {
                remaining = Data(remaining[remaining.index(remaining.startIndex, offsetBy: chunkSize + 2)...])
            } else {
                break
            }
        }

        return result
    }

}
