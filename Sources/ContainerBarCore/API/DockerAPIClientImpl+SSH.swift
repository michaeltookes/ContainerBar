import Foundation

extension DockerAPIClientImpl {
    static func validatedRemoteSocketPath(configuredPath: String?, fallbackPath: String) -> String {
        guard let configuredPath else {
            return fallbackPath
        }

        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return fallbackPath
        }
        guard trimmedPath.hasPrefix("/") else {
            return fallbackPath
        }
        guard !trimmedPath.contains("\0") else {
            return fallbackPath
        }

        let pathSegments = trimmedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard !pathSegments.contains(where: { $0 == ".." }) else {
            return fallbackPath
        }

        return trimmedPath
    }

    func ensureSSHTunnel() async throws {
        guard host.connectionType == .ssh, let tunnel = sshTunnel else {
            return
        }

        let state = connectionLock.withLock {
            (socketPath: effectiveSocketPath, tunnelState: tunnel.snapshotState())
        }

        let needsConnect = state.socketPath == nil || state.tunnelState.hasDied || !state.tunnelState.isConnected
        guard needsConnect else {
            return
        }

        let localSocket: String
        if state.tunnelState.hasDied {
            logger.warning("SSH tunnel died, attempting reconnect")
            closeConnection()
            localSocket = try await tunnel.reconnect()
        } else {
            localSocket = try await tunnel.connect()
        }

        connectionLock.withLock {
            effectiveSocketPath = localSocket
            connection = nil
        }
    }
}
