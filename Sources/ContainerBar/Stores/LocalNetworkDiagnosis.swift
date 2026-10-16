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
/// failure with POSIX code EHOSTUNREACH or ENETDOWN is probed; the local socket
/// path is never probed.
struct LocalNetworkDiagnoser: Sendable {
    let resolver: SSHRouteResolving
    let probe: LocalNetworkProbing

    static let live = LocalNetworkDiagnoser(resolver: SSHConfigRouteResolver(), probe: NWLocalNetworkProbe())

    /// POSIX codes the Network framework reports while a connection waits on a
    /// path denied by Local Network privacy (TN3179).
    static let tlsDenialCodes: Set<Int32> = [POSIXErrorCode.EHOSTUNREACH.rawValue, POSIXErrorCode.ENETDOWN.rawValue]

    /// The ssh stderr worth inspecting, or `nil` when the error is not an SSH
    /// failure on an SSH host.
    static func sshStderr(for error: Error, host: DockerHost) -> String? {
        guard host.connectionType == .ssh,
              case .sshConnectionFailed(let stderr)? = error as? DockerAPIError else {
            return nil
        }
        return stderr
    }

    /// Whether the failure can be a Local Network denial and is worth probing.
    /// SSH: ssh's stderr reads "No route to host" (ssh prints English on every
    /// locale). TCP/TLS: the structured POSIX code is EHOSTUNREACH or ENETDOWN;
    /// the localized NWError text is never parsed. The probe, not this check,
    /// decides.
    static func mayBeLocalNetworkDenial(_ error: Error, host: DockerHost) -> Bool {
        guard let dockerError = error as? DockerAPIError else { return false }
        switch (host.connectionType, dockerError) {
        case (.ssh, .sshConnectionFailed(let stderr)):
            return stderr.localizedCaseInsensitiveContains("no route to host")
        case (.tcpTLS, .tlsConnectionFailed(_, let posixCode?)):
            return tlsDenialCodes.contains(posixCode)
        default:
            return false
        }
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
        guard let host, Self.mayBeLocalNetworkDenial(error, host: host) else {
            return false
        }

        let plan: LocalNetworkProbePlan
        switch host.connectionType {
        case .ssh:
            guard let address = host.host, !address.isEmpty else { return false }
            let route = await resolver.resolve(host: address, user: host.sshUser, port: host.sshPort)
            plan = Self.sshPlan(route: route, stderr: Self.sshStderr(for: error, host: host) ?? "")
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
