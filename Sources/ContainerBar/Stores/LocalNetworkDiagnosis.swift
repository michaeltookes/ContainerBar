import Foundation
import ContainerBarCore

/// Copy and System Settings links for a denied Local Network permission (CB-115).
enum LocalNetworkGuidance {
    static let message = "ContainerBar is not allowed to reach devices on your local network. "
        + "Turn it on in System Settings > Privacy & Security > Local Network, then try again."

    static let buttonTitle = "Open Local Network Settings"

    /// Deep link to the Local Network list in Privacy & Security.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")

    /// Privacy & Security, for when the deep link does not open.
    static let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")

    /// Whether a displayed message is the Local Network guidance, so the view
    /// can offer the settings button next to it.
    static func isGuidance(_ message: String?) -> Bool {
        message?.trimmingCharacters(in: .whitespacesAndNewlines) == self.message
    }
}

/// Where a failed connection should be probed for a Local Network denial.
enum LocalNetworkProbePlan: Equatable {
    case probe(NetworkEndpoint)
    case skip
}

/// Decides whether a connection failure was caused by a denied macOS Local
/// Network permission (CB-115). Only an SSH "No route to host" or a TCP/TLS
/// EHOSTUNREACH/ENETDOWN failure is probed; the local socket path is never probed.
struct LocalNetworkDiagnoser: Sendable {
    let resolver: SSHRouteResolving
    let probe: LocalNetworkProbing

    static let live = LocalNetworkDiagnoser(resolver: SSHConfigRouteResolver(), probe: NWLocalNetworkProbe())

    /// The failure text worth inspecting, per transport, or `nil` when the
    /// error cannot be a Local Network denial.
    static func failureText(for error: Error, host: DockerHost) -> String? {
        guard let dockerError = error as? DockerAPIError else { return nil }
        switch (host.connectionType, dockerError) {
        case (.ssh, .sshConnectionFailed(let stderr)):
            return stderr
        case (.tcpTLS, .tlsConnectionFailed(let message)):
            return message
        default:
            return nil
        }
    }

    /// Whether the failure text can be a Local Network denial, per transport.
    /// ssh reports a denial as "No route to host" (EHOSTUNREACH). The Network
    /// framework reports it through the path's `localNetworkDenied` reason,
    /// while the connection waits with EHOSTUNREACH or ENETDOWN ("Network is
    /// down", TN3179), so a TLS failure with either text is probed; the probe,
    /// not the text, decides.
    static func mayBeLocalNetworkDenial(_ text: String, connectionType: ConnectionType) -> Bool {
        let markers: [String]
        switch connectionType {
        case .ssh:
            markers = ["no route to host"]
        case .tcpTLS:
            markers = ["no route to host", "network is down"]
        case .unixSocket:
            markers = []
        }
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// Which endpoint to probe for an SSH failure. Prefers the `ssh -G` route;
    /// skips when that route goes through a proxy; falls back to the address in
    /// ssh's own `connect to host` line; otherwise skips.
    static func sshPlan(route: SSHRoute?, stderr: String) -> LocalNetworkProbePlan {
        if let route {
            return route.isProxied ? .skip : .probe(route.endpoint)
        }
        if let endpoint = SSHRouteParser.connectEndpoint(fromStderr: stderr) {
            return .probe(endpoint)
        }
        return .skip
    }

    /// The endpoint a TCP/TLS host connects to: its configured host and port.
    static func tlsPlan(host: DockerHost) -> LocalNetworkProbePlan {
        guard let address = host.host, !address.isEmpty else { return .skip }
        return .probe(NetworkEndpoint(host: address, port: host.tlsPort))
    }

    /// Whether `error` on `host` is a Local Network denial, confirmed by the probe.
    func isLocalNetworkDenied(error: Error, host: DockerHost?) async -> Bool {
        guard let host,
              let text = Self.failureText(for: error, host: host),
              Self.mayBeLocalNetworkDenial(text, connectionType: host.connectionType) else {
            return false
        }

        let plan: LocalNetworkProbePlan
        switch host.connectionType {
        case .ssh:
            guard let address = host.host, !address.isEmpty else { return false }
            let route = await resolver.resolve(host: address, user: host.sshUser, port: host.sshPort)
            plan = Self.sshPlan(route: route, stderr: text)
        case .tcpTLS:
            plan = Self.tlsPlan(host: host)
        case .unixSocket:
            plan = .skip
        }

        guard case .probe(let endpoint) = plan else { return false }
        return await probe.probe(endpoint) == .denied
    }

    /// The banner / `connectionStatus` message: the Local Network guidance when
    /// the probe confirms a denial, otherwise the normal mapped message.
    func message(for error: Error, host: DockerHost?) async -> String {
        if await isLocalNetworkDenied(error: error, host: host) {
            return LocalNetworkGuidance.message
        }
        return userFriendlyConnectionErrorMessage(for: error, host: host)
    }
}
