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
    private var tunnelErrorHandle: FileHandle?
    private var connectTask: Task<String, Error>?
    private var connectTaskID: UUID?
    private let reconnectCoordinator = SSHTunnelReconnectCoordinator()
    /// Bumps on deliberate disconnects so older reconnect operations cannot
    /// create a new inner SSH launch after teardown has already happened.
    private var disconnectGeneration = 0

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
        let task = try getOrCreateConnectTask(forceReconnect: false)
        return try await task.value
    }

    /// Tears down the existing tunnel and reconnects with exponential backoff.
    /// Concurrent callers are coalesced behind a single in-flight reconnect
    /// (`SSHTunnelReconnectCoordinator`), so the 3-attempt backoff runs once, not
    /// once per caller. Returns the new local socket path.
    public func reconnect() async throws -> String {
        let reconnectStartGeneration = stateLock.withLock { disconnectGeneration }
        return try await reconnectCoordinator.reconnect { [weak self] in
            guard let self else {
                throw DockerAPIError.connectionFailed
            }
            return try await self.performReconnect(startedAtDisconnectGeneration: reconnectStartGeneration)
        }
    }

    /// The 3-attempt exponential-backoff reconnect body, run once per coalesce.
    private func performReconnect(startedAtDisconnectGeneration: Int) async throws -> String {
        let maxRetries = 3
        let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        var lastError: Error?

        for attempt in 0..<maxRetries {
            try Task.checkCancellation()
            let task = try getOrCreateConnectTask(
                forceReconnect: true,
                reconnectStartedAtDisconnectGeneration: startedAtDisconnectGeneration
            )

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

    public func snapshotState() -> StateSnapshot {
        stateLock.withLock {
            StateSnapshot(
                isConnected: tunnelProcess?.isRunning ?? false,
                hasDied: tunnelDied
            )
        }
    }

    private func getOrCreateConnectTask(
        forceReconnect: Bool,
        reconnectStartedAtDisconnectGeneration: Int? = nil
    ) throws -> Task<String, Error> {
        try stateLock.withLock {
            try Task.checkCancellation()
            try validateReconnectGenerationLocked(reconnectStartedAtDisconnectGeneration)

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

                try Task.checkCancellation()
                if forceReconnect {
                    self.disconnectTunnelState(cancelConnectTask: false)
                }
                try self.validateReconnectGeneration(reconnectStartedAtDisconnectGeneration)

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
        let launch = try launchTunnelIfCurrent(taskID: taskID)
        let process = launch.process
        let localSocket = launch.localSocketPath

        attachTerminationHandler(to: process)

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

        let errorHandle = launch.errorPipe.fileHandleForReading
        let adoptedState = stateLock.withLock { () -> Bool in
            guard connectTaskID == taskID else {
                return false
            }

            tunnelProcess = process
            localSocketPath = localSocket
            tunnelDied = false
            // Drain stderr post-adoption so the pipe buffer can never fill and
            // wedge ssh; under the lock to avoid a store/install race.
            tunnelErrorHandle = errorHandle
            installStderrDrain(on: errorHandle)
            return true
        }

        guard adoptedState else {
            // Lost the adoption race to a newer attempt: throw a retryable
            // DockerAPIError, not a bare CancellationError. Real teardown
            // cancellation comes from checkCancellation in waitForSocket.
            throw DockerAPIError.sshConnectionFailed("SSH tunnel connection was superseded by a newer attempt")
        }

        adopted = true
        logger.info("SSH tunnel established: \(localSocket)")
        return localSocket
    }

    /// Monitors tunnel death: flips `tunnelDied` when the adopted process exits.
    private func attachTerminationHandler(to process: Process) {
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
    }

    /// Installs the stderr drain (log-at-debug and discard). Call under `stateLock`.
    private func installStderrDrain(on errorHandle: FileHandle) {
        SSHTunnelStderrDrain.installDrainHandler(on: errorHandle) { [logger] data in
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                logger.debug("SSH tunnel stderr: \(message)")
            }
        }
    }

    private func disconnectTunnelState(cancelConnectTask: Bool) {
        let state = stateLock.withLock { () -> (Process?, String?) in
            let process = tunnelProcess
            let socketPath = localSocketPath
            let errorHandle = tunnelErrorHandle
            if cancelConnectTask {
                disconnectGeneration += 1
            }
            tunnelProcess = nil
            localSocketPath = nil
            tunnelErrorHandle = nil
            tunnelDied = false

            // Tear down the drain handler so a reconnect can't leak or fire stale.
            SSHTunnelStderrDrain.removeDrainHandler(from: errorHandle)

            if cancelConnectTask {
                connectTask?.cancel()
                connectTask = nil
                connectTaskID = nil
            }

            return (process, socketPath)
        }

        if cancelConnectTask {
            reconnectCoordinator.cancelInFlight()
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

private extension SSHTunnelConnection {
    func validateReconnectGeneration(_ expectedGeneration: Int?) throws {
        try stateLock.withLock {
            try validateReconnectGenerationLocked(expectedGeneration)
        }
    }

    func validateReconnectGenerationLocked(_ expectedGeneration: Int?) throws {
        guard let expectedGeneration else {
            return
        }

        guard disconnectGeneration == expectedGeneration else {
            throw CancellationError()
        }
    }

    func launchTunnelIfCurrent(taskID: UUID) throws -> SSHTunnelLaunchResult {
        // Keep the final task-id check and process spawn atomic with disconnect()
        // so teardown cannot slip between "still current" and `Process.run()`.
        try stateLock.withLock {
            try Task.checkCancellation()
            guard connectTaskID == taskID else {
                throw CancellationError()
            }

            return try SSHTunnelProcessLauncher.launch(
                host: host,
                user: user,
                port: port,
                remoteSocketPath: remoteSocketPath,
                logger: logger
            )
        }
    }
}
