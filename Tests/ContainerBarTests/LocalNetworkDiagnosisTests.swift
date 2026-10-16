import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Records what the diagnoser asked for and answers with canned values. No network,
/// no `ssh` process.
final class StubRouteResolver: SSHRouteResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let route: SSHRoute?
    private var _calls: [String] = []

    init(route: SSHRoute?) {
        self.route = route
    }

    var calls: [String] {
        lock.withLock { _calls }
    }

    func resolve(host: String, user: String?, port: Int?) async -> SSHRoute? {
        lock.withLock { _calls.append(host) }
        return route
    }
}

final class StubLocalNetworkProbe: LocalNetworkProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: LocalNetworkProbeResult
    private var _probed: [NetworkEndpoint] = []

    init(result: LocalNetworkProbeResult) {
        self.result = result
    }

    var probed: [NetworkEndpoint] {
        lock.withLock { _probed }
    }

    func probe(_ endpoint: NetworkEndpoint) async -> LocalNetworkProbeResult {
        lock.withLock { _probed.append(endpoint) }
        return result
    }
}

/// Local Network denial detection and its message mapping (CB-115).
@Suite("Local Network Diagnosis Tests")
struct LocalNetworkDiagnosisTests {

    static let noRoute = "ssh: connect to host 10.0.0.5 port 22: No route to host"
    static let lanRoute = SSHRoute(endpoint: NetworkEndpoint(host: "10.0.0.5", port: 22), isProxied: false)

    let sshHost = DockerHost(
        name: "QA Runtime",
        connectionType: .ssh,
        runtime: .podman,
        host: "cbqa-tunnel",
        sshUser: "cbqa-fwd"
    )

    let tlsHost = DockerHost(
        name: "LAN TLS",
        connectionType: .tcpTLS,
        host: "10.0.0.7",
        port: 2376
    )

    private struct Fixture {
        let diag: LocalNetworkDiagnoser
        let resolver: StubRouteResolver
        let prober: StubLocalNetworkProbe
    }

    private func diagnoser(route: SSHRoute? = lanRoute, probe: LocalNetworkProbeResult) -> Fixture {
        let resolver = StubRouteResolver(route: route)
        let prober = StubLocalNetworkProbe(result: probe)
        return Fixture(diag: LocalNetworkDiagnoser(resolver: resolver, probe: prober), resolver: resolver, prober: prober)
    }

    @Test("Denied SSH alias: probe targets the ssh -G address and port, message is the guidance")
    func sshAliasDenied() async {
        let fixture = diagnoser(probe: .denied)
        let diag = fixture.diag, resolver = fixture.resolver, prober = fixture.prober
        let message = await diag.message(for: DockerAPIError.sshConnectionFailed(Self.noRoute), host: sshHost)

        #expect(message == LocalNetworkGuidance.message)
        #expect(!message.contains("No route to host"))
        #expect(!message.contains("10.0.0.5"))
        #expect(resolver.calls == ["cbqa-tunnel"])
        #expect(prober.probed == [NetworkEndpoint(host: "10.0.0.5", port: 22)])
    }

