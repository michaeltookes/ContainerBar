import Foundation

extension DockerAPIClientImpl {
    var unixSocketResolvedHost: String {
        switch host.connectionType {
        case .ssh:
            return host.host ?? "localhost"
        case .unixSocket, .tcpTLS:
            return "localhost"
        }
    }

    func getConnection() async throws -> UnixSocketConnection {
        let snapshot: (
            existing: UnixSocketConnection?,
            socketPath: String?,
            sshGuardOK: Bool,
            staleConnection: UnixSocketConnection?
        ) = connectionLock.withLock {
            let existing = connection
            let socketPath = effectiveSocketPath
            let sshGuardOK: Bool
            if host.connectionType == .ssh {
                sshGuardOK = sshTunnel?.isConnected ?? false
            } else {
                sshGuardOK = true
            }

            if !sshGuardOK {
                connection = nil
                return (nil, socketPath, sshGuardOK, existing)
            }

            return (existing, socketPath, sshGuardOK, nil)
        }

        if let staleConnection = snapshot.staleConnection {
            staleConnection.disconnectForTeardown()
        }

        if let existing = snapshot.existing {
            return existing
        }

        guard snapshot.sshGuardOK else {
            throw DockerAPIError.connectionFailed
        }

        guard let socketPath = snapshot.socketPath else {
            throw DockerAPIError.invalidConfiguration("No socket path configured")
        }

        let candidate = UnixSocketConnection(socketPath: socketPath, resolvedHost: unixSocketResolvedHost)
        try await candidate.connect()

        // Adopt the candidate, or discard it if a peer beat us to the cache
        // while we were awaiting connect(). Re-check the SSH guard here too:
        // the tunnel can die while `candidate.connect()` is suspended.
        let adoption: (
            adopted: UnixSocketConnection?,
            staleConnection: UnixSocketConnection?
        ) = connectionLock.withLock {
            let sshGuardOK: Bool
            if host.connectionType == .ssh {
                sshGuardOK = sshTunnel?.isConnected ?? false
            } else {
                sshGuardOK = true
            }

            guard sshGuardOK else {
                let staleConnection = connection
                connection = nil
                return (nil, staleConnection)
            }

            if let existing = connection {
                return (existing, nil)
            }

            connection = candidate
            return (candidate, nil)
        }

        if let staleConnection = adoption.staleConnection {
            staleConnection.disconnectForTeardown()
        }

        guard let adopted = adoption.adopted else {
            candidate.disconnectForTeardown()
            throw DockerAPIError.connectionFailed
        }

        if adopted !== candidate {
            candidate.disconnectForTeardown()
        }

        return adopted
    }

    func closeConnection() async {
        let closing: UnixSocketConnection? = connectionLock.withLock {
            let c = connection
            connection = nil
            return c
        }

        if let closing {
            try? await closing.disconnect()
        }
    }

    func performRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        if host.connectionType == .tcpTLS {
            return try await performTLSRequest(request)
        }

        try await ensureSSHTunnel()

        do {
            let conn = try await getConnection()
            return try await conn.sendRequest(request)
        } catch {
            await closeConnection()

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

            let conn = try await getConnection()
            return try await conn.sendRequest(request)
        }
    }
}
