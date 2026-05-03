import Foundation
import Logging

/// Concrete implementation of DockerAPIClient
///
/// Supports Unix socket and SSH tunnel connections to Docker daemons.
/// Synchronization: `connectionLock` protects `connection` and `effectiveSocketPath`.
/// `UnixSocketConnection` has its own lock for socket I/O, and `SSHTunnelConnection`
/// has its own lock for tunnel process state. Lock ordering: connectionLock → socketLock.
public final class DockerAPIClientImpl: DockerAPIClient, @unchecked Sendable {

    // MARK: - Properties

    let host: DockerHost
    let logger = Logger(label: "com.containerbar.api")
    let apiVersion = "v1.44"

    // Connection management
    var connection: UnixSocketConnection?
    var sshTunnel: SSHTunnelConnection?
    var tlsConnection: TLSConnection?
    var effectiveSocketPath: String?
    let connectionLock = NSLock()
    let tlsConnectCoordinator = TLSConnectCoordinator()

    // MARK: - Initialization

    public init(host: DockerHost) throws {
        self.host = host

        switch host.connectionType {
        case .unixSocket:
            guard let socketPath = host.socketPath else {
                throw DockerAPIError.invalidConfiguration("Missing socket path")
            }
            // Verify socket exists
            guard FileManager.default.fileExists(atPath: socketPath) else {
                throw DockerAPIError.socketNotFound(socketPath)
            }
            self.effectiveSocketPath = socketPath

        case .tcpTLS:
            guard let remoteHost = host.host else {
                throw DockerAPIError.invalidConfiguration("Missing host for TCP+TLS connection")
            }
            let tls = try TLSConnection(
                host: remoteHost,
                port: host.tlsPort,
                caCertPath: host.tlsCACert,
                clientCertPath: host.tlsClientCert,
                clientKeyPath: host.tlsClientKey
            )
            self.tlsConnection = tls

        case .ssh:
            guard let remoteHost = host.host else {
                throw DockerAPIError.invalidConfiguration("Missing SSH host")
            }
            guard let sshUser = host.sshUser else {
                throw DockerAPIError.invalidConfiguration("Missing SSH user")
            }
            let sshPort = host.sshPort ?? 22

            let podmanUID = host.remotePodmanUID ?? ContainerRuntime.defaultPodmanUID
            let remoteSocketPath = Self.validatedRemoteSocketPath(
                configuredPath: host.socketPath,
                fallbackPath: host.runtime.defaultRemoteSocketPath(podmanUID: podmanUID)
            )

            // Create SSH tunnel (connection established lazily via ensureSSHTunnel)
            let tunnel = SSHTunnelConnection(
                host: remoteHost,
                user: sshUser,
                port: sshPort,
                remoteSocketPath: remoteSocketPath
            )
            self.sshTunnel = tunnel
        }

        logger.info("DockerAPIClient initialized for \(host.name)")
    }

    deinit {
        connection?.disconnectForTeardown()
        sshTunnel?.disconnect()
        tlsConnection?.disconnectForTeardown()
    }

    // MARK: - DockerAPIClient Protocol

    public func ping() async throws {
        logger.debug("Pinging Docker daemon")

        let request = HTTPRequest(path: "/\(apiVersion)/_ping")
        let response = try await performRequest(request)

        guard response.statusCode == 200 else {
            throw DockerAPIError.connectionFailed
        }

        logger.info("Successfully connected to Docker daemon")
    }

    public func listContainers(all: Bool) async throws -> [DockerContainer] {
        let path = "/\(apiVersion)/containers/json?all=\(all)"
        logger.debug("Fetching containers (all=\(all))")

        let request = HTTPRequest(path: path)
        let response = try await performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        do {
            let containers = try decoder.decode([DockerContainer].self, from: response.body)
            logger.info("Fetched \(containers.count) containers")
            return containers
        } catch {
            logger.error("Failed to decode containers: \(error)")
            throw DockerAPIError.decodingError(error.localizedDescription)
        }
    }

    public func getContainer(id: String) async throws -> DockerContainer {
        let path = "/\(apiVersion)/containers/\(id)/json"
        logger.debug("Fetching container \(id)")

        let request = HTTPRequest(path: path)
        let response = try await performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(DockerContainer.self, from: response.body)
    }

    public func getContainerStats(id: String) async throws -> ContainerStats {
        let path = "/\(apiVersion)/containers/\(id)/stats?stream=false"
        logger.debug("Fetching stats for container \(id)")

        do {
            let request = HTTPRequest(path: path)
            let response = try await performRequest(request)
            try validateResponse(response)

            let decoder = JSONDecoder()
            let rawStats = try decoder.decode(DockerRawStats.self, from: response.body)
            return try ContainerStats(from: rawStats, containerId: id)
        } catch {
            logger.error("Stats fetch error: \(error.localizedDescription)")
            throw error
        }
    }

    public func startContainer(id: String) async throws {
        let path = "/\(apiVersion)/containers/\(id)/start"
        logger.info("Starting container \(id)")

        let request = HTTPRequest(method: "POST", path: path)
        let response = try await performRequest(request)

        // Docker returns 204 (success) or 304 (already started)
        try validateResponse(response, allowedCodes: [204, 304])
        logger.info("Container \(id) started")
    }

    public func stopContainer(id: String, timeout: Int?) async throws {
        var path = "/\(apiVersion)/containers/\(id)/stop"
        if let timeout {
            path += "?t=\(timeout)"
        }
        logger.info("Stopping container \(id)")

        let request = HTTPRequest(method: "POST", path: path)
        let response = try await performRequest(request)

        // Docker returns 204 (success) or 304 (already stopped)
        try validateResponse(response, allowedCodes: [204, 304])
        logger.info("Container \(id) stopped")
    }

    public func restartContainer(id: String, timeout: Int?) async throws {
        var path = "/\(apiVersion)/containers/\(id)/restart"
        if let timeout {
            path += "?t=\(timeout)"
        }
        logger.info("Restarting container \(id)")

        let request = HTTPRequest(method: "POST", path: path)
        let response = try await performRequest(request)

        try validateResponse(response, allowedCodes: [204])
        logger.info("Container \(id) restarted")
    }

    public func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        let path = "/\(apiVersion)/containers/\(id)?force=\(force)&v=\(volumes)"
        logger.info("Removing container \(id)")

        let request = HTTPRequest(method: "DELETE", path: path)
        let response = try await performRequest(request)

        try validateResponse(response, allowedCodes: [204])
        logger.info("Container \(id) removed")
    }

    public func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String {
        var path = "/\(apiVersion)/containers/\(id)/logs?stdout=true&stderr=true"
        if let tail {
            path += "&tail=\(tail)"
        }
        if timestamps {
            path += "&timestamps=true"
        }
        logger.debug("Fetching logs for container \(id)")

        let request = HTTPRequest(path: path)
        let response = try await performRequest(request)
        try validateResponse(response)

        // Docker logs use multiplexed stream format when TTY is disabled
        // For simplicity, we attempt direct UTF-8 decoding first
        if let logs = String(data: response.body, encoding: .utf8) {
            return logs
        }

        // If that fails, parse multiplexed format
        return parseMultiplexedLogs(response.body)
    }

    public func getSystemInfo() async throws -> DockerSystemInfo {
        let path = "/\(apiVersion)/info"
        logger.debug("Fetching system info")

        let request = HTTPRequest(path: path)
        let response = try await performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(DockerSystemInfo.self, from: response.body)
    }
}
