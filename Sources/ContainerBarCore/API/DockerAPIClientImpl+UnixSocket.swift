import Foundation

extension DockerAPIClientImpl {
    func getConnection() throws -> UnixSocketConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection {
            return existing
        }

        guard let socketPath = effectiveSocketPath else {
            throw DockerAPIError.invalidConfiguration("No socket path configured")
        }

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

    func closeConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.disconnect()
        connection = nil
    }

    func performRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        if host.connectionType == .tcpTLS {
            return try await performTLSRequest(request)
        }

        try await ensureSSHTunnel()

        do {
            let conn = try getConnection()
            return try conn.sendRequest(request)
        } catch {
            closeConnection()

            if host.connectionType == .ssh, let tunnel = sshTunnel {
                let tunnelState = tunnel.snapshotState()
                if !tunnelState.isConnected {
                    logger.warning("SSH tunnel lost during request, attempting reconnect")
                    let localSocket = try await tunnel.reconnect()
                    connectionLock.withLock {
                        effectiveSocketPath = localSocket
                        connection = nil
                    }
                }
            }

            let conn = try getConnection()
            return try conn.sendRequest(request)
        }
    }
}
