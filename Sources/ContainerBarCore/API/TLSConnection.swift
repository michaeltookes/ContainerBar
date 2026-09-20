import Foundation
import Network
import Logging
import Security

/// Handles HTTP communication over TCP+TLS connections to remote Docker daemons
///
/// Uses Network.framework NWConnection for TLS-secured TCP connections. The
/// connect/disconnect/send lifecycle lives in the shared `NWConnectionTransport`;
/// this type supplies the TLS-specific endpoint, error taxonomy, and logging.
final class TLSConnection: @unchecked Sendable {

    private let transport: NWConnectionTransport

    /// Creates a TLS connection to a remote Docker daemon
    /// - Parameters:
    ///   - host: Remote host address
    ///   - port: Remote port (default 2376)
    ///   - caCertPath: Path to CA certificate (PEM)
    ///   - clientCertPath: Path to client certificate (PEM)
    ///   - clientKeyPath: Path to client private key (PEM)
    init(host: String, port: Int = 2376, caCertPath: String?, clientCertPath: String?, clientKeyPath: String?) throws {
        guard let validatedPort = UInt16(exactly: port) else {
            throw DockerAPIError.invalidConfiguration("TLS port must be between 0 and 65535")
        }

        let tlsOptions = try Self.makeTLSOptions(
            caCertPath: caCertPath,
            clientCertPath: clientCertPath,
            clientKeyPath: clientKeyPath
        )

        let logger = Logger(label: "com.containerbar.tls")

        let connectTimeout = Self.connectTimeout

        self.transport = NWConnectionTransport(config: .init(
            resolvedHost: host,
            // TLS disconnect waits on `ioGate` (see NWConnectionTransport.disconnect).
            disconnectWaitsForGate: true,
            makeConnection: {
                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: validatedPort)!
                // OS-level TCP connect timeout: defense-in-depth behind the
                // app-level deadline so even the kernel forces a bounded
                // `.failed`/`.waiting` transition instead of retrying forever.
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.connectionTimeout = Int(connectTimeout)
                let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
                return NWConnection(host: nwHost, port: nwPort, using: params)
            },
            mapStateFailure: { error in
                DockerAPIError.tlsConnectionFailed(error.localizedDescription)
            },
            adoptionFailureError: {
                DockerAPIError.tlsConnectionFailed("Connection adoption failed")
            },
            mapSendFailure: { error in
                DockerAPIError.tlsConnectionFailed("Send failed: \(error.localizedDescription)")
            },
            logConnectionEstablished: {
                logger.info("TLS connection established to \(host):\(validatedPort)")
            },
            // TLS unconditionally cleans up the current connection on failure.
            shouldCleanupFailedConnection: nil,
            connectTimeout: connectTimeout,
            requestTimeout: Self.requestTimeout
        ))
    }

    /// App-level connect deadline; also drives the OS-level TCP
    /// `connectionTimeout`. Handshaking to a remote TLS daemon over a LAN/VPN
    /// can be slow, so 15 s is generous while still failing a wrong port or a
    /// sleeping host well before it wedges the polling refresh loop.
    private static let connectTimeout: TimeInterval = 15
    /// App-level request deadline: comfortably above a normal Docker
    /// list/inspect round-trip while still bounding a daemon that accepts the
    /// connection and then never replies.
    private static let requestTimeout: TimeInterval = 30

    deinit {
        disconnectForTeardown()
    }

    /// Builds the TLS options, configuring the client identity and CA anchor
    /// when provided. Throws `invalidConfiguration` for a half-specified
    /// client identity or an unusable client certificate.
    private static func makeTLSOptions(
        caCertPath: String?,
        clientCertPath: String?,
        clientKeyPath: String?
    ) throws -> NWProtocolTLS.Options {
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

        return tlsOptions
    }

    // MARK: - Connection Management

    func isConnectedState() async throws -> Bool {
        try await transport.isConnectedState()
    }

    /// Establish the TLS connection
    func connect() async throws {
        try await transport.connect()
    }

    /// Close the TLS connection
    func disconnect() async throws {
        try await transport.disconnect()
    }

    func disconnectForTeardown() {
        transport.disconnectForTeardown()
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response
    func sendRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await transport.sendRequest(request)
    }
}