    @Test("Guidance copy matches the ticket wording")
    func guidanceCopy() {
        #expect(LocalNetworkGuidance.message == "ContainerBar is not allowed to reach devices on your local network. "
            + "Turn it on in System Settings > Privacy & Security > Local Network, then try again.")
        #expect(LocalNetworkGuidance.buttonTitle == "Open Local Network Settings")
        #expect(LocalNetworkGuidance.settingsURL?.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
        #expect(LocalNetworkGuidance.fallbackURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security")
    }

    @Test("Real routing failure (probe not denied) keeps the normal SSH message", arguments: [
        LocalNetworkProbeResult.inconclusive, .reachable
    ])
    func sshRoutingFailure(result: LocalNetworkProbeResult) async {
        let fixture = diagnoser(probe: result)
        let diag = fixture.diag, prober = fixture.prober
        let error = DockerAPIError.sshConnectionFailed(Self.noRoute)
        let message = await diag.message(for: error, host: sshHost)

        #expect(message == userFriendlyConnectionErrorMessage(for: error, host: sshHost))
        #expect(message != LocalNetworkGuidance.message)
        #expect(prober.probed.count == 1)
    }

    @Test("ProxyJump or ProxyCommand route: no probe, normal SSH message")
    func proxiedRouteSkipsProbe() async {
        let proxied = SSHRoute(endpoint: NetworkEndpoint(host: "10.0.0.5", port: 22), isProxied: true)
        let fixture = diagnoser(route: proxied, probe: .denied)
        let diag = fixture.diag, prober = fixture.prober
        let error = DockerAPIError.sshConnectionFailed(Self.noRoute)
        let message = await diag.message(for: error, host: sshHost)

        #expect(prober.probed.isEmpty)
        #expect(message == userFriendlyConnectionErrorMessage(for: error, host: sshHost))
    }

    @Test("ssh -G failure falls back to the address ssh printed")
    func resolverFailureFallsBackToStderr() async {
        let fixture = diagnoser(route: nil, probe: .denied)
        let diag = fixture.diag, prober = fixture.prober
        let stderr = "ssh: connect to host fd00::5 port 2222: No route to host"
        let message = await diag.message(for: DockerAPIError.sshConnectionFailed(stderr), host: sshHost)

        #expect(prober.probed == [NetworkEndpoint(host: "fd00::5", port: 2222)])
        #expect(message == LocalNetworkGuidance.message)
    }

    @Test("ssh -G failure and no address in stderr: no probe, normal SSH message")
    func noAddressSkipsProbe() async {
        let fixture = diagnoser(route: nil, probe: .denied)
        let diag = fixture.diag, prober = fixture.prober
        let error = DockerAPIError.sshConnectionFailed("ssh: No route to host")
        let message = await diag.message(for: error, host: sshHost)

        #expect(prober.probed.isEmpty)
        #expect(message == userFriendlyConnectionErrorMessage(for: error, host: sshHost))
    }

    @Test("Failures that are not 'No route to host' are never probed", arguments: [
        "cbqa-fwd@cbqa-tunnel: Permission denied (publickey).",
        "Host key verification failed.",
        "ssh: connect to host 10.0.0.5 port 22: Connection refused",
        "ssh: connect to host 10.0.0.5 port 22: Operation timed out"
    ])
    func otherSSHFailuresNotProbed(stderr: String) async {
        let fixture = diagnoser(probe: .denied)
        let diag = fixture.diag, resolver = fixture.resolver, prober = fixture.prober
        let error = DockerAPIError.sshConnectionFailed(stderr)
        let message = await diag.message(for: error, host: sshHost)

        #expect(resolver.calls.isEmpty)
        #expect(prober.probed.isEmpty)
        #expect(message == userFriendlyConnectionErrorMessage(for: error, host: sshHost))
    }

    @Test("TCP/TLS host probes its configured host and port directly, no alias resolution")
    func tlsDenied() async {
        let fixture = diagnoser(probe: .denied)
        let diag = fixture.diag, resolver = fixture.resolver, prober = fixture.prober
        let error = DockerAPIError.tlsConnectionFailed("The operation couldn’t be completed. (Network.NWError error 65 - No route to host)")
        let message = await diag.message(for: error, host: tlsHost)

        #expect(message == LocalNetworkGuidance.message)
        #expect(resolver.calls.isEmpty)
        #expect(prober.probed == [NetworkEndpoint(host: "10.0.0.7", port: 2376)])
    }

    @Test("TCP/TLS routing failure keeps the TLS message")
    func tlsRoutingFailure() async {
        let fixture = diagnoser(probe: .inconclusive)
        let diag = fixture.diag
        let error = DockerAPIError.tlsConnectionFailed("No route to host")
        let message = await diag.message(for: error, host: tlsHost)
        #expect(message == "TLS connection failed: No route to host")
    }

    @Test("Local socket host and the implicit local host are never probed")
    func localSocketNeverProbed() async {
        let fixture = diagnoser(probe: .denied)
        let diag = fixture.diag, resolver = fixture.resolver, prober = fixture.prober
        let socketHost = DockerHost(name: "Local", connectionType: .unixSocket, socketPath: "/tmp/x.sock")

        for host in [socketHost, nil] {
            let denied = await diag.isLocalNetworkDenied(
                error: DockerAPIError.sshConnectionFailed(Self.noRoute),
                host: host
            )
            #expect(!denied)
        }
        let missing = await diag.message(for: DockerAPIError.socketNotFound("/tmp/x.sock"), host: socketHost)
        #expect(missing.hasPrefix("Docker is not running."))
        #expect(resolver.calls.isEmpty)
        #expect(prober.probed.isEmpty)
    }

    @Test("Mismatched transport and error is not probed")
    func mismatchedTransport() {
        #expect(LocalNetworkDiagnoser.failureText(for: DockerAPIError.tlsConnectionFailed("x"), host: sshHost) == nil)
        #expect(LocalNetworkDiagnoser.failureText(for: DockerAPIError.sshConnectionFailed("x"), host: tlsHost) == nil)
        #expect(LocalNetworkDiagnoser.failureText(for: DockerAPIError.connectionFailed, host: sshHost) == nil)
    }

    @Test("Guidance detection tolerates surrounding whitespace only")
    func isGuidance() {
        #expect(LocalNetworkGuidance.isGuidance(LocalNetworkGuidance.message))
        #expect(LocalNetworkGuidance.isGuidance("  \(LocalNetworkGuidance.message)\n"))
        #expect(!LocalNetworkGuidance.isGuidance("Can't reach QA Runtime over SSH."))
        #expect(!LocalNetworkGuidance.isGuidance(nil))
    }

    @MainActor
    @Test("Status bar offers the settings button only for the guidance failure")
    func presentationButton() {
        let denied = ConnectionStatusPresentation.make(
            hostName: "QA Runtime", isConnected: false, isRefreshing: false,
            connectionError: LocalNetworkGuidance.message
        )
        #expect(denied.showsLocalNetworkSettingsButton)
        #expect(denied.detail == LocalNetworkGuidance.message)

        let other = ConnectionStatusPresentation.make(
            hostName: "QA Runtime", isConnected: false, isRefreshing: false,
            connectionError: "Can't reach QA Runtime over SSH. Connection refused."
        )
        #expect(!other.showsLocalNetworkSettingsButton)

        let connecting = ConnectionStatusPresentation.make(
            hostName: "QA Runtime", isConnected: false, isRefreshing: true,
            connectionError: LocalNetworkGuidance.message
        )
        #expect(!connecting.showsLocalNetworkSettingsButton)
    }

    @Test("Open Local Network Settings has a stable automation id")
    func buttonIdentifier() {
        #expect(QAAccessibilityID.openLocalNetworkSettings == "openLocalNetworkSettings")
    }
}
