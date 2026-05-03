import Foundation

private struct UnixSocketConnectionSnapshot {
    let existing: UnixSocketConnection?
    let socketPath: String?
    let sshGuardOK: Bool
    let staleConnection: UnixSocketConnection?
}

struct UnixSocketConnectionAdoption {
    let adopted: UnixSocketConnection?
    let staleConnection: UnixSocketConnection?
}

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
        let snapshot: UnixSocketConnectionSnapshot = connectionLock.withLock {
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
                return UnixSocketConnectionSnapshot(
                    existing: nil,
                    socketPath: socketPath,
                    sshGuardOK: sshGuardOK,
                    staleConnection: existing
                )
            }

            return UnixSocketConnectionSnapshot(
                existing: existing,
                socketPath: socketPath,
                sshGuardOK: sshGuardOK,
                staleConnection: nil
            )
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
        let adoption: UnixSocketConnectionAdoption = connectionLock.withLock {
            let sshGuardOK: Bool
            if host.connectionType == .ssh {
                sshGuardOK = sshTunnel?.isConnected ?? false
            } else {
                sshGuardOK = true
            }

            let adoption = Self.adoptionForConnectedUnixSocketCandidate(
                candidate,
                candidateSocketPath: socketPath,
                currentSocketPath: effectiveSocketPath,
                cachedConnection: connection,
                sshGuardOK: sshGuardOK
            )

            if !sshGuardOK {
                connection = nil
            } else if adoption.adopted === candidate {
                connection = candidate
            }

            return adoption
        }

        if let staleConnection = adoption.staleConnection {
            staleConnection.disconnectForTeardown()
        }

        guard let adopted = adoption.adopted else {
            if adoption.staleConnection !== candidate {
                candidate.disconnectForTeardown()
            }
            throw DockerAPIError.connectionFailed
        }

        if adopted !== candidate {
            candidate.disconnectForTeardown()
        }

        return adopted
    }

    static func adoptionForConnectedUnixSocketCandidate(
        _ candidate: UnixSocketConnection,
        candidateSocketPath: String,
        currentSocketPath: String?,
        cachedConnection: UnixSocketConnection?,
        sshGuardOK: Bool
    ) -> UnixSocketConnectionAdoption {
        guard currentSocketPath == candidateSocketPath else {
            return UnixSocketConnectionAdoption(adopted: nil, staleConnection: candidate)
        }

        guard sshGuardOK else {
            return UnixSocketConnectionAdoption(adopted: nil, staleConnection: cachedConnection)
        }

        if let cachedConnection {
            return UnixSocketConnectionAdoption(adopted: cachedConnection, staleConnection: nil)
        }

        return UnixSocketConnectionAdoption(adopted: candidate, staleConnection: nil)
    }

    func closeConnection() async {
        let closing: UnixSocketConnection? = connectionLock.withLock {
            let cachedConnection = connection
            connection = nil
            return cachedConnection
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
            if error is CancellationError || Task.isCancelled {
                throw error
            }

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
