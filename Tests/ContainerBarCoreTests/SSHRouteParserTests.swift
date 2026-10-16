import Foundation
import Network
import Testing
@testable import ContainerBarCore

/// `ssh -G` parsing, ssh connect-line parsing, and the probe's path mapping (CB-115).
/// Pure functions only: no process is spawned and no connection is made.
@Suite("SSH Route Parser Tests")
struct SSHRouteParserTests {

    @Test("Alias with HostName and Port resolves to that address and port")
    func aliasWithHostNameAndPort() {
        let output = """
        user cbqa-fwd
        hostname 10.0.0.5
        port 2222
        addressfamily any
        """
        let route = SSHRouteParser.parse(sshConfigOutput: output)
        #expect(route == SSHRoute(endpoint: NetworkEndpoint(host: "10.0.0.5", port: 2222), isProxied: false))
    }

    @Test("IPv6 hostname is kept, with or without brackets")
    func ipv6Hostname() {
        let plain = SSHRouteParser.parse(sshConfigOutput: "hostname fd00::5\nport 22\n")
        #expect(plain?.endpoint == NetworkEndpoint(host: "fd00::5", port: 22))

        let bracketed = SSHRouteParser.parse(sshConfigOutput: "hostname [fd00::5]\nport 22\n")
        #expect(bracketed?.endpoint == NetworkEndpoint(host: "fd00::5", port: 22))
    }

    @Test("ProxyJump marks the route proxied")
    func proxyJumpSet() {
        let route = SSHRouteParser.parse(sshConfigOutput: "hostname 10.0.0.5\nport 22\nproxyjump bastion\n")
        #expect(route?.isProxied == true)
    }

    @Test("ProxyCommand marks the route proxied")
    func proxyCommandSet() {
        let output = "hostname nas.lan\nport 22\nproxycommand /usr/bin/nc -X connect -x proxy:8080 %h %p\n"
        #expect(SSHRouteParser.parse(sshConfigOutput: output)?.isProxied == true)
    }

    @Test("ProxyJump and ProxyCommand set to none are not proxied")
    func proxyNone() {
        let output = "hostname 10.0.0.5\nport 22\nproxyjump none\nproxycommand none\nproxyusefdpass no\n"
        #expect(SSHRouteParser.parse(sshConfigOutput: output)?.isProxied == false)
    }

    @Test("Empty or incomplete ssh -G output yields no route", arguments: [
        "",
        "hostname 10.0.0.5\n",
        "port 22\n",
        "hostname 10.0.0.5\nport 0\n",
        "hostname 10.0.0.5\nport notaport\n"
    ])
    func incompleteOutput(output: String) {
        #expect(SSHRouteParser.parse(sshConfigOutput: output) == nil)
    }

    @Test("Connect line yields the address and port ssh printed")
    func connectLineIPv4() {
        let stderr = "Warning: banner\nssh: connect to host 10.0.0.5 port 22: No route to host\n"
        #expect(SSHRouteParser.connectEndpoint(fromStderr: stderr) == NetworkEndpoint(host: "10.0.0.5", port: 22))
    }

    @Test("Connect line with an IPv6 address")
    func connectLineIPv6() {
        let stderr = "ssh: connect to host fd00::5 port 2222: No route to host"
        #expect(SSHRouteParser.connectEndpoint(fromStderr: stderr) == NetworkEndpoint(host: "fd00::5", port: 2222))
    }

    @Test("Stderr without a connect line yields no endpoint", arguments: [
        "",
        "ssh: Could not resolve hostname cbqa-tunnel: nodename nor servname provided",
        "Connection closed by 10.0.0.5 port 22",
        "ssh: connect to host 10.0.0.5: No route to host"
    ])
    func noConnectLine(stderr: String) {
        #expect(SSHRouteParser.connectEndpoint(fromStderr: stderr) == nil)
    }

    @Test("ssh -G argv mirrors the tunnel: session flags, -p, -l, then -- before the host")
    func resolverArguments() {
        #expect(SSHConfigRouteResolver.arguments(host: "cbqa-tunnel", user: "cbqa-fwd", port: 22)
            == ["-G", "-nNT", "-p", "22", "-l", "cbqa-fwd", "--", "cbqa-tunnel"])
        #expect(SSHConfigRouteResolver.arguments(host: "box", user: nil, port: nil) == ["-G", "-nNT", "--", "box"])
        #expect(SSHConfigRouteResolver.arguments(host: "box", user: nil, port: nil).contains(SSHTunnelProcessLauncher.sessionFlags))
    }

    /// Runs the real `/usr/bin/ssh -G` against a temporary config; it evaluates
    /// the file only and opens no connection.
    @Test("Session-dependent Match resolves the tunnel's route, not an interactive one")
    func sessionTypeMatch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb115-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config")
        try """
        Match host cbqa-tunnel sessiontype none
          HostName 10.0.0.9
          Port 2200
          ProxyJump none
        Host cbqa-tunnel
          HostName 10.0.0.5
          ProxyJump bastion
        """.write(to: config, atomically: true, encoding: .utf8)

        let resolver = SSHConfigRouteResolver(timeout: .seconds(5), configFile: config.path)
        let route = await resolver.resolve(host: "cbqa-tunnel", user: "cbqa-fwd", port: nil)

        #expect(route == SSHRoute(endpoint: NetworkEndpoint(host: "10.0.0.9", port: 2200), isProxied: false))
    }

    @Test("Resolver refuses an option-shaped host without spawning ssh")
    func resolverRejectsOptionHost() async {
        let route = await SSHConfigRouteResolver().resolve(host: "-oProxyCommand=evil", user: "u", port: 22)
        #expect(route == nil)
    }

    @Test("Only localNetworkDenied maps to a denial")
    func probePathMapping() {
        #expect(NWLocalNetworkProbe.result(forUnsatisfiedReason: .localNetworkDenied) == .denied)
        #expect(NWLocalNetworkProbe.result(forUnsatisfiedReason: .notAvailable) == .inconclusive)
        #expect(NWLocalNetworkProbe.result(forUnsatisfiedReason: nil) == .inconclusive)
    }
}
