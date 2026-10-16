import Foundation

/// A network endpoint: a host (IPv4, IPv6 without brackets, or DNS name) and a TCP port.
public struct NetworkEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

/// The route OpenSSH would take for a host, as reported by `ssh -G` (CB-115).
///
/// `DockerHost.host` is often an `~/.ssh/config` alias, and the Network framework
/// does not read that file, so the Local Network probe needs the effective
/// `hostname` and `port`. When a `ProxyJump` or `ProxyCommand` is configured the
/// app's process does not make the LAN connection itself, so `isProxied` tells the
/// caller to skip the probe.
public struct SSHRoute: Equatable, Sendable {
    public let endpoint: NetworkEndpoint
    public let isProxied: Bool

    public init(endpoint: NetworkEndpoint, isProxied: Bool) {
        self.endpoint = endpoint
        self.isProxied = isProxied
    }
}

/// Pure parsers for `ssh -G` output and ssh's connect diagnostics. No I/O.
public enum SSHRouteParser {
    /// Parses `ssh -G` output (`keyword value` per line, keywords in lowercase).
    /// Returns `nil` when `hostname` or a valid `port` is missing.
    public static func parse(sshConfigOutput output: String) -> SSHRoute? {
        var hostname: String?
        var port: Int?
        var isProxied = false

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let key = line[..<space].lowercased()
            let value = line[space...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            switch key {
            case "hostname":
                hostname = stripBrackets(value)
            case "port":
                port = validPort(value)
            case "proxyjump", "proxycommand":
                if value.lowercased() != "none" {
                    isProxied = true
                }
            default:
                continue
            }
        }

        guard let hostname, !hostname.isEmpty, let port else { return nil }
        return SSHRoute(endpoint: NetworkEndpoint(host: hostname, port: port), isProxied: isProxied)
    }

    /// The address and port from ssh's `connect to host <address> port <n>: …`
    /// line, scanning every stderr line. Returns `nil` when no line has that shape.
    public static func connectEndpoint(fromStderr stderr: String) -> NetworkEndpoint? {
        let marker = "connect to host "
        for rawLine in stderr.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let markerRange = line.range(of: marker, options: .caseInsensitive) else { continue }
            let tokens = line[markerRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 3, tokens[1].lowercased() == "port" else { continue }
            let portToken = tokens[2].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard let port = validPort(portToken) else { continue }
            let host = stripBrackets(String(tokens[0]))
            guard !host.isEmpty else { continue }
            return NetworkEndpoint(host: host, port: port)
        }
        return nil
    }

    private static func validPort(_ text: String) -> Int? {
        guard let port = Int(text), (1...65535).contains(port) else { return nil }
        return port
    }

    private static func stripBrackets(_ text: String) -> String {
        if text.hasPrefix("["), text.hasSuffix("]"), text.count >= 2 {
            return String(text.dropFirst().dropLast())
        }
        return text
    }
}
