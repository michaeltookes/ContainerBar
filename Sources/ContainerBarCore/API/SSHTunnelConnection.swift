import Foundation
import Logging

/// Manages SSH tunnel connections to remote Docker/Podman hosts
///
/// Creates an SSH tunnel that forwards the remote container socket to a local socket,
/// allowing the standard Unix socket connection to work with remote hosts.
/// Synchronization: `stateLock` protects `tunnelProcess` and `localSocketPath`
/// which may be read from any thread (e.g. `isConnected`, `disconnect`).
public final class SSHTunnelConnection: @unchecked Sendable {
    public struct StateSnapshot: Sendable {
        public let isConnected: Bool
        public let hasDied: Bool
    }

    // MARK: - Properties

    private let host: String
    private let user: String
    private let port: Int
    private let remoteSocketPath: String
    private let logger = Logger(label: "com.containerbar.ssh")
    private let stateLock = NSLock()

    private var tunnelProcess: Process?
    private var localSocketPath: String?
    private var connectTask: Task<String, Error>?
    private var connectTaskID: UUID?

    /// Set to true when the tunnel process terminates unexpectedly
    private var tunnelDied = false

    // MARK: - Initialization

    /// Creates an SSH tunnel connection
    /// - Parameters:
    ///   - host: Remote host address
    ///   - user: SSH username
    ///   - port: SSH port (default: 22)
    ///   - remoteSocketPath: Path to container socket on remote host (default: /var/run/docker.sock)
    public init(host: String, user: String, port: Int = 22, remoteSocketPath: String = "/var/run/docker.sock") {
        self.host = host
        self.user = user
        self.port = port
        self.remoteSocketPath = remoteSocketPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Establishes an SSH tunnel to the remote Docker socket
    /// - Returns: The local socket path to connect to
    public func connect() async throws -> String {
        let task = getOrCreateConnectTask(forceReconnect: false)
        return try await task.value
    }

    /// Tears down the existing tunnel and reconnects with exponential backoff
    /// - Returns: The new local socket path
    public func reconnect() async throws -> String {
        let maxRetries = 3
        let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        var lastError: Error?

        for attempt in 0..<maxRetries {
            let task = getOrCreateConnectTask(forceReconnect: true)

            do {
                let socketPath = try await task.value
                logger.info("SSH tunnel reconnected on attempt \(attempt + 1)")
                return socketPath
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
                logger.warning("Reconnect attempt \(attempt + 1)/\(maxRetries) failed: \(error.localizedDescription)")

                if attempt < maxRetries - 1 {
                    try await Task.sleep(for: delays[attempt])
                }
            }
        }

        logger.error("SSH tunnel reconnection failed after \(maxRetries) attempts")
        if let dockerError = lastError as? DockerAPIError {
            throw dockerError
        }

        throw DockerAPIError.sshConnectionFailed(
            "Reconnection failed after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "unknown error")"
        )
    }

    /// Closes the SSH tunnel
    public func disconnect() {
        disconnectTunnelState(cancelConnectTask: true)
    }

    /// Check if tunnel is active
    public var isConnected: Bool {
        stateLock.withLock {
            tunnelProcess?.isRunning ?? false
        }
    }

    /// Whether the tunnel has died since last connect
    public var hasDied: Bool {
        stateLock.withLock {
            tunnelDied
        }
    }

    public func snapshotState() -> StateSnapshot {
        stateLock.withLock {
            StateSnapshot(
                isConnected: tunnelProcess?.isRunning ?? false,
                hasDied: tunnelDied
            )
        }
    }

    private func getOrCreateConnectTask(forceReconnect: Bool) -> Task<String, Error> {
        stateLock.withLock {
            if !forceReconnect, let connectTask {
                return connectTask
            }

            let taskID = UUID()
            let task = Task<String, Error> { [weak self] in
                guard let self else {
                    throw DockerAPIError.connectionFailed
                }

                defer {
                    self.clearConnectTaskIfCurrent(taskID)
                }

                if forceReconnect {
                    self.disconnectTunnelState(cancelConnectTask: false)
                }

                return try await self.startTunnel(taskID: taskID)
            }

            connectTask = task
            connectTaskID = taskID
            return task
        }
    }

    private func clearConnectTaskIfCurrent(_ taskID: UUID) {
        stateLock.withLock {
            guard connectTaskID == taskID else {
                return
            }

            connectTask = nil
            connectTaskID = nil
        }
    }

    private func startTunnel(taskID: UUID) async throws -> String {
        let launch = try SSHTunnelProcessLauncher.launch(
            host: host,
            user: user,
            port: port,
            remoteSocketPath: remoteSocketPath,
            logger: logger
        )
        let process = launch.process
        let localSocket = launch.localSocketPath

        // Monitor tunnel death via terminationHandler
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            let status = terminatedProcess.terminationStatus
            let shouldReport = self.stateLock.withLock { () -> Bool in
                guard self.tunnelProcess === terminatedProcess else {
                    return false
                }
                self.tunnelDied = true
                return true
            }
            guard shouldReport else { return }
            self.logger.warning("SSH tunnel process terminated with status \(status)")
        }

        var adopted = false
        defer {
            if !adopted {
                process.terminationHandler = nil
                if process.isRunning {
                    process.terminate()
                }
                try? FileManager.default.removeItem(atPath: localSocket)
            }
        }

        try await SSHTunnelProcessLauncher.waitForSocket(
            process: process,
            errorPipe: launch.errorPipe,
            localSocketPath: localSocket,
            logger: logger
        )

        let adoptedState = stateLock.withLock { () -> Bool in
            guard connectTaskID == taskID else {
                return false
            }

            tunnelProcess = process
            localSocketPath = localSocket
            tunnelDied = false
            return true
        }

        guard adoptedState else {
            throw CancellationError()
        }

        adopted = true
        logger.info("SSH tunnel established: \(localSocket)")
        return localSocket
    }

    private func disconnectTunnelState(cancelConnectTask: Bool) {
        let state = stateLock.withLock { () -> (Process?, String?) in
            let process = tunnelProcess
            let socketPath = localSocketPath
            tunnelProcess = nil
            localSocketPath = nil
            tunnelDied = false

            if cancelConnectTask {
                connectTask?.cancel()
                connectTask = nil
                connectTaskID = nil
            }

            return (process, socketPath)
        }

        if let process = state.0, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
            logger.info("SSH tunnel closed")
        }

        if let socketPath = state.1 {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

}
