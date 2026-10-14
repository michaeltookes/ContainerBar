import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Runtime- and transport-aware connection error copy (CB-077).
@Suite("Connection Error Message Tests")
struct ConnectionErrorMessageTests {

    private let podmanSocketHost = DockerHost(
        name: "QA Runtime (socket)",
        connectionType: .unixSocket,
        runtime: .podman,
        socketPath: "/tmp/qa/podman.sock"
    )

    private let sshHost = DockerHost(
        name: "QA Runtime",
        connectionType: .ssh,
        runtime: .podman,
        host: "qa.example.invalid",
        sshUser: "cbqa"
    )

    @Test("Missing Docker socket names Docker and the socket, not Docker Desktop config")
    func missingDockerSocket() {
        let message = userFriendlyConnectionErrorMessage(for: DockerAPIError.socketNotFound("/var/run/docker.sock"))
        #expect(message == "Docker is not running. Start Docker and try again. No socket at /var/run/docker.sock.")
        #expect(!message.contains("not configured"))
    }

    @Test("Missing Podman socket names Podman and the socket path")
    func missingPodmanSocket() {
        let message = userFriendlyConnectionErrorMessage(
            for: DockerAPIError.socketNotFound("/tmp/qa/podman.sock"),
            host: podmanSocketHost
        )
        #expect(message.hasPrefix("Podman is not running. Start the Podman machine and try again."))
        #expect(message.contains("/tmp/qa/podman.sock"))
        #expect(!message.contains("Docker"))
    }

    @Test("Socket permission error shows the access-denied message for the runtime")
    func permissionDenied() {
        let message = userFriendlyConnectionErrorMessage(for: DockerAPIError.unauthorized, host: podmanSocketHost)
        #expect(message == "Access denied. Check Podman permissions.")
    }

    @Test("Invalid configuration keeps its own message")
    func invalidConfiguration() {
        let error = DockerAPIError.invalidConfiguration("Missing socket path")
        #expect(userFriendlyConnectionErrorMessage(for: error) == error.localizedDescription)
    }

    @Test("SSH failures name the host and classify the first stderr line")
    func sshFailureClasses() {
        let cases: [(String, String)] = [
            ("cbqa@qa: Permission denied (publickey).\nmore", "Authentication failed"),
            ("Host key verification failed.", "Host key verification failed"),
            ("ssh: connect to host qa port 22: Connection refused", "Connection refused")
        ]
        for (stderr, expected) in cases {
            let message = userFriendlyConnectionErrorMessage(
                for: DockerAPIError.sshConnectionFailed(stderr),
                host: sshHost
            )
            #expect(message.hasPrefix("Can't reach QA Runtime over SSH."))
            #expect(message.contains(expected))
            #expect(!message.contains("more"))
        }

        let empty = userFriendlyConnectionErrorMessage(for: DockerAPIError.sshConnectionFailed(""), host: sshHost)
        #expect(empty == "Can't reach QA Runtime over SSH.")
    }

    @Test("Unclassified SSH stderr keeps only the first non-empty line")
    func sshUnclassifiedFirstLine() {
        let message = sshFailureMessage(hostName: "box", stderr: "\n  ssh: Could not resolve hostname box\nsecond line")
        #expect(message == "Can't reach box over SSH. ssh: Could not resolve hostname box")
    }

    @Test("SSH failure classifier")
    func sshFailureClassifier() {
        #expect(SSHFailureClass(stderrLine: "Too many authentication failures") == .authentication)
        #expect(SSHFailureClass(stderrLine: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!") == .hostKey)
        #expect(SSHFailureClass(stderrLine: "connect: Connection refused") == .refused)
        #expect(SSHFailureClass(stderrLine: "Operation timed out") == .other)
    }
}
