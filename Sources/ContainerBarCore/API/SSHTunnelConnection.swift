import Foundation
import Logging

/// Manages SSH tunnel connections to remote Docker/Podman hosts
///
/// Creates an SSH tunnel that forwards the remote container socket to a local socket,
/// allowing the standard Unix socket connection to work with remote hosts.
public final class SSHTunnelConnection: @unchecked Sendable {

    // MARK: - Properties

    private let host: String
    private let user: String
    private let port: Int
    private let remoteSocketPath: String
    private let logger = Logger(label: "com.containerbar.ssh")

    private var tunnelProcess: Process?
    private var localSocketPath: String?

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
    public func connect() throws -> String {
        // Create a unique local socket path
        let socketDir = FileManager.default.temporaryDirectory
        let socketName = "dockerbar-\(UUID().uuidString.prefix(8)).sock"
        let localSocket = socketDir.appendingPathComponent(socketName).path

        // Remove existing socket if present
        try? FileManager.default.removeItem(atPath: localSocket)

        logger.info("Creating SSH tunnel to \(user)@\(host):\(port) -> \(remoteSocketPath)")

        // Build SSH command for socket forwarding
        // ssh -nNT -L /local/socket:/remote/socket user@host
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-nNT",                                    // No command, no TTY
            "-o", "StrictHostKeyChecking=accept-new", // Accept new host keys
            "-o", "BatchMode=yes",                    // No password prompts (use key auth)
            "-o", "ConnectTimeout=10",                // 10 second timeout
            "-o", "ServerAliveInterval=30",           // Keep alive
            "-o", "ServerAliveCountMax=3",
            "-p", String(port),
            "-L", "\(localSocket):\(remoteSocketPath)",
            "\(user)@\(host)"
        ]

        // Ensure SSH agent socket is available to the subprocess
        // Apps launched from Xcode/GUI may not inherit the full shell environment
        var environment = ProcessInfo.processInfo.environment
        if environment["SSH_AUTH_SOCK"] == nil {
            // Query launchd for the SSH_AUTH_SOCK value
            let launchctlProcess = Process()
            launchctlProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            launchctlProcess.arguments = ["getenv", "SSH_AUTH_SOCK"]
            let pipe = Pipe()
            launchctlProcess.standardOutput = pipe
            launchctlProcess.standardError = FileHandle.nullDevice

            do {
                try launchctlProcess.run()
                launchctlProcess.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    environment["SSH_AUTH_SOCK"] = path
                    logger.info("Found SSH_AUTH_SOCK via launchctl: \(path)")
                }
            } catch {
                logger.warning("Failed to query launchctl for SSH_AUTH_SOCK: \(error)")
            }
        }
        process.environment = environment

        logger.info("SSH_AUTH_SOCK: \(environment["SSH_AUTH_SOCK"] ?? "not set")")

        // Capture stderr for error messages
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Failed to start SSH tunnel: \(error.localizedDescription)")
            throw DockerAPIError.connectionFailed
        }

        // Wait briefly for tunnel to establish
        Thread.sleep(forTimeInterval: 1.0)

        // Check if process is still running
        guard process.isRunning else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.error("SSH tunnel failed: \(errorMessage)")
            throw DockerAPIError.sshConnectionFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Verify socket was created
        var attempts = 0
        while attempts < 10 {
            if FileManager.default.fileExists(atPath: localSocket) {
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
            attempts += 1
        }

        guard FileManager.default.fileExists(atPath: localSocket) else {
            process.terminate()
            logger.error("SSH tunnel established but socket not created")
            throw DockerAPIError.connectionFailed
        }

        self.tunnelProcess = process
        self.localSocketPath = localSocket

        logger.info("SSH tunnel established: \(localSocket)")
        return localSocket
    }

    /// Closes the SSH tunnel
    public func disconnect() {
        if let process = tunnelProcess, process.isRunning {
            process.terminate()
            logger.info("SSH tunnel closed")
        }
        tunnelProcess = nil

        // Clean up local socket
        if let socketPath = localSocketPath {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        localSocketPath = nil
    }

    /// Check if tunnel is active
    public var isConnected: Bool {
        tunnelProcess?.isRunning ?? false
    }
}
