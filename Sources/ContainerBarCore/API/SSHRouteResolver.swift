import Foundation

/// Resolves the effective SSH route for a host (CB-115).
public protocol SSHRouteResolving: Sendable {
    /// The route `ssh` would use, or `nil` when it cannot be determined.
    func resolve(host: String, user: String?, port: Int?) async -> SSHRoute?
}

/// Runs `/usr/bin/ssh -G` with the same `-p`/`-l`/`--` argv shape the tunnel uses.
/// `ssh -G` only evaluates the configuration and makes no network connection.
public struct SSHConfigRouteResolver: SSHRouteResolving {
    /// Upper bound for `ssh -G`; it normally returns in milliseconds.
    let timeout: Duration

    public init(timeout: Duration = .seconds(3)) {
        self.timeout = timeout
    }

    /// The argv after `ssh`. The user goes in `-l` and `--` ends option parsing.
    static func arguments(host: String, user: String?, port: Int?) -> [String] {
        var args = ["-G"]
        if let port {
            args += ["-p", String(port)]
        }
        if let user, !user.isEmpty {
            args += ["-l", user]
        }
        args += ["--", host]
        return args
    }

    public func resolve(host: String, user: String?, port: Int?) async -> SSHRoute? {
        do {
            try SSHTargetValidator.validateHost(host)
            if let user, !user.isEmpty {
                try SSHTargetValidator.validateUser(user)
            }
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.arguments(host: host, user: user, port: port)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeout = self.timeout
        let watchdog = Task.detached {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }
        defer { watchdog.cancel() }

        let data = await Task.detached {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value

        guard process.terminationReason == .exit,
              process.terminationStatus == 0,
              let text = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        return SSHRouteParser.parse(sshConfigOutput: text)
    }
}
