import Testing
@testable import ContainerBar
@testable import ContainerBarCore

@Suite("ContainerBar App Tests")
struct ContainerBarTests {

    @Test("App can be initialized")
    func appInitialization() {
        // Basic smoke test - more comprehensive tests will be added
        // once we have the actual Docker API client
        #expect(true, "ContainerBar app module compiles and links successfully")
    }

    @Test("Connection status shows connecting before the first refresh completes")
    func connectionStatusShowsConnectingDuringInitialLoad() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: true,
            lastRefreshAt: nil,
            connectionError: nil
        )

        #expect(presentation.state == .connecting)
        #expect(presentation.title == "Connecting to Beelink Server")
        #expect(presentation.detail == nil)
    }

    @Test("Connection status surfaces host-specific errors")
    func connectionStatusShowsErrorDetails() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            lastRefreshAt: nil,
            connectionError: "Failed to connect to Docker daemon"
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Connection failed for Beelink Server")
        #expect(presentation.detail == "Failed to connect to Docker daemon")
    }

    @Test("Connection status stays disconnected when idle in manual mode")
    func connectionStatusDoesNotShowConnectingWithoutRefresh() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            lastRefreshAt: nil,
            connectionError: nil
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Disconnected from Beelink Server")
        #expect(presentation.detail == nil)
    }
}

// TODO: Add tests for:
// - ContainerStore refresh behavior
// - SettingsStore persistence
// - StatusItemController menu building
// These require @MainActor testing support
