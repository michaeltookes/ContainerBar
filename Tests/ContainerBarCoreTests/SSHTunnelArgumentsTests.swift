import Foundation
import Testing
@testable import ContainerBarCore

@Suite("SSH tunnel argv and target validation (CB-072)")
struct SSHTunnelArgumentsTests {
    private static let hostileValues = [
        "-oProxyCommand=touch /tmp/cbqa-pwned",
        "-oProxyCommand=sh",
        "-l",
        "-lroot",
        "-",
        "--",
        "-v"
    ]

    private func arguments(host: String, user: String, port: Int = 22) -> [String] {
        SSHTunnelProcessLauncher.arguments(
            host: host,
            user: user,
            port: port,
            localSocket: "/tmp/local.sock",
            remoteSocket: "/var/run/docker.sock"
        )
    }

    @Test("argv passes the user with -l, ends options with --, and puts the host last")
    func argvSnapshot() {
        let argv = arguments(host: "qa.example.com", user: "alice")
        let knownHosts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/known_hosts").path

        #expect(argv == [
            "-nNT",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(knownHosts)",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-p", "22",
            "-l", "alice",
            "-L", "/tmp/local.sock:/var/run/docker.sock",
            "--",
            "qa.example.com"
        ])
        #expect(!argv.contains { $0.contains("@") })
    }

    @Test("hostile values never land before the -- terminator as an option", arguments: hostileValues)
    func hostileValuesStayOperands(value: String) throws {
        let asUser = arguments(host: "qa.example.com", user: value)
        let userIndex = try #require(asUser.firstIndex(of: "-l"))
        #expect(asUser[userIndex + 1] == value)
        #expect(asUser.last == "qa.example.com")
        #expect(asUser.firstIndex(of: "--")! > userIndex)

        let asHost = arguments(host: value, user: "alice")
        #expect(asHost[asHost.count - 2] == "--")
        #expect(asHost.last == value)
        // Everything before the host is identical to a benign build: the value adds no option.
        #expect(Array(asHost.dropLast()) == Array(arguments(host: "qa.example.com", user: "alice").dropLast()))
    }

    @Test("an ~/.ssh/config alias is passed through as the bare host")
    func aliasPassesThrough() throws {
        try SSHTargetValidator.validate(host: "cbqa-tunnel", user: "root")
        #expect(arguments(host: "cbqa-tunnel", user: "root").suffix(2) == ["--", "cbqa-tunnel"])
    }

    @Test("validator rejects hostile users with the user-facing message", arguments: hostileValues + [
        "", "alice smith", "alice\tsmith", "al\nice", "al\u{0}ice", "al\u{7F}ice", "al\u{2028}ice",
        String(repeating: "a", count: 256)
    ])
    func rejectsHostileUsers(user: String) {
        #expect(throws: SSHTargetValidator.ValidationError.invalidUser) {
            try SSHTargetValidator.validate(host: "qa.example.com", user: user)
        }
        #expect(SSHTargetValidator.ValidationError.invalidUser.errorDescription
            == "Host and user cannot be empty, start with '-', or contain spaces or control characters.")
    }

    @Test("validator rejects hostile hosts", arguments: hostileValues + [
        "", "qa example.com", "qa.example.com\n", "qa\u{0}.example.com", "qa\u{1B}.example.com",
        "fe80::1%-x y", String(repeating: "a", count: 256)
    ])
    func rejectsHostileHosts(host: String) {
        #expect(throws: SSHTargetValidator.ValidationError.invalidHost) {
            try SSHTargetValidator.validate(host: host, user: "alice")
        }
    }

    @Test("validator accepts hostnames, aliases, IPv4, IPv6, and unicode hostnames", arguments: [
        "qa.example.com", "cbqa-tunnel", "my_box", "192.168.1.10", "::1", "fe80::1%en0",
        "2001:db8::8a2e:370:7334", "::ffff:192.0.2.1", "prod+vpn", "host.example.com.", "bücher.example"
    ])
    func acceptsValidHosts(host: String) throws {
        try SSHTargetValidator.validate(host: host, user: "deploy-user.1")
    }

    @Test("validator accepts user names, including realm logins", arguments: [
        "root", "alice", "_svc", "deploy-user", "a.b_c-1", "alice@EXAMPLE.COM", "ålice"
    ])
    func acceptsValidUsers(user: String) throws {
        try SSHTargetValidator.validate(host: "qa.example.com", user: user)
    }

    @Test("client init refuses a saved host whose user would become an ssh option")
    func clientInitRejectsPersistedHostileUser() {
        let host = DockerHost(
            name: "Old build",
            connectionType: .ssh,
            host: "cbqa-invalid.invalid",
            sshUser: "-oProxyCommand=touch /tmp/cbqa-pwned"
        )
        do {
            _ = try DockerAPIClientImpl(host: host)
            Issue.record("Expected DockerAPIClientImpl.init to throw")
        } catch let error as DockerAPIError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected invalidConfiguration, got \(error)")
                return
            }
            #expect(error.localizedDescription
                == "Configuration error: Host and user cannot be empty, start with '-', or contain spaces or control characters.")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("client init refuses a saved host value that begins with -")
    func clientInitRejectsPersistedHostileHost() {
        let host = DockerHost(name: "Old build", connectionType: .ssh, host: "-oProxyCommand=sh", sshUser: "root")
        #expect(throws: DockerAPIError.self) {
            _ = try DockerAPIClientImpl(host: host)
        }
    }
}
