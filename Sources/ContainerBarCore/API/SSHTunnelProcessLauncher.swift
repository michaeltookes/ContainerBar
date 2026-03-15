import Foundation
import Logging

struct SSHTunnelLaunchResult {
    let process: Process
    let errorPipe: Pipe
    let localSocketPath: String
}

enum SSHTunnelProcessLauncher {
    static func launch(
        host: String,
        user: String,
        port: Int,
        remoteSocketPath: String,
        logger: Logger
    ) throws -> SSHTunnelLaunchResult {
        let localSocketPath = makeLocalSocketPath()
        try? FileManager.default.removeItem(atPath: localSocketPath)

        logger.info("Creating SSH tunnel to \(user)@\(host):\(port) -> \(remoteSocketPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-nNT",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(knownHostsPath())",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-p", String(port),
            "-L", "\(localSocketPath):\(remoteSocketPath)",
            "\(user)@\(host)"
        ]

        process.environment = resolvedEnvironment(logger: logger)
        logger.info(process.environment?["SSH_AUTH_SOCK"] == nil ? "SSH agent socket is not set" : "SSH agent socket is available")

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Failed to start SSH tunnel: \(error.localizedDescription)")
            throw DockerAPIError.connectionFailed
        }

        return SSHTunnelLaunchResult(process: process, errorPipe: errorPipe, localSocketPath: localSocketPath)
    }

    static func waitForSocket(
        process: Process,
        errorPipe: Pipe,
        localSocketPath: String,
        logger: Logger
    ) async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(1))
        try Task.checkCancellation()

        guard process.isRunning else {
            throw parseLaunchError(errorPipe: errorPipe, logger: logger)
        }

        var attempts = 0
        while attempts < 10 {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: localSocketPath) {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
            attempts += 1
        }

        process.terminate()
        logger.error("SSH tunnel established but socket not created")
        throw DockerAPIError.connectionFailed
    }

    private static func makeLocalSocketPath() -> String {
        let socketDir = FileManager.default.temporaryDirectory
        let socketName = "dockerbar-\(UUID().uuidString.prefix(8)).sock"
        return socketDir.appendingPathComponent(socketName).path
    }

    private static func knownHostsPath() -> String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".ssh/known_hosts")
            .path
    }

    private static func resolvedEnvironment(logger: Logger) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard environment["SSH_AUTH_SOCK"] == nil else {
            return environment
        }

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
                logger.info("Found SSH agent socket via launchctl")
            }
        } catch {
            logger.warning("Failed to query launchctl for SSH_AUTH_SOCK: \(error)")
        }

        return environment
    }

    private static func parseLaunchError(errorPipe: Pipe, logger: Logger) -> DockerAPIError {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        logger.error("SSH tunnel failed: \(errorMessage)")
        let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.localizedCaseInsensitiveContains("host key verification failed")
            || trimmed.localizedCaseInsensitiveContains("REMOTE HOST IDENTIFICATION HAS CHANGED")
            || trimmed.localizedCaseInsensitiveContains("host key is known") {
            return DockerAPIError.sshConnectionFailed(
                "\(trimmed). Verify the host key in ~/.ssh/known_hosts before reconnecting."
            )
        }

        return DockerAPIError.sshConnectionFailed(trimmed)
    }
}
