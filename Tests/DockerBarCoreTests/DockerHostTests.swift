import Foundation
import Testing
@testable import DockerBarCore

@Suite("DockerHost Tests")
struct DockerHostTests {

    @Test("Local host has correct defaults")
    func localHostDefaults() {
        let host = DockerHost.local

        #expect(host.name == "Local Docker")
        #expect(host.connectionType == .unixSocket)
        #expect(host.isDefault == true)
        #expect(host.socketPath == "/var/run/docker.sock")
        #expect(host.tlsEnabled == false)
    }

    @Test("Unix socket host sets default socket path")
    func unixSocketDefaultPath() {
        let host = DockerHost(
            name: "Test",
            connectionType: .unixSocket
        )

        #expect(host.socketPath == "/var/run/docker.sock")
    }

    @Test("SSH host sets default port")
    func sshDefaultPort() {
        let host = DockerHost(
            name: "SSH Server",
            connectionType: .ssh,
            host: "example.com",
            sshUser: "root"
        )

        #expect(host.sshPort == 22)
    }

    @Test("SSH host respects custom port")
    func sshCustomPort() {
        let host = DockerHost(
            name: "SSH Server",
            connectionType: .ssh,
            host: "example.com",
            sshUser: "root",
            sshPort: 2222
        )

        #expect(host.sshPort == 2222)
    }

    @Test("TCP+TLS enables TLS automatically")
    func tcpTlsEnablesTls() {
        let host = DockerHost(
            name: "TLS Server",
            connectionType: .tcpTLS,
            host: "example.com",
            port: 2376
        )

        #expect(host.tlsEnabled == true)
    }

    @Test("Host ID is unique")
    func hostIdUnique() {
        let host1 = DockerHost(name: "Host 1", connectionType: .unixSocket)
        let host2 = DockerHost(name: "Host 2", connectionType: .unixSocket)

        #expect(host1.id != host2.id)
    }

    @Test("Host equality compares all properties")
    func hostEquality() {
        let id = UUID()
        let host1 = DockerHost(id: id, name: "Host", connectionType: .unixSocket)
        let host2 = DockerHost(id: id, name: "Host", connectionType: .unixSocket)
        let host3 = DockerHost(id: id, name: "Host Modified", connectionType: .unixSocket)

        #expect(host1 == host2)
        #expect(host1 != host3)
    }

    @Test("Host is Codable")
    func hostCodable() throws {
        let original = DockerHost(
            name: "Test Server",
            connectionType: .ssh,
            host: "192.168.1.100",
            sshUser: "admin",
            sshPort: 22
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DockerHost.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.connectionType == original.connectionType)
        #expect(decoded.host == original.host)
        #expect(decoded.sshUser == original.sshUser)
        #expect(decoded.sshPort == original.sshPort)
    }
}

@Suite("ConnectionType Tests")
struct ConnectionTypeTests {

    @Test("Display names are set correctly")
    func displayNames() {
        #expect(ConnectionType.unixSocket.displayName == "Unix Socket (Local)")
        #expect(ConnectionType.tcpTLS.displayName == "TCP + TLS (Remote)")
        #expect(ConnectionType.ssh.displayName == "SSH Tunnel (Remote)")
    }

    @Test("Requires credentials is correct")
    func requiresCredentials() {
        #expect(ConnectionType.unixSocket.requiresCredentials == false)
        #expect(ConnectionType.tcpTLS.requiresCredentials == true)
        #expect(ConnectionType.ssh.requiresCredentials == true)
    }

    @Test("Raw values are correct")
    func rawValues() {
        #expect(ConnectionType.unixSocket.rawValue == "unix")
        #expect(ConnectionType.tcpTLS.rawValue == "tcp+tls")
        #expect(ConnectionType.ssh.rawValue == "ssh")
    }

    @Test("All cases are included")
    func allCases() {
        #expect(ConnectionType.allCases.count == 3)
        #expect(ConnectionType.allCases.contains(.unixSocket))
        #expect(ConnectionType.allCases.contains(.tcpTLS))
        #expect(ConnectionType.allCases.contains(.ssh))
    }
}
