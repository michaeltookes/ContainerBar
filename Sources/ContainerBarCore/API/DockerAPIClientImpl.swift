import Foundation
import Logging

/// Concrete implementation of DockerAPIClient
///
/// Supports Unix socket and SSH tunnel connections to Docker daemons.
public final class DockerAPIClientImpl: DockerAPIClient, @unchecked Sendable {

    // MARK: - Properties

    private let host: DockerHost
    private let logger = Logger(label: "com.containerbar.api")
    private let apiVersion = "v1.44"

    // Connection management
    private var connection: UnixSocketConnection?
    private var sshTunnel: SSHTunnelConnection?
    private var effectiveSocketPath: String?
    private let connectionLock = NSLock()

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
            throw DockerAPIError.notImplemented("TCP+TLS connections")

        case .ssh:
            guard let remoteHost = host.host else {
                throw DockerAPIError.invalidConfiguration("Missing SSH host")
            }
            guard let sshUser = host.sshUser else {
                throw DockerAPIError.invalidConfiguration("Missing SSH user")
            }
            let sshPort = host.sshPort ?? 22

            // Determine the remote socket path based on runtime
            // Use configured socketPath if provided, otherwise use runtime default for Linux servers
            let remoteSocketPath = (host.socketPath?.isEmpty == false)
                ? host.socketPath!
                : host.runtime.defaultRemoteSocketPath

            // Create SSH tunnel to the remote socket
            let tunnel = SSHTunnelConnection(
                host: remoteHost,
                user: sshUser,
                port: sshPort,
                remoteSocketPath: remoteSocketPath
            )
            let localSocket = try tunnel.connect()

            self.sshTunnel = tunnel
            self.effectiveSocketPath = localSocket
        }

        logger.info("DockerAPIClient initialized for \(host.name)")
    }

    deinit {
        closeConnection()
        sshTunnel?.disconnect()
    }

    // MARK: - Connection Management

    private func getConnection() throws -> UnixSocketConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection {
            return existing
        }

        guard let socketPath = effectiveSocketPath else {
            throw DockerAPIError.invalidConfiguration("No socket path configured")
        }

        // For SSH connections, verify tunnel is still active
        if host.connectionType == .ssh {
            guard let tunnel = sshTunnel, tunnel.isConnected else {
                throw DockerAPIError.connectionFailed
            }
        }

        let conn = UnixSocketConnection(socketPath: socketPath)
        try conn.connect()
        connection = conn
        return conn
    }

    private func closeConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.disconnect()
        connection = nil
    }

    // MARK: - Request Helpers

    private func performRequest(_ request: HTTPRequest) throws -> HTTPResponse {
        // Try to reuse connection, reconnect if needed
        do {
            let conn = try getConnection()
            return try conn.sendRequest(request)
        } catch {
            // Connection might be stale, try reconnecting once
            closeConnection()
            let conn = try getConnection()
            return try conn.sendRequest(request)
        }
    }

    private func validateResponse(_ response: HTTPResponse, allowedCodes: Set<Int> = [200]) throws {
        guard allowedCodes.contains(response.statusCode) else {
            logger.error("HTTP error: \(response.statusCode)")

            switch response.statusCode {
            case 401:
                throw DockerAPIError.unauthorized
            case 404:
                throw DockerAPIError.notFound("Resource not found")
            case 409:
                throw DockerAPIError.conflict("Container is already in requested state")
            case 500...599:
                // Try to extract error message from body
                if let errorMessage = String(data: response.body, encoding: .utf8) {
                    throw DockerAPIError.serverError(errorMessage)
                }
                throw DockerAPIError.serverError("Docker daemon error")
            default:
                throw DockerAPIError.unexpectedStatus(response.statusCode)
            }
        }
    }

    // MARK: - DockerAPIClient Protocol

    public func ping() async throws {
        logger.debug("Pinging Docker daemon")

        let request = HTTPRequest(path: "/\(apiVersion)/_ping")
        let response = try performRequest(request)

        guard response.statusCode == 200 else {
            throw DockerAPIError.connectionFailed
        }

        logger.info("Successfully connected to Docker daemon")
    }

    public func listContainers(all: Bool) async throws -> [DockerContainer] {
        let path = "/\(apiVersion)/containers/json?all=\(all)"
        logger.debug("Fetching containers (all=\(all))")

        let request = HTTPRequest(path: path)
        let response = try performRequest(request)
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
        let response = try performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(DockerContainer.self, from: response.body)
    }

    public func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error> {
        let path = "/\(apiVersion)/containers/\(id)/stats?stream=\(stream)"
        logger.debug("Fetching stats for container \(id) (stream=\(stream))")

        return AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    let request = HTTPRequest(path: path)
                    let response = try self.performRequest(request)
                    try self.validateResponse(response)

                    // Parse stats from response body
                    // For non-streaming, we get a single JSON object
                    let decoder = JSONDecoder()
                    let rawStats = try decoder.decode(DockerRawStats.self, from: response.body)
                    let stats = ContainerStats(from: rawStats, containerId: id)

                    continuation.yield(stats)
                    continuation.finish()
                } catch {
                    self.logger.error("Stats fetch error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func startContainer(id: String) async throws {
        let path = "/\(apiVersion)/containers/\(id)/start"
        logger.info("Starting container \(id)")

        let request = HTTPRequest(method: "POST", path: path)
        let response = try performRequest(request)

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
        let response = try performRequest(request)

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
        let response = try performRequest(request)

        try validateResponse(response, allowedCodes: [204])
        logger.info("Container \(id) restarted")
    }

    public func removeContainer(id: String, force: Bool, volumes: Bool) async throws {
        let path = "/\(apiVersion)/containers/\(id)?force=\(force)&v=\(volumes)"
        logger.info("Removing container \(id)")

        let request = HTTPRequest(method: "DELETE", path: path)
        let response = try performRequest(request)

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
        let response = try performRequest(request)
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
        let response = try performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(DockerSystemInfo.self, from: response.body)
    }

    // MARK: - Multiplexed Log Parsing

    /// Parse Docker's multiplexed log format
    /// Format: [8-byte header][payload]
    /// Header: [stream_type(1)][padding(3)][size(4 big-endian)]
    private func parseMultiplexedLogs(_ data: Data) -> String {
        var result = ""
        var offset = 0

        while offset + 8 <= data.count {
            // Read 4-byte size (big-endian) from bytes 4-7 of header
            let sizeBytes = data.subdata(in: (offset + 4)..<(offset + 8))
            let size = sizeBytes.withUnsafeBytes { buffer in
                buffer.load(as: UInt32.self).bigEndian
            }

            // Move past header
            offset += 8

            // Validate we have enough data
            guard offset + Int(size) <= data.count else {
                break
            }

            // Extract payload
            let payload = data.subdata(in: offset..<(offset + Int(size)))
            if let text = String(data: payload, encoding: .utf8) {
                result += text
            }

            // Move to next frame
            offset += Int(size)
        }

        return result
    }
}

// MARK: - Factory Method

extension DockerAPIClientImpl {
    /// Create a client for local Docker daemon
    public static func local() throws -> DockerAPIClientImpl {
        let host = DockerHost.local
        return try DockerAPIClientImpl(host: host)
    }
}
