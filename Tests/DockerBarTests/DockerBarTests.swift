import Testing
@testable import DockerBar
@testable import DockerBarCore

@Suite("DockerBar App Tests")
struct DockerBarTests {

    @Test("App can be initialized")
    func appInitialization() {
        // Basic smoke test - more comprehensive tests will be added
        // once we have the actual Docker API client
        #expect(true, "DockerBar app module compiles and links successfully")
    }
}

// TODO: Add tests for:
// - ContainerStore refresh behavior
// - SettingsStore persistence
// - StatusItemController menu building
// These require @MainActor testing support
