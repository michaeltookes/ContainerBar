import Foundation
import Testing
@testable import DockerBarCore

@Suite("DockerContainer Tests")
struct DockerContainerTests {

    @Test("Display name strips leading slash")
    func displayNameStripsSlash() {
        let container = DockerContainer(
            id: "abc123",
            names: ["/my-container"],
            image: "nginx",
            imageID: "sha256:abc",
            command: "nginx",
            created: Date(),
            state: .running,
            status: "Up 1 hour",
            ports: [],
            labels: [:],
            networkMode: nil
        )

        #expect(container.displayName == "my-container")
    }

    @Test("Display name falls back to truncated ID when no names")
    func displayNameFallsBackToId() {
        let container = DockerContainer(
            id: "abc123def456ghi789",
            names: [],
            image: "nginx",
            imageID: "sha256:abc",
            command: "nginx",
            created: Date(),
            state: .running,
            status: "Up 1 hour",
            ports: [],
            labels: [:],
            networkMode: nil
        )

        #expect(container.displayName == "abc123def456")
    }

    @Test("Container state isActive returns correct values")
    func containerStateIsActive() {
        #expect(ContainerState.running.isActive == true)
        #expect(ContainerState.paused.isActive == true)
        #expect(ContainerState.restarting.isActive == true)
        #expect(ContainerState.exited.isActive == false)
        #expect(ContainerState.created.isActive == false)
        #expect(ContainerState.dead.isActive == false)
    }

    @Test("Container state display colors are set correctly")
    func containerStateDisplayColors() {
        #expect(ContainerState.running.displayColor == "green")
        #expect(ContainerState.paused.displayColor == "yellow")
        #expect(ContainerState.restarting.displayColor == "orange")
        #expect(ContainerState.exited.displayColor == "red")
        #expect(ContainerState.dead.displayColor == "red")
        #expect(ContainerState.created.displayColor == "gray")
    }
}

@Suite("PortMapping Tests")
struct PortMappingTests {

    @Test("Port mapping stores values correctly")
    func portMappingValues() {
        let mapping = PortMapping(
            privatePort: 80,
            publicPort: 8080,
            type: "tcp",
            ip: "0.0.0.0"
        )

        #expect(mapping.privatePort == 80)
        #expect(mapping.publicPort == 8080)
        #expect(mapping.type == "tcp")
        #expect(mapping.ip == "0.0.0.0")
    }
}
